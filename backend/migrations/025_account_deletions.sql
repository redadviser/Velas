-- Birthdayly — apagar a conta só depois de confirmar por email.
--
-- Pedir o apagamento (na app ou na página /legal/apagar-conta) envia um email
-- com um link; a conta só é apagada quando a pessoa abre o link e confirma.
-- Um pedido ativo por conta (um pedido novo substitui o anterior).
create table account_deletions (
  token_hash  text primary key,
  user_id     uuid not null unique references users (id) on delete cascade,
  expires_at  timestamptz not null,
  created_at  timestamptz not null default now()
);
