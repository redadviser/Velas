-- Birthdayly — definições das conversas
--
-- Privacidade (como no WhatsApp: quem desliga também deixa de ver o dos outros):
--   show_presence     "online" e "visto por último"
--   read_receipts     "vista" / confirmações de leitura
--   typing_indicator  "a escrever…"
-- Notificações (a app respeita-as já; servem também para o push, mais tarde):
--   message_notifications, message_previews
alter table profiles
  add column show_presence          boolean not null default true,
  add column read_receipts          boolean not null default true,
  add column typing_indicator       boolean not null default true,
  add column message_notifications  boolean not null default true,
  add column message_previews       boolean not null default true;

-- Preferências de cada pessoa em cada conversa.
create table conversation_prefs (
  conversation_id  uuid not null references conversations (id) on delete cascade,
  user_id          uuid not null references users (id) on delete cascade,
  -- Silenciada até esta hora ("sempre" = 9999-12-31).
  muted_until      timestamptz,
  -- Fixada no topo da lista (as mais recentes primeiro).
  pinned_at        timestamptz,
  primary key (conversation_id, user_id)
);
