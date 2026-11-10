-- Birthdayly — datas especiais
--
-- Datas que se repetem todos os anos e não são aniversários de nascimento:
-- casamento, namoro, Dia da Mãe, a data de alguém que já partiu… Cada uma é
-- de um utilizador e pode estar ligada a uma das suas pessoas.
create table special_dates (
  id             uuid primary key default gen_random_uuid(),
  user_id        uuid not null references users (id) on delete cascade,
  title          text not null check (char_length(title) between 1 and 120),
  kind           text not null default 'other' check (kind in ('couple', 'wedding', 'family', 'memorial', 'other')),
  day            smallint not null check (day between 1 and 31),
  month          smallint not null check (month between 1 and 12),
  year           smallint check (year between 1900 and 2100),
  person_id      uuid references people (id) on delete set null,
  notes          text not null default '',
  reminder_days  smallint[],              -- null = usar as preferências do perfil
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);
create index special_dates_user_idx on special_dates (user_id);

create trigger special_dates_touch before update on special_dates
  for each row execute function touch_updated_at();

-- A pessoa (se houver) tem de ser do mesmo utilizador.
create or replace function check_special_date_person()
returns trigger language plpgsql as $$
begin
  if new.person_id is not null
     and not exists (select 1 from people where id = new.person_id and user_id = new.user_id) then
    raise exception 'person not found' using errcode = '42501';
  end if;
  return new;
end $$;

create trigger special_dates_owner_refs before insert or update on special_dates
  for each row execute function check_special_date_person();
