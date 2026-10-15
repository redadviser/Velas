-- Birthdayly — fotografia de perfil
--
-- Caminho no PhotoStorage (<utilizador>/avatar-<n>.<ext>); a API devolve-o
-- como URL assinado (photo_url) no perfil, nos amigos, nas conversas e nos grupos.
alter table profiles add column photo_path text;
