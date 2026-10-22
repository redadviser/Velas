-- Birthdayly — segurança: bloquear e denunciar utilizadores
--
-- Bloquear: deixam de ser amigos (e os aniversários ligados desligam-se, ver
-- 012), quem foi bloqueado não pode pedir amizade nem escrever em privado, e
-- quem bloqueou deixa de ver as mensagens dele nos grupos e a conversa privada.
-- Denunciar: fica registado para a equipa analisar (e vai por email para
-- MODERATION_EMAIL, se estiver definido). As lojas exigem as duas coisas em
-- apps com conteúdo entre utilizadores.
create table user_blocks (
  blocker_id  uuid not null references users (id) on delete cascade,
  blocked_id  uuid not null references users (id) on delete cascade,
  created_at  timestamptz not null default now(),
  primary key (blocker_id, blocked_id),
  check (blocker_id <> blocked_id)
);
create index user_blocks_blocked_idx on user_blocks (blocked_id);

-- Um dos dois bloqueou o outro.
create or replace function is_blocked(a uuid, b uuid)
returns boolean language sql stable as $$
  select exists (
    select 1 from user_blocks
    where (blocker_id = a and blocked_id = b) or (blocker_id = b and blocked_id = a)
  );
$$;

create table user_reports (
  id           uuid primary key default gen_random_uuid(),
  reporter_id  uuid references users (id) on delete set null,
  reported_id  uuid references users (id) on delete set null,
  reason       text not null check (reason in ('spam', 'harassment', 'inappropriate', 'impersonation', 'underage', 'other')),
  details      text not null default '' check (char_length(details) <= 500),
  -- A mensagem denunciada, se a denúncia partiu de uma (copiada, para não se perder se for apagada).
  message_id   uuid,
  message_body text,
  status       text not null default 'open' check (status in ('open', 'reviewed', 'dismissed')),
  created_at   timestamptz not null default now()
);
create index user_reports_status_idx on user_reports (status, created_at);
