-- As notificações push nas 16 línguas da app (antes só pt, en, es e fr).
alter table push_tokens drop constraint if exists push_tokens_lang_check;
alter table push_tokens add constraint push_tokens_lang_check
  check (lang in ('pt', 'pt_BR', 'en', 'es', 'fr', 'de', 'it', 'nl', 'pl', 'ro', 'uk', 'ru', 'tr', 'ar', 'zh', 'ja'));
