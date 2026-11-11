-- Birthdayly — gostos e lista de desejos
--
-- Cada utilizador escolhe os seus gostos e hobbies e guarda o que gostava de
-- receber. Os amigos (amizade aceite) veem os dois no perfil da pessoa ligada
-- a essa conta, para acertarem na prenda. As pessoas sem conta também têm
-- gostos, escolhidos por quem as guardou. Os gostos são chaves fixas da app
-- (ex.: 'books', 'travel'), para as sugestões de prendas as perceberem.
alter table profiles add column interests text[] not null default '{}'
  check (cardinality(interests) <= 30);
alter table people add column interests text[] not null default '{}'
  check (cardinality(interests) <= 30);

create table wishlist_items (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references users (id) on delete cascade,
  title       text not null check (char_length(title) between 1 and 200),
  price       numeric(10, 2) check (price >= 0),
  link        text not null default '' check (char_length(link) <= 2000),
  notes       text not null default '' check (char_length(notes) <= 2000),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
create index wishlist_items_user_idx on wishlist_items (user_id);

create trigger wishlist_items_touch before update on wishlist_items
  for each row execute function touch_updated_at();
