-- Birthdayly — deixa de haver pagamentos dentro da app (Stripe Connect).
--
-- Nas prendas em grupo cada membro paga diretamente a quem compra (MB WAY,
-- Revolut, PayPal, em mão) e marca "já paguei"; a subscrição do Birthdayly+
-- vende-se pelas lojas (Adapty), sem Stripe. Sai a tabela dos pagamentos e o
-- que a Stripe usava nos perfis.
drop table if exists payments;

alter table profiles
  drop column if exists stripe_account_id,
  drop column if exists payouts_enabled,
  drop column if exists mbway_pay_phone;
