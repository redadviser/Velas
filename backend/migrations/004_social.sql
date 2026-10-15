-- Birthdayly — amigos e conversas
--
-- Cada prenda em grupo tem uma conversa (criada com o grupo) onde os membros
-- combinam a prenda. Dois amigos podem também ter uma conversa privada.
-- As mensagens podem ser texto, imagens, GIFs ou stickers e levar uma
-- reação por pessoa. Quem vê cada conversa é verificado com can_chat().

-- ---------------------------------------------------------------------------
-- Amigos
-- ---------------------------------------------------------------------------
-- Um pedido recusado é apagado, por isso pode voltar a ser feito.
create table friendships (
  id            uuid primary key default gen_random_uuid(),
  requester_id  uuid not null references users (id) on delete cascade,
  addressee_id  uuid not null references users (id) on delete cascade,
  status        text not null default 'pending' check (status in ('pending', 'accepted')),
  created_at    timestamptz not null default now(),
  responded_at  timestamptz,
  check (requester_id <> addressee_id)
);
-- Um só registo por par, seja quem for que fez o pedido.
create unique index friendships_pair_key
  on friendships (least(requester_id, addressee_id), greatest(requester_id, addressee_id));
create index friendships_requester_idx on friendships (requester_id);
create index friendships_addressee_idx on friendships (addressee_id);

create or replace function are_friends(a uuid, b uuid)
returns boolean language sql stable as $$
  select exists (
    select 1 from friendships
    where status = 'accepted'
      and least(requester_id, addressee_id) = least(a, b)
      and greatest(requester_id, addressee_id) = greatest(a, b)
  );
$$;

-- ---------------------------------------------------------------------------
-- Conversas
-- ---------------------------------------------------------------------------
create table conversations (
  id               uuid primary key default gen_random_uuid(),
  -- Conversa de um grupo...
  group_id         uuid unique references gift_groups (id) on delete cascade,
  -- ...ou privada entre dois utilizadores (por ordem, para o par ser único).
  user_a           uuid references users (id) on delete cascade,
  user_b           uuid references users (id) on delete cascade,
  last_message_at  timestamptz,
  created_at       timestamptz not null default now(),
  check (
    (group_id is not null and user_a is null and user_b is null)
    or (group_id is null and user_a is not null and user_b is not null and user_a < user_b)
  )
);
create unique index conversations_direct_key on conversations (user_a, user_b) where group_id is null;
create index conversations_user_b_idx on conversations (user_b) where group_id is null;

-- A conversa de cada grupo nasce com ele.
create or replace function create_group_conversation()
returns trigger language plpgsql as $$
begin
  insert into conversations (group_id) values (new.id);
  return new;
end $$;

create trigger gift_groups_conversation after insert on gift_groups
  for each row execute function create_group_conversation();

insert into conversations (group_id) select id from gift_groups;

create or replace function can_chat(cid uuid)
returns boolean language sql stable as $$
  select exists (
    select 1 from conversations c
    where c.id = cid
      and (app.uid() in (c.user_a, c.user_b) or (c.group_id is not null and is_group_member(c.group_id)))
  );
$$;

-- Contas que participam numa conversa (para enviar os eventos em tempo real).
create or replace function conversation_user_ids(cid uuid)
returns setof uuid language sql stable as $$
  select unnest(array[c.user_a, c.user_b]) from conversations c where c.id = cid and c.group_id is null
  union
  select m.user_id from conversations c join group_members m on m.group_id = c.group_id
  where c.id = cid and m.user_id is not null
  union
  select g.created_by from conversations c join gift_groups g on g.id = c.group_id where c.id = cid;
$$;

-- Até onde cada pessoa leu (contador de não lidas e "visto").
create table conversation_reads (
  conversation_id  uuid not null references conversations (id) on delete cascade,
  user_id          uuid not null references users (id) on delete cascade,
  last_read_at     timestamptz not null default now(),
  primary key (conversation_id, user_id)
);

-- ---------------------------------------------------------------------------
-- Mensagens
-- ---------------------------------------------------------------------------
create table chat_messages (
  id               uuid primary key,          -- gerado na app: reenviar não duplica
  conversation_id  uuid not null references conversations (id) on delete cascade,
  sender_id        uuid references users (id) on delete set null,  -- null: conta eliminada
  kind             text not null check (kind in ('text', 'image', 'gif', 'sticker')),
  body             text not null default '' check (char_length(body) <= 4000),
  -- Imagem guardada na API (PhotoStorage) ou GIF/sticker externo (GIPHY).
  media_key        text,
  media_url        text,
  width            integer check (width between 1 and 10000),
  height           integer check (height between 1 and 10000),
  reply_to         uuid references chat_messages (id) on delete set null,
  created_at       timestamptz not null default now(),
  deleted_at       timestamptz,
  -- Uma mensagem apagada fica só como "mensagem apagada" (sem conteúdo).
  check (deleted_at is not null or kind = 'text' or media_key is not null or media_url is not null),
  check (deleted_at is not null or kind <> 'text' or char_length(trim(body)) > 0)
);
create index chat_messages_conversation_idx on chat_messages (conversation_id, created_at desc, id desc);

create or replace function touch_conversation()
returns trigger language plpgsql as $$
begin
  update conversations set last_message_at = new.created_at where id = new.conversation_id;
  return new;
end $$;

create trigger chat_messages_touch_conversation after insert on chat_messages
  for each row execute function touch_conversation();

-- Uma reação por pessoa em cada mensagem (escolher outra substitui).
create table chat_reactions (
  message_id  uuid not null references chat_messages (id) on delete cascade,
  user_id     uuid not null references users (id) on delete cascade,
  emoji       text not null check (char_length(emoji) between 1 and 16),
  created_at  timestamptz not null default now(),
  primary key (message_id, user_id)
);

-- ---------------------------------------------------------------------------
-- Stickers guardados por cada pessoa
-- ---------------------------------------------------------------------------
create table stickers (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references users (id) on delete cascade,
  media_key   text,
  media_url   text,
  width       integer check (width between 1 and 10000),
  height      integer check (height between 1 and 10000),
  created_at  timestamptz not null default now(),
  check ((media_key is null) <> (media_url is null))
);
create index stickers_user_idx on stickers (user_id, created_at desc);
create unique index stickers_user_url_key on stickers (user_id, media_url) where media_url is not null;
