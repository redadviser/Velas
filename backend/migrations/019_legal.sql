-- Birthdayly — aceitação dos termos (lojas e RGPD)
--
-- Guarda quando e que versão dos Termos e da Política de Privacidade cada
-- conta aceitou (o registo inclui confirmar a idade mínima). Quando a versão
-- muda, a app pede para aceitar a nova. As contas antigas ficam sem registo
-- e aceitam na próxima vez que abrirem a app.
alter table users
  add column terms_accepted_at timestamptz,
  add column terms_version text;
