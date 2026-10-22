-- Birthdayly — Birthdayly+ (funcionalidades do plano pago)
--
-- O acesso ao Birthdayly+ é profiles.plus_until: enquanto for futuro, a conta
-- tem o plano. Para já só se obtém pelo período experimental de 30 dias (um
-- por conta); a compra dentro da app vem depois e vai prolongar a mesma data.
alter table profiles
  add column plus_until timestamptz,
  add column plus_trial_used boolean not null default false,
  -- Resumo semanal à segunda-feira com os aniversários da semana.
  add column weekly_digest boolean not null default false;

create or replace function has_plus(u uuid)
returns boolean language sql stable as $$
  select coalesce((select plus_until > now() from profiles where id = u), false)
$$;

-- Lembretes avançados: hora própria por pessoa (null = a do perfil).
alter table people
  add column reminder_hour smallint check (reminder_hour between 0 and 23),
  add column reminder_minute smallint check (reminder_minute between 0 and 59),
  add check ((reminder_hour is null) = (reminder_minute is null));

-- Histórico de prendas: quando foi marcada como comprada.
alter table gift_ideas add column purchased_at timestamptz;
update gift_ideas set purchased_at = updated_at where purchased and purchased_at is null;

-- Cartões especiais: uma fotografia, um vídeo ou um áudio junto à mensagem.
alter table greeting_cards
  add column media_key text,
  add column media_kind text check (media_kind in ('image', 'video', 'audio')),
  add check ((media_key is null) = (media_kind is null));

-- Mural com fotografias: as do próprio dia, num álbum por ano.
create table wall_photos (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references users (id) on delete cascade,
  year        smallint not null check (year between 1900 and 2100),
  media_key   text not null,
  caption     text not null default '' check (char_length(caption) <= 200),
  created_at  timestamptz not null default now()
);
create index wall_photos_user_year_idx on wall_photos (user_id, year);
