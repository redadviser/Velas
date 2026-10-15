-- Birthdayly — mais métodos de pagamento e fotografia dos grupos
--
-- card:   cartão VISA / Mastercard, pago pelo link Revolut ou PayPal de quem recebe
--         (a app continua a não movimentar dinheiro; só regista o "já paguei").
-- skrill: transferência Skrill para o email de quem recebe.
alter table group_members drop constraint group_members_paid_method_check;
alter table group_members add constraint group_members_paid_method_check
  check (paid_method in ('mbway', 'transfer', 'revolut', 'paypal', 'cash', 'card', 'skrill'));

-- Fotografia do grupo (PhotoStorage: <grupo>/photo-<n>.<ext>), escolhida pelo administrador.
alter table gift_groups add column photo_path text;
