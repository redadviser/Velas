-- Birthdayly — taxa de serviço nos pagamentos dentro da app
--
-- Quem paga a sua parte dentro da app paga, além do custo da Stripe, uma taxa
-- de serviço fixa (PAYMENTS_SERVICE_FEE, 0,39 € por omissão), que fica para a
-- Birthdayly. payments.fee continua a ser tudo o que se soma à parte (Stripe +
-- serviço); service_fee é a parte da Birthdayly, para a contabilidade.
alter table payments add column service_fee numeric(10, 2) not null default 0 check (service_fee >= 0);
