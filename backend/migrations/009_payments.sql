-- Birthdayly — pagamentos dentro da app (Stripe Connect)
--
-- Quem compra a prenda liga uma conta Stripe (stripe_account_id) e passa a
-- receber diretamente: cartão VISA/Mastercard e PayPal pelo Stripe Checkout,
-- MB WAY com um pedido enviado para o telemóvel de quem paga. Um pagamento
-- concluído marca a parte como paga e confirmada (o dinheiro chegou mesmo).
alter table profiles
  add column stripe_account_id  text unique,
  -- A conta pode receber transferências (onboarding concluído na Stripe).
  add column payouts_enabled    boolean not null default false,
  -- Número MB WAY guardado para pagar (privado: nunca é mostrado a ninguém).
  add column mbway_pay_phone    text check (mbway_pay_phone ~ '^\+[1-9][0-9]{7,14}$');

create table payments (
  id                       uuid primary key default gen_random_uuid(),
  group_id                 uuid not null references gift_groups (id) on delete cascade,
  member_id                uuid references group_members (id) on delete set null,
  payer_id                 uuid references users (id) on delete set null,
  payee_id                 uuid references users (id) on delete set null,
  method                   text not null check (method in ('card', 'paypal', 'mb_way')),
  -- A parte (o que chega a quem compra) e a comissão somada a quem paga.
  amount                   numeric(10, 2) not null check (amount > 0),
  fee                      numeric(10, 2) not null default 0 check (fee >= 0),
  status                   text not null default 'pending' check (status in ('pending', 'succeeded', 'failed', 'canceled')),
  error                    text,
  stripe_payment_intent    text unique,
  stripe_checkout_session  text unique,
  created_at               timestamptz not null default now(),
  updated_at               timestamptz not null default now()
);
create index payments_member_idx on payments (member_id);
create index payments_payer_idx on payments (payer_id);

create trigger payments_touch before update on payments for each row execute function touch_updated_at();
