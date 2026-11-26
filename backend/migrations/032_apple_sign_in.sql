-- Birthdayly — Entrar com a Apple
--
-- apple_sub identifica a conta Apple (como google_sub). O refresh token da
-- Apple é guardado só para o revogar quando a conta é apagada, como a Apple
-- exige às apps com Entrar com a Apple.
alter table users add column apple_sub text unique;
alter table users add column apple_refresh_token text;
