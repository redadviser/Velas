-- Birthdayly — pedir aniversários por link, sem spam
--
-- As respostas deixam de entrar diretamente na lista: ficam pendentes até o
-- dono as aceitar (ou ignorar). Assim, nomes inventados num grupo nunca chegam
-- à lista de aniversários. O link pode ser desligado e expira ao fim de 30 dias.
alter table birthday_requests
  add column enabled boolean not null default true,
  add column expires_at timestamptz not null default now() + interval '30 days';

create table birthday_answers (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid not null references users (id) on delete cascade,
  name         text not null check (char_length(name) between 1 and 80),
  birth_day    smallint not null check (birth_day between 1 and 31),
  birth_month  smallint not null check (birth_month between 1 and 12),
  birth_year   smallint check (birth_year between 1900 and 2100),
  -- Identificador aleatório do telemóvel de quem respondeu (guardado pela página):
  -- uma segunda resposta do mesmo telemóvel substitui a primeira.
  device       text not null check (char_length(device) between 8 and 64),
  status       text not null default 'pending' check (status in ('pending', 'accepted', 'ignored')),
  created_at   timestamptz not null default now()
);
create index birthday_answers_user_idx on birthday_answers (user_id, status, created_at);
create unique index birthday_answers_device_key on birthday_answers (user_id, device) where status = 'pending';
