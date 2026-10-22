-- Birthdayly — interesse no Birthdayly+
--
-- A subscrição ainda não se vende (falta a compra dentro da app da Apple e da
-- Google). Até lá, o ecrã de planos regista quem a quer e com que periodicidade,
-- para medir a procura antes de a construir.
create table plus_interest (
  user_id     uuid primary key references users (id) on delete cascade,
  plan        text not null check (plan in ('monthly', 'yearly')),
  created_at  timestamptz not null default now()
);
