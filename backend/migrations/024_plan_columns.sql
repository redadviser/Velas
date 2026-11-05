-- Birthdayly — o plano (Birthdayly+) em três colunas:
--
--   trial_until       fim do período experimental de 30 dias (null = ainda não o usou);
--   store_plus_until  o que a loja diz (App Store / Google Play, pelo Adapty);
--   plan_source       'store' (o normal), ou para testes num utilizador:
--                     'plus' (Plus sem fim) ou 'free' (Grátis).
--
-- Mudar plan_source não apaga nada: voltar a 'store' repõe o que a loja e o
-- período experimental dão. A data que conta é plan_until(profiles).
--
-- Para testar, por exemplo:
--   update profiles set plan_source = 'plus' where username = 'x';
--   update profiles set plan_source = 'store' where username = 'x';

alter table profiles drop column plus_active_until;

-- O período experimental usado passa a ser trial_until preenchido.
update profiles set plus_until = coalesce(plus_until, now()) where plus_trial_used;

alter table profiles drop constraint profiles_plan_source_check;
update profiles set plan_source = case
  when plan_source = 'store' then 'store'
  when debug_plus_until > now() then 'plus'
  else 'free'
end;
alter table profiles
  add constraint profiles_plan_source_check check (plan_source in ('store', 'plus', 'free')),
  drop column debug_plus_until,
  drop column plus_trial_used;
alter table profiles rename column plus_until to trial_until;

-- Até quando a conta tem o Birthdayly+ (null = Grátis).
create or replace function plan_until(p profiles)
returns timestamptz language sql stable as $$
  select case p.plan_source
    when 'plus' then '9999-12-31T00:00:00Z'::timestamptz
    when 'free' then null
    else greatest(p.trial_until, p.store_plus_until)
  end
$$;

create or replace function has_plus(u uuid)
returns boolean language sql stable as $$
  select coalesce((select plan_until(p) > now() from profiles p where p.id = u), false)
$$;
