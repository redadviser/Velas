-- Birthdayly — aniversários criados (limite do plano Grátis)
--
-- O plano Grátis conta os aniversários criados, não os que estão guardados:
-- apagar um não liberta espaço (senão bastava apagar e criar outro). O contador
-- começa com os que cada conta já tem e sobe a cada inserção em people.
alter table profiles add column people_created integer not null default 0;

update profiles p set people_created = (select count(*) from people where user_id = p.id);

create or replace function count_person_created()
returns trigger language plpgsql as $$
begin
  update profiles set people_created = people_created + 1 where id = new.user_id;
  return new;
end $$;

create trigger people_count_created after insert on people
  for each row execute function count_person_created();
