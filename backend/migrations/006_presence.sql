-- Birthdayly — presença ("online" / "visto por último")
--
-- Quem tem a app aberta está ligado por WebSocket (ver src/core/realtime.ts).
-- Ao sair, guarda-se a hora para mostrar "visto por último às …" a amigos e a
-- quem partilha conversas com a pessoa.
alter table profiles add column last_seen_at timestamptz;
