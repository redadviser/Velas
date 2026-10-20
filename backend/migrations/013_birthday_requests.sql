-- Birthdayly — pedir aniversários por link
--
-- Quase ninguém tem a data de aniversário guardada nos contactos. Cada
-- utilizador tem por isso um link (/b/TOKEN) para partilhar, por exemplo no
-- grupo da família: quem o abre escreve o nome e a data, sem conta nem app, e
-- o aniversário entra diretamente na lista de quem pediu (people).
--
-- O token é o segredo: quem o tem pode acrescentar aniversários à lista do
-- dono. Por isso há um limite de respostas e o dono pode trocar de link.
create table birthday_requests (
  user_id     uuid primary key references users (id) on delete cascade,
  token       text not null unique check (token ~ '^[A-Za-z0-9_-]{22}$'),
  answers     integer not null default 0,
  created_at  timestamptz not null default now()
);
