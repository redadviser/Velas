-- Velas — prendas em grupo e convites
--
-- Um grupo junta várias pessoas para comprar uma prenda. O administrador
-- (quem cria) define o valor e a divisão; quem compra recebe o dinheiro.
-- Se não houver comprador definido, é o administrador.
--
-- A app não movimenta dinheiro: mostra os dados de pagamento do comprador
-- (MB WAY, IBAN, Revolut, PayPal) e regista quem já pagou e quem confirmou.
--
-- Quem vê e quem altera cada linha é verificado na API com as funções
-- is_group_admin() / is_group_member(); as regras por coluna estão nos
-- triggers guard_* abaixo.

-- ---------------------------------------------------------------------------
-- Tabelas
-- ---------------------------------------------------------------------------
create table gift_groups (
  id                uuid primary key default gen_random_uuid(),
  created_by        uuid not null references users (id) on delete cascade,
  title             text not null check (char_length(title) between 1 and 120),
  celebrant_name    text not null check (char_length(celebrant_name) between 1 and 120),
  celebrant_day     smallint check (celebrant_day between 1 and 31),
  celebrant_month   smallint check (celebrant_month between 1 and 12),
  person_id         uuid references people (id) on delete set null,
  gift_description  text not null default '',
  gift_link         text not null default '',
  target_amount     numeric(10, 2) not null check (target_amount > 0 and target_amount <= 100000),
  split_mode        text not null default 'equal' check (split_mode in ('equal', 'custom')),
  buyer_member_id   uuid,
  deadline          date,
  -- 40 bits aleatórios; suficiente para não ser adivinhado.
  invite_code       text not null unique default upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 10)),
  purchased_at      timestamptz,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now()
);
create index gift_groups_created_by_idx on gift_groups (created_by);

create table group_members (
  id               uuid primary key default gen_random_uuid(),
  group_id         uuid not null references gift_groups (id) on delete cascade,
  user_id          uuid references users (id) on delete cascade,   -- null = participante sem conta
  display_name     text not null check (char_length(display_name) between 1 and 80),
  -- Cópia do username no momento em que entrou (distingue pessoas com o mesmo nome).
  username         text,
  custom_amount    numeric(10, 2) check (custom_amount >= 0),
  paid_at          timestamptz,
  paid_method      text check (paid_method in ('mbway', 'transfer', 'revolut', 'paypal', 'cash')),
  confirmed_at     timestamptz,
  payment_methods  jsonb not null default '{}'::jsonb,              -- só para quem não tem conta
  created_at       timestamptz not null default now(),
  unique (group_id, user_id)
);
create index group_members_group_idx on group_members (group_id);
create index group_members_user_idx on group_members (user_id);

alter table gift_groups
  add constraint gift_groups_buyer_fk
  foreign key (buyer_member_id) references group_members (id) on delete set null;

create trigger gift_groups_touch before update on gift_groups
  for each row execute function touch_updated_at();

create table group_invitations (
  id                uuid primary key default gen_random_uuid(),
  group_id          uuid not null references gift_groups (id) on delete cascade,
  invited_user_id   uuid not null references users (id) on delete cascade,
  invited_by        uuid not null references users (id) on delete cascade,
  invitee_name      text not null default '',
  invitee_username  text,
  status            text not null default 'pending' check (status in ('pending', 'accepted', 'declined')),
  created_at        timestamptz not null default now(),
  responded_at      timestamptz,
  unique (group_id, invited_user_id)
);
create index group_invitations_user_idx on group_invitations (invited_user_id) where status = 'pending';

-- ---------------------------------------------------------------------------
-- Funções auxiliares
-- ---------------------------------------------------------------------------
create or replace function is_group_admin(gid uuid)
returns boolean language sql stable as $$
  select exists (select 1 from gift_groups where id = gid and created_by = app.uid());
$$;

create or replace function is_group_member(gid uuid)
returns boolean language sql stable as $$
  select is_group_admin(gid)
      or exists (select 1 from group_members where group_id = gid and user_id = app.uid());
$$;

-- Utilizador que compra a prenda (o administrador, se não houver comprador).
create or replace function group_buyer_user(gid uuid)
returns uuid language sql stable as $$
  select coalesce(
    (select m.user_id from gift_groups g join group_members m on m.id = g.buyer_member_id where g.id = gid),
    (select g.created_by from gift_groups g where g.id = gid and g.buyer_member_id is null)
  );
$$;

-- ---------------------------------------------------------------------------
-- Regras de alteração por coluna
-- ---------------------------------------------------------------------------
create or replace function guard_gift_group()
returns trigger language plpgsql as $$
declare
  uid uuid := app.uid();
begin
  if uid is null then return new; end if;  -- tarefas internas

  if new.created_by is distinct from old.created_by or new.invite_code is distinct from old.invite_code then
    raise exception 'immutable field' using errcode = '42501';
  end if;

  if new.buyer_member_id is not null
     and not exists (select 1 from group_members where id = new.buyer_member_id and group_id = new.id) then
    raise exception 'buyer must belong to the group' using errcode = '23514';
  end if;

  -- O comprador (não administrador) só pode marcar a prenda como comprada.
  -- Exceção: se o comprador sair do grupo ou eliminar a conta, a FK limpa
  -- buyer_member_id (ON DELETE SET NULL) e o administrador volta a comprar.
  if old.created_by <> uid then
    if (to_jsonb(new) - 'purchased_at' - 'updated_at' - 'buyer_member_id')
         is distinct from (to_jsonb(old) - 'purchased_at' - 'updated_at' - 'buyer_member_id')
       or (new.buyer_member_id is distinct from old.buyer_member_id
           and not (new.buyer_member_id is null
                    and not exists (select 1 from group_members where id = old.buyer_member_id))) then
      raise exception 'only the admin can edit the group' using errcode = '42501';
    end if;
  end if;
  return new;
end $$;

create trigger gift_groups_guard before update on gift_groups
  for each row execute function guard_gift_group();

create or replace function guard_group_member()
returns trigger language plpgsql as $$
declare
  uid uuid := app.uid();
  is_admin boolean;
  is_buyer boolean;
  is_self boolean;
begin
  if uid is null then return new; end if;

  -- coalesce: com user_id nulo (participante sem conta) a comparação daria
  -- NULL e as verificações abaixo seriam ignoradas.
  is_admin := coalesce(is_group_admin(old.group_id), false);
  is_buyer := coalesce(group_buyer_user(old.group_id) = uid, false);
  is_self  := coalesce(old.user_id = uid, false);

  if new.group_id is distinct from old.group_id or new.user_id is distinct from old.user_id
     or new.created_at is distinct from old.created_at then
    raise exception 'immutable field' using errcode = '42501';
  end if;

  -- A cópia do username só muda pela sincronização com o perfil.
  if new.username is distinct from old.username
     and new.username is distinct from (select username from profiles where id = old.user_id) then
    raise exception 'immutable field' using errcode = '42501';
  end if;

  if not is_admin and (new.custom_amount is distinct from old.custom_amount
                       or new.payment_methods is distinct from old.payment_methods) then
    raise exception 'only the admin can change amounts' using errcode = '42501';
  end if;

  if not (is_admin or is_self) and new.display_name is distinct from old.display_name then
    raise exception 'not allowed' using errcode = '42501';
  end if;

  if not (is_admin or is_self or is_buyer)
     and (new.paid_at is distinct from old.paid_at or new.paid_method is distinct from old.paid_method) then
    raise exception 'not allowed' using errcode = '42501';
  end if;

  -- Só quem recebe o dinheiro (ou o administrador) confirma ou anula uma
  -- confirmação; um membro só pode anular o "já paguei" antes de confirmado.
  if not (is_admin or is_buyer) and new.confirmed_at is distinct from old.confirmed_at then
    raise exception 'only the buyer can confirm payments' using errcode = '42501';
  end if;
  return new;
end $$;

create trigger group_members_guard before update on group_members
  for each row execute function guard_group_member();

-- O administrador não pode sair nem ser removido do próprio grupo.
create or replace function guard_group_member_delete()
returns trigger language plpgsql as $$
begin
  if exists (select 1 from gift_groups where id = old.group_id and created_by = old.user_id) then
    raise exception 'the admin cannot leave the group' using errcode = '42501';
  end if;
  return old;
end $$;

create trigger group_members_guard_delete before delete on group_members
  for each row execute function guard_group_member_delete();

-- O username do membro vem sempre do perfil.
create or replace function fill_member_username()
returns trigger language plpgsql as $$
begin
  if new.user_id is not null then
    new.username := (select username from profiles where id = new.user_id);
  end if;
  return new;
end $$;

create trigger group_members_fill_username before insert on group_members
  for each row execute function fill_member_username();

create or replace function sync_member_username()
returns trigger language plpgsql as $$
begin
  if new.username is distinct from old.username then
    update group_members set username = new.username where user_id = new.id;
  end if;
  return new;
end $$;

create trigger profiles_sync_member_username after update of username on profiles
  for each row execute function sync_member_username();

-- Quem entra pelo link fica com o convite (se existia) marcado como aceite.
create or replace function accept_invite_on_join()
returns trigger language plpgsql as $$
begin
  if new.user_id is not null then
    update group_invitations set status = 'accepted', responded_at = now()
    where group_id = new.group_id and invited_user_id = new.user_id and status = 'pending';
  end if;
  return new;
end $$;

create trigger group_members_accept_invite after insert on group_members
  for each row execute function accept_invite_on_join();

-- ---------------------------------------------------------------------------
-- Operações chamadas pela API
-- ---------------------------------------------------------------------------
create or replace function join_gift_group(code text, display_name text)
returns uuid language plpgsql as $$
declare
  uid uuid := app.uid();
  g record;
  fallback text;
begin
  if uid is null then raise exception 'not authenticated' using errcode = '42501'; end if;

  select id, purchased_at into g from gift_groups where invite_code = upper(trim(code));
  if not found then raise exception 'invalid_code' using errcode = 'P0002'; end if;
  if g.purchased_at is not null then raise exception 'group_closed' using errcode = 'P0001'; end if;

  select p.display_name into fallback from profiles p where p.id = uid;
  insert into group_members (group_id, user_id, display_name)
  values (g.id, uid, coalesce(nullif(trim(display_name), ''), nullif(fallback, ''), 'Participante'))
  on conflict (group_id, user_id) do nothing;
  return g.id;
end $$;

-- Dados de pagamento de quem compra, apenas para membros do grupo.
create or replace function group_payee(gid uuid)
returns jsonb language plpgsql stable as $$
declare
  buyer record;
begin
  if not is_group_member(gid) then
    raise exception 'not a member' using errcode = '42501';
  end if;

  select m.user_id, m.payment_methods into buyer
  from gift_groups g
  join group_members m on m.id = g.buyer_member_id
  where g.id = gid;

  if not found then
    -- Sem comprador definido: é o administrador.
    return (select p.payment_methods from gift_groups g join profiles p on p.id = g.created_by where g.id = gid);
  end if;
  if buyer.user_id is null then
    return buyer.payment_methods;
  end if;
  return (select p.payment_methods from profiles p where p.id = buyer.user_id);
end $$;

-- Procurar uma conta por email, telemóvel ou username.
create or replace function find_user(identifier text)
returns table (user_id uuid, display_name text, username text)
language plpgsql stable as $$
declare
  q text := trim(identifier);
begin
  if app.uid() is null then raise exception 'not authenticated' using errcode = '42501'; end if;

  if q ~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then
    return query
      select p.id, p.display_name, p.username
      from users u join profiles p on p.id = u.id
      where lower(u.email) = lower(q);
  elsif q ~ '^\+[1-9][0-9]{7,14}$' then
    return query select p.id, p.display_name, p.username from profiles p where p.phone = q;
  else
    return query select p.id, p.display_name, p.username from profiles p where p.username = lower(ltrim(q, '@'));
  end if;
end $$;

create or replace function invite_to_group(gid uuid, invitee uuid)
returns text language plpgsql as $$
declare
  p record;
  existing text;
begin
  if not is_group_admin(gid) then
    raise exception 'only the admin can invite' using errcode = '42501';
  end if;
  if exists (select 1 from gift_groups where id = gid and purchased_at is not null) then
    return 'group_closed';
  end if;
  if exists (select 1 from group_members where group_id = gid and user_id = invitee) then
    return 'already_member';
  end if;

  select display_name, username into p from profiles where id = invitee;
  if not found then return 'not_found'; end if;

  select status into existing from group_invitations where group_id = gid and invited_user_id = invitee;
  if existing = 'pending' then return 'already_invited'; end if;

  -- Um convite recusado pode ser reenviado.
  insert into group_invitations (group_id, invited_user_id, invited_by, invitee_name, invitee_username)
  values (gid, invitee, app.uid(), p.display_name, p.username)
  on conflict (group_id, invited_user_id) do update
    set status = 'pending', invited_by = excluded.invited_by, created_at = now(), responded_at = null,
        invitee_name = excluded.invitee_name, invitee_username = excluded.invitee_username;
  return 'invited';
end $$;

-- Convites pendentes do utilizador, com o mínimo para decidir.
create or replace function my_invitations()
returns jsonb language sql stable as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', i.id,
    'group_id', g.id,
    'title', g.title,
    'celebrant_name', g.celebrant_name,
    'inviter_name', inviter.display_name,
    'member_count', (select count(*) from group_members m where m.group_id = g.id),
    'created_at', i.created_at
  ) order by i.created_at desc), '[]'::jsonb)
  from group_invitations i
  join gift_groups g on g.id = i.group_id
  left join profiles inviter on inviter.id = i.invited_by
  where i.invited_user_id = app.uid() and i.status = 'pending' and g.purchased_at is null;
$$;

create or replace function respond_invitation(inv uuid, accept boolean)
returns uuid language plpgsql as $$
declare
  i record;
  name text;
begin
  select * into i from group_invitations where id = inv and invited_user_id = app.uid() and status = 'pending';
  if not found then raise exception 'invitation_not_found' using errcode = 'P0002'; end if;

  update group_invitations set status = case when accept then 'accepted' else 'declined' end, responded_at = now()
  where id = inv;
  if not accept then return null; end if;

  if exists (select 1 from gift_groups where id = i.group_id and purchased_at is not null) then
    raise exception 'group_closed' using errcode = 'P0001';
  end if;
  select coalesce(nullif(display_name, ''), 'Participante') into name from profiles where id = app.uid();
  insert into group_members (group_id, user_id, display_name) values (i.group_id, app.uid(), name)
  on conflict (group_id, user_id) do nothing;
  return i.group_id;
end $$;

-- Pré-visualização do grupo a partir do link de convite.
create or replace function group_preview(code text)
returns jsonb language plpgsql stable as $$
declare
  g record;
begin
  if app.uid() is null then raise exception 'not authenticated' using errcode = '42501'; end if;
  select gg.*, p.display_name as admin_name into g
  from gift_groups gg left join profiles p on p.id = gg.created_by
  where gg.invite_code = upper(trim(code));
  if not found then raise exception 'invalid_code' using errcode = 'P0002'; end if;
  return jsonb_build_object(
    'id', g.id,
    'title', g.title,
    'celebrant_name', g.celebrant_name,
    'admin_name', g.admin_name,
    'member_count', (select count(*) from group_members where group_id = g.id),
    'already_member', is_group_member(g.id),
    'closed', g.purchased_at is not null
  );
end $$;
