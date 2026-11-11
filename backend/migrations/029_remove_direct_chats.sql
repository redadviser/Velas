-- Birthdayly — sem conversas privadas
--
-- A app deixou de ter conversas 1 para 1: fica só a conversa de cada prenda em
-- grupo. Apagam-se as privadas (as mensagens, leituras e preferências vão em
-- cascata) e passa a ser impossível criar novas. Os amigos e o mural ficam.
delete from conversations where group_id is null;

drop index if exists conversations_direct_key;
drop index if exists conversations_user_b_idx;
alter table conversations add constraint conversations_group_only check (group_id is not null);
