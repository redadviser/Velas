-- Códigos de convite mais fáceis de ler e ditar: 8 caracteres de um alfabeto
-- sem ambiguidades (sem 0/O nem 1/I), mostrados como "K7P2 QX9M". Continuam a
-- ter 40 bits aleatórios. Os grupos existentes mantêm o código que já têm.
create or replace function new_invite_code() returns text
language sql volatile as $$
  -- Bytes de um UUID v4 sem os bits fixos de versão e variante (6 e 8).
  select string_agg(substr('ABCDEFGHJKLMNPQRSTUVWXYZ23456789', get_byte(b, i) % 32 + 1, 1), '' order by i)
  from (select uuid_send(gen_random_uuid()) as b) r, unnest(array[0, 1, 2, 3, 4, 5, 10, 11]) as i
$$;

alter table gift_groups alter column invite_code set default new_invite_code();
