-- Birthdayly — transferência (débito SEPA: quem paga escreve o IBAN na página da
-- Stripe) e Revolut Pay dentro da app.
--
-- Uma transferência demora alguns dias úteis: fica "processing" (a parte conta
-- como paga) até a Stripe confirmar que o dinheiro chegou (confirmada) ou falhou.
alter table payments drop constraint payments_method_check;
alter table payments add constraint payments_method_check
  check (method in ('card', 'paypal', 'mb_way', 'sepa_debit', 'revolut_pay'));

alter table payments drop constraint payments_status_check;
alter table payments add constraint payments_status_check
  check (status in ('pending', 'processing', 'succeeded', 'failed', 'canceled'));
