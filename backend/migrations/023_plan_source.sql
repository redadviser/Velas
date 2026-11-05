-- Birthdayly — de onde vem o plano (Birthdayly+): da loja ou de testes.
--
--   plus_until        período experimental dado pela Birthdayly (30 dias);
--   store_plus_until  o que a loja diz (App Store / Google Play, pelo Adapty);
--   plan_source       'store' (o normal) ou 'debug' (testes num utilizador);
--   debug_plus_until  com 'debug', o plano é só este (null = Grátis).
--
-- Mudar plan_source não apaga nada: voltar a 'store' repõe o que a loja e o
-- período experimental dão. plus_active_until é o que conta (calculado).
--
-- Para testar, por exemplo:
--   update profiles set plan_source = 'debug', debug_plus_until = now() + interval '1 day' where username = 'x';
--   update profiles set plan_source = 'store' where username = 'x';
alter table profiles
  add column store_plus_until timestamptz,
  add column plan_source text not null default 'store' check (plan_source in ('store', 'debug')),
  add column debug_plus_until timestamptz,
  add column plus_active_until timestamptz generated always as (
    case when plan_source = 'debug' then debug_plus_until else greatest(plus_until, store_plus_until) end
  ) stored;

create or replace function has_plus(u uuid)
returns boolean language sql stable as $$
  select coalesce((select plus_active_until > now() from profiles where id = u), false)
$$;
