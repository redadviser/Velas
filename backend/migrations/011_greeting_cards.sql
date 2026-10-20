-- Birthdayly — cartões de parabéns
--
-- Em vez de mandar só o texto para o WhatsApp, quem escreve os parabéns pode
-- mandar um cartão: um link (/c/TOKEN) que mostra a mensagem a qualquer
-- pessoa que o tenha, com ou sem a app. Na app, quem recebe "reclama" o
-- cartão: fica amigo de quem o mandou e a mensagem passa a ser a primeira da
-- conversa privada entre os dois, para poder responder logo.
--
-- Entre amigos, o cartão pode ir diretamente para o mural de quem faz anos
-- (via = 'wall'): fica logo na conta dessa pessoa, sem precisar do link.
-- O mural é privado: só quem recebeu vê os cartões que lá estão.
--
-- O token é o segredo (como o link de convite): quem o tem lê o cartão.
-- O texto e o nome de quem recebe são uma cópia, para o cartão não mudar se a
-- mensagem ou a pessoa forem editadas ou apagadas depois.
create table greeting_cards (
  id              uuid primary key,          -- gerado na app: reenviar não duplica
  token           text not null unique check (token ~ '^[A-Za-z0-9_-]{22}$'),
  sender_id       uuid not null references users (id) on delete cascade,
  person_id       uuid references people (id) on delete set null,
  recipient_name  text not null check (char_length(recipient_name) between 1 and 120),
  body            text not null check (char_length(body) between 1 and 1000),
  via             text not null default 'link' check (via in ('link', 'wall')),
  -- Primeira vez que quem recebeu o viu (na página, com JS, na app ou no mural):
  -- as pré-visualizações dos links (WhatsApp, iMessage) não contam.
  opened_at       timestamptz,
  -- Quem recebeu apaga a conta: os cartões do mural dela vão com ela.
  recipient_id    uuid references users (id) on delete cascade,
  claimed_at      timestamptz,
  created_at      timestamptz not null default now(),
  check (recipient_id is null or recipient_id <> sender_id),
  check (via = 'link' or recipient_id is not null)
);
create index greeting_cards_sender_idx on greeting_cards (sender_id, person_id);
create index greeting_cards_recipient_idx on greeting_cards (recipient_id) where recipient_id is not null;

create trigger greeting_cards_owner_refs before insert or update on greeting_cards
  for each row execute function check_owner_refs();

-- check_owner_refs() passa a conhecer os cartões (a pessoa tem de ser de quem envia).
create or replace function check_owner_refs()
returns trigger language plpgsql as $$
begin
  if tg_table_name in ('gift_ideas', 'messages') then
    if not exists (select 1 from people where id = new.person_id and user_id = new.user_id) then
      raise exception 'person not found' using errcode = '42501';
    end if;
  elsif tg_table_name = 'greeting_cards' then
    -- Encaixado: o PL/pgSQL não garante que "a and b" pare em "a" (new.person_id só existe aqui).
    if new.person_id is not null then
      if not exists (select 1 from people where id = new.person_id and user_id = new.sender_id) then
        raise exception 'person not found' using errcode = '42501';
      end if;
    end if;
  elsif tg_table_name = 'people' and new.category_id is not null then
    if not exists (select 1 from categories where id = new.category_id and user_id = new.user_id) then
      raise exception 'category not found' using errcode = '42501';
    end if;
  end if;
  return new;
end $$;
