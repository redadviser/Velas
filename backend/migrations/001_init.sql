-- Velas — esquema inicial (PostgreSQL 14+)
--
-- A API abre uma transação por pedido e define o utilizador autenticado com
--   select set_config('app.user_id', '<uuid>', true);
-- As funções e triggers leem-no com app.uid(). O isolamento entre
-- utilizadores é garantido nas queries da API (where user_id = ...) e,
-- nas regras mais finas dos grupos, pelos triggers destas migrações.

create schema if not exists app;

create or replace function app.uid()
returns uuid language sql stable as $$
  select nullif(current_setting('app.user_id', true), '')::uuid
$$;

-- ---------------------------------------------------------------------------
-- Contas
-- ---------------------------------------------------------------------------
create table users (
  id              uuid primary key default gen_random_uuid(),
  email           text not null check (email ~ '^[^@\s]+@[^@\s]+\.[^@\s]+$'),
  password_hash   text,                 -- null: conta criada só com o Google
  google_sub      text unique,          -- identificador estável da conta Google
  email_verified  boolean not null default false,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);
create unique index users_email_key on users (lower(email));

-- Sessões: só se guarda o hash do refresh token.
create table refresh_tokens (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references users (id) on delete cascade,
  token_hash  text not null unique,
  expires_at  timestamptz not null,
  created_at  timestamptz not null default now()
);
create index refresh_tokens_user_idx on refresh_tokens (user_id);

create table password_resets (
  token_hash  text primary key,
  user_id     uuid not null references users (id) on delete cascade,
  expires_at  timestamptz not null,
  used_at     timestamptz,
  created_at  timestamptz not null default now()
);
create index password_resets_user_idx on password_resets (user_id);

-- ---------------------------------------------------------------------------
-- Perfis e preferências (RF20)
-- ---------------------------------------------------------------------------
create table profiles (
  id                     uuid primary key references users (id) on delete cascade,
  display_name           text not null default '',
  username               text unique
    check (username ~ '^[a-z0-9._]{3,20}$' and username !~ '^[._]' and username !~ '[._]$'),
  phone                  text unique check (phone ~ '^\+[1-9][0-9]{7,14}$'),
  notifications_enabled  boolean not null default true,
  reminder_hour          smallint not null default 9 check (reminder_hour between 0 and 23),
  reminder_minute        smallint not null default 0 check (reminder_minute between 0 and 59),
  default_reminder_days  smallint[] not null default '{0,1}',
  -- Privados: só são revelados, através de group_payee(), aos membros de um
  -- grupo em que este utilizador é o comprador.
  payment_methods        jsonb not null default '{}'::jsonb,
  created_at             timestamptz not null default now(),
  updated_at             timestamptz not null default now()
);

comment on column profiles.phone is
  'Formato E.164. Ainda não verificado por SMS: o convite mostra nome e username para confirmar a pessoa.';

-- ---------------------------------------------------------------------------
-- Categorias (RF11)
-- ---------------------------------------------------------------------------
create table categories (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references users (id) on delete cascade,
  name        text not null check (char_length(name) between 1 and 40),
  color       smallint not null default 0,
  sort        smallint not null default 0,
  created_at  timestamptz not null default now()
);
create index categories_user_idx on categories (user_id);

-- ---------------------------------------------------------------------------
-- Pessoas / aniversários (RF04–RF06, RF12)
-- ---------------------------------------------------------------------------
create table people (
  id             uuid primary key default gen_random_uuid(),
  user_id        uuid not null references users (id) on delete cascade,
  name           text not null check (char_length(name) between 1 and 120),
  birth_day      smallint not null check (birth_day between 1 and 31),
  birth_month    smallint not null check (birth_month between 1 and 12),
  birth_year     smallint check (birth_year between 1900 and 2100),
  relation       text not null default '',
  category_id    uuid references categories (id) on delete set null,
  photo_path     text,
  notes          text not null default '',
  gift_budget    numeric(10, 2) check (gift_budget >= 0),
  reminder_days  smallint[],              -- null = usar as preferências do perfil
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);
create index people_user_idx on people (user_id);
create index people_birthday_idx on people (user_id, birth_month, birth_day);

-- ---------------------------------------------------------------------------
-- Ideias de presentes (RF16–RF18)
-- ---------------------------------------------------------------------------
create table gift_ideas (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references users (id) on delete cascade,
  person_id   uuid not null references people (id) on delete cascade,
  title       text not null check (char_length(title) between 1 and 200),
  price       numeric(10, 2) check (price >= 0),
  link        text not null default '',
  notes       text not null default '',
  purchased   boolean not null default false,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
create index gift_ideas_user_idx on gift_ideas (user_id);
create index gift_ideas_person_idx on gift_ideas (person_id);

-- ---------------------------------------------------------------------------
-- Mensagens de aniversário (RF14)
-- ---------------------------------------------------------------------------
create table messages (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references users (id) on delete cascade,
  person_id   uuid not null references people (id) on delete cascade,
  body        text not null check (char_length(body) between 1 and 1000),
  tone        text not null default '',
  updated_at  timestamptz not null default now()
);
create index messages_user_idx on messages (user_id);
create index messages_person_idx on messages (person_id);

-- ---------------------------------------------------------------------------
-- updated_at automático
-- ---------------------------------------------------------------------------
create or replace function touch_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at := now();
  return new;
end $$;

create trigger users_touch      before update on users      for each row execute function touch_updated_at();
create trigger profiles_touch   before update on profiles   for each row execute function touch_updated_at();
create trigger people_touch     before update on people     for each row execute function touch_updated_at();
create trigger gift_ideas_touch before update on gift_ideas for each row execute function touch_updated_at();
create trigger messages_touch   before update on messages   for each row execute function touch_updated_at();

-- ---------------------------------------------------------------------------
-- Integridade entre tabelas: impede ligar dados a pessoas/categorias de outro
-- utilizador, mesmo que alguém adivinhe um UUID.
-- ---------------------------------------------------------------------------
create or replace function check_owner_refs()
returns trigger language plpgsql as $$
begin
  if tg_table_name in ('gift_ideas', 'messages') then
    if not exists (select 1 from people where id = new.person_id and user_id = new.user_id) then
      raise exception 'person not found' using errcode = '42501';
    end if;
  elsif tg_table_name = 'people' and new.category_id is not null then
    if not exists (select 1 from categories where id = new.category_id and user_id = new.user_id) then
      raise exception 'category not found' using errcode = '42501';
    end if;
  end if;
  return new;
end $$;

create trigger people_owner_refs     before insert or update on people     for each row execute function check_owner_refs();
create trigger gift_ideas_owner_refs before insert or update on gift_ideas for each row execute function check_owner_refs();
create trigger messages_owner_refs   before insert or update on messages   for each row execute function check_owner_refs();

-- Verificação antes do registo (sem sessão).
create or replace function signup_check(p_username text, p_phone text)
returns jsonb language sql stable as $$
  select jsonb_build_object(
    'username_taken', exists (select 1 from profiles where username = lower(p_username)),
    'phone_taken', p_phone is not null and p_phone <> '' and exists (select 1 from profiles where phone = p_phone)
  );
$$;
