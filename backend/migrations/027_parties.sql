-- Birthdayly — festas surpresa
--
-- Quem cria a festa convida pessoas (por código ou à mão, sem conta), que
-- respondem se vão e dividem tarefas. A festa só é vista por quem a criou e
-- pelos convidados com conta: o aniversariante não é convidado e não a vê.
-- As permissões são verificadas na API (modules/parties/parties.service.ts).
create table parties (
  id              uuid primary key default gen_random_uuid(),
  created_by      uuid not null references users (id) on delete cascade,
  title           text not null check (char_length(title) between 1 and 120),
  celebrant_name  text not null check (char_length(celebrant_name) between 1 and 120),
  person_id       uuid references people (id) on delete set null,
  starts_at       timestamptz,
  place           text not null default '' check (char_length(place) <= 200),
  notes           text not null default '' check (char_length(notes) <= 2000),
  -- 40 bits aleatórios; suficiente para não ser adivinhado.
  invite_code     text not null unique default upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 10)),
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);
create index parties_created_by_idx on parties (created_by);

create trigger parties_touch before update on parties
  for each row execute function touch_updated_at();

create table party_guests (
  id            uuid primary key default gen_random_uuid(),
  party_id      uuid not null references parties (id) on delete cascade,
  user_id       uuid references users (id) on delete cascade,   -- null = convidado sem conta
  display_name  text not null check (char_length(display_name) between 1 and 80),
  username      text,
  rsvp          text not null default 'pending' check (rsvp in ('pending', 'yes', 'maybe', 'no')),
  created_at    timestamptz not null default now(),
  unique (party_id, user_id)
);
create index party_guests_party_idx on party_guests (party_id);
create index party_guests_user_idx on party_guests (user_id);

create table party_tasks (
  id           uuid primary key default gen_random_uuid(),
  party_id     uuid not null references parties (id) on delete cascade,
  title        text not null check (char_length(title) between 1 and 200),
  assignee_id  uuid references party_guests (id) on delete set null,
  done         boolean not null default false,
  created_at   timestamptz not null default now()
);
create index party_tasks_party_idx on party_tasks (party_id);
