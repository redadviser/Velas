-- Birthdayly — aniversários ligados a amigos da app
--
-- Um aniversário guardado (people) pode ficar ligado à conta de um amigo que
-- já está na Birthdayly. Assim a app sabe para que mural mandar os parabéns,
-- com quem abrir a conversa, etc. Só se liga a amigos, e cada amigo só a um
-- aniversário do mesmo utilizador. Deixar de ser amigos desfaz a ligação.
alter table people add column linked_user_id uuid references users (id) on delete set null;
create unique index people_linked_user_key on people (user_id, linked_user_id) where linked_user_id is not null;

create or replace function check_person_link()
returns trigger language plpgsql as $$
begin
  if new.linked_user_id is null then
    return new;
  end if;
  -- Só se verifica quando a ligação muda (uma ligação antiga não impede editar o resto).
  if tg_op = 'UPDATE' then
    if new.linked_user_id is not distinct from old.linked_user_id then
      return new;
    end if;
  end if;
  if new.linked_user_id = new.user_id or not are_friends(new.user_id, new.linked_user_id) then
    raise exception 'not_friends' using errcode = '42501';
  end if;
  return new;
end $$;

create trigger people_link before insert or update on people
  for each row execute function check_person_link();

create or replace function unlink_people_on_unfriend()
returns trigger language plpgsql as $$
begin
  update people set linked_user_id = null
  where (user_id = old.requester_id and linked_user_id = old.addressee_id)
     or (user_id = old.addressee_id and linked_user_id = old.requester_id);
  return old;
end $$;

create trigger friendships_unlink_people after delete on friendships
  for each row execute function unlink_people_on_unfriend();
