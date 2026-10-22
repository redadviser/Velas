-- Birthdayly — notificações push e mensagens de parabéns agendadas.
--
-- push_tokens: um por telemóvel (o token do Firebase Cloud Messaging), com a
-- língua da app para o texto das notificações.
create table push_tokens (
  token       text primary key check (char_length(token) between 20 and 4096),
  user_id     uuid not null references users (id) on delete cascade,
  platform    text not null check (platform in ('android', 'ios')),
  lang        text not null default 'pt' check (lang in ('pt', 'en', 'es', 'fr')),
  updated_at  timestamptz not null default now()
);
create index push_tokens_user_idx on push_tokens (user_id);

-- Agendar a mensagem preparada para uma pessoa:
--   wall   = a API publica-a no mural do amigo (e na vossa conversa) à hora marcada;
--   remind = fora da app (WhatsApp, SMS, cartão por link): a app avisa à hora
--            marcada, com a mensagem pronta a enviar.
alter table messages
  add column scheduled_at        timestamptz,
  add column schedule_via        text check (schedule_via in ('wall', 'remind')),
  add column schedule_friend_id  uuid references users (id) on delete set null,
  add column schedule_media_key  text,
  -- Quando foi enviada (wall) e porque falhou, se falhou.
  add column sent_at             timestamptz,
  add column send_error          text,
  -- O amigo do "wall" é validado pela API (se apagar a conta, o envio falha com aviso).
  add constraint messages_schedule_check check ((scheduled_at is null) = (schedule_via is null));

create index messages_due_idx on messages (scheduled_at)
  where schedule_via = 'wall' and sent_at is null;
