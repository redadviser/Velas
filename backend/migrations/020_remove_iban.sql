-- Birthdayly — deixa de haver transferência por IBAN: nem dentro da app (débito
-- SEPA na Stripe) nem como dado de pagamento para os outros transferirem.
--
-- Os IBANs já guardados são apagados. Os pagamentos e as partes pagas antigas
-- ('sepa_debit' / 'transfer') ficam no histórico, por isso as restrições mantêm-se.
update profiles set payment_methods = payment_methods - 'iban' - 'iban_holder'
  where payment_methods ?| array['iban', 'iban_holder'];
update group_members set payment_methods = payment_methods - 'iban' - 'iban_holder'
  where payment_methods ?| array['iban', 'iban_holder'];
