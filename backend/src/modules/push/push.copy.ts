/** Texto das notificações push, na língua da app de cada telemóvel. */
export const pushLangs = [
  "pt",
  "pt_BR",
  "en",
  "es",
  "fr",
  "de",
  "it",
  "nl",
  "pl",
  "ro",
  "uk",
  "ru",
  "tr",
  "ar",
  "zh",
  "ja",
] as const;
export type PushLang = (typeof pushLangs)[number];

/** Modelos com {name} e {text} (traduzidos com a app: assets/translations). */
interface Templates {
  newMessage: string;
  photo: string;
  /** Mensagem num grupo: "Ana: olá". */
  inGroup: string;
  scheduledSent: string;
  scheduledSentBody: string;
  wallCard: string;
  wallCardBody: string;
  scheduledFailed: string;
  scheduledFailedBody: string;
}

interface Copy {
  newMessage: string;
  photo: string;
  photoCaption: (text: string) => string;
  gif: string;
  sticker: string;
  inGroup: (name: string, text: string) => string;
  scheduledSent: (name: string) => string;
  scheduledSentBody: string;
  scheduledFailed: (name: string) => string;
  scheduledFailedBody: string;
  wallCard: (name: string) => string;
  wallCardBody: string;
}

const templates: Record<PushLang, Templates> = {
  pt: {
    newMessage: "Nova mensagem",
    photo: "📷 Fotografia",
    inGroup: "{name}: {text}",
    scheduledSent: "🎉 Enviámos os teus parabéns a {name}",
    scheduledSentBody: "A tua mensagem já está no mural.",
    wallCard: "{name} deixou-te parabéns no mural",
    wallCardBody: "Toca para leres.",
    scheduledFailed: "Não foi possível enviar a mensagem a {name}",
    scheduledFailedBody: "Abre a app para a enviares de outra forma.",
  },
  pt_BR: {
    newMessage: "Nova mensagem",
    photo: "📷 Foto",
    inGroup: "{name}: {text}",
    scheduledSent: "🎉 Enviamos seus parabéns para {name}",
    scheduledSentBody: "Sua mensagem já está no mural.",
    wallCard: "{name} deixou parabéns no seu mural",
    wallCardBody: "Toque para ler.",
    scheduledFailed: "Não foi possível enviar a mensagem para {name}",
    scheduledFailedBody: "Abra o app para enviar de outra forma.",
  },
  en: {
    newMessage: "New message",
    photo: "📷 Photo",
    inGroup: "{name}: {text}",
    scheduledSent: "🎉 We sent your birthday wishes to {name}",
    scheduledSentBody: "Your message is on their wall.",
    wallCard: "{name} left you birthday wishes on your wall",
    wallCardBody: "Tap to read.",
    scheduledFailed: "We couldn't send your message to {name}",
    scheduledFailedBody: "Open the app to send it another way.",
  },
  es: {
    newMessage: "Mensaje nuevo",
    photo: "📷 Foto",
    inGroup: "{name}: {text}",
    scheduledSent: "🎉 Hemos enviado tu felicitación a {name}",
    scheduledSentBody: "Tu mensaje ya está en su muro.",
    wallCard: "{name} te ha felicitado en tu muro",
    wallCardBody: "Toca para leerlo.",
    scheduledFailed: "No se pudo enviar tu mensaje a {name}",
    scheduledFailedBody: "Abre la app para enviarlo de otra forma.",
  },
  fr: {
    newMessage: "Nouveau message",
    photo: "📷 Photo",
    inGroup: "{name} : {text}",
    scheduledSent: "🎉 Nous avons envoyé vos vœux à {name}",
    scheduledSentBody: "Votre message est sur son mur.",
    wallCard: "{name} vous a souhaité un joyeux anniversaire sur votre mur",
    wallCardBody: "Touchez pour lire.",
    scheduledFailed: "Impossible d'envoyer votre message à {name}",
    scheduledFailedBody: "Ouvrez l'app pour l'envoyer autrement.",
  },
  de: {
    newMessage: "Neue Nachricht",
    photo: "📷 Foto",
    inGroup: "{name}: {text}",
    scheduledSent: "🎉 Wir haben deine Glückwünsche an {name} geschickt",
    scheduledSentBody: "Deine Nachricht ist auf der Pinnwand.",
    wallCard: "{name} hat dir Glückwünsche auf deiner Pinnwand hinterlassen",
    wallCardBody: "Tippe zum Lesen.",
    scheduledFailed: "Die Nachricht an {name} konnte nicht gesendet werden",
    scheduledFailedBody: "Öffne die App, um sie auf anderem Weg zu senden.",
  },
  it: {
    newMessage: "Nuovo messaggio",
    photo: "📷 Foto",
    inGroup: "{name}: {text}",
    scheduledSent: "🎉 Abbiamo inviato i tuoi auguri a {name}",
    scheduledSentBody: "Il tuo messaggio è già nella bacheca.",
    wallCard: "{name} ti ha lasciato gli auguri nella bacheca",
    wallCardBody: "Tocca per leggerli.",
    scheduledFailed: "Impossibile inviare il messaggio a {name}",
    scheduledFailedBody: "Apri l'app per inviarlo in un altro modo.",
  },
  nl: {
    newMessage: "Nieuw bericht",
    photo: "📷 Foto",
    inGroup: "{name}: {text}",
    scheduledSent: "🎉 We hebben je felicitatie naar {name} gestuurd",
    scheduledSentBody: "Je bericht staat al op de muur.",
    wallCard: "{name} heeft je gefeliciteerd op je muur",
    wallCardBody: "Tik om te lezen.",
    scheduledFailed: "Kan het bericht niet naar {name} sturen",
    scheduledFailedBody:
      "Open de app om het op een andere manier te versturen.",
  },
  pl: {
    newMessage: "Nowa wiadomość",
    photo: "📷 Zdjęcie",
    inGroup: "{name}: {text}",
    scheduledSent: "🎉 Wysłaliśmy twoje życzenia do: {name}",
    scheduledSentBody: "Twoja wiadomość jest już na tablicy.",
    wallCard: "{name} zostawia ci życzenia na tablicy",
    wallCardBody: "Dotknij, aby przeczytać.",
    scheduledFailed: "Nie udało się wysłać wiadomości do: {name}",
    scheduledFailedBody: "Otwórz aplikację, aby wysłać ją w inny sposób.",
  },
  ro: {
    newMessage: "Mesaj nou",
    photo: "📷 Fotografie",
    inGroup: "{name}: {text}",
    scheduledSent: "🎉 I-am trimis urările tale lui {name}",
    scheduledSentBody: "Mesajul tău e deja pe perete.",
    wallCard: "{name} ți-a lăsat urări de La mulți ani pe perete",
    wallCardBody: "Atinge ca să citești.",
    scheduledFailed: "Nu am putut trimite mesajul către {name}",
    scheduledFailedBody: "Deschide aplicația ca să-l trimiți altfel.",
  },
  uk: {
    newMessage: "Нове повідомлення",
    photo: "📷 Фото",
    inGroup: "{name}: {text}",
    scheduledSent: "🎉 Ми надіслали твоє привітання для {name}",
    scheduledSentBody: "Твоє повідомлення вже на стіні.",
    wallCard: "{name} залишає тобі привітання на стіні",
    wallCardBody: "Торкнися, щоб прочитати.",
    scheduledFailed: "Не вдалося надіслати повідомлення для {name}",
    scheduledFailedBody:
      "Відкрий застосунок, щоб надіслати його іншим способом.",
  },
  ru: {
    newMessage: "Новое сообщение",
    photo: "📷 Фотография",
    inGroup: "{name}: {text}",
    scheduledSent: "🎉 Мы отправили твоё поздравление: {name}",
    scheduledSentBody: "Твоё поздравление уже на стене.",
    wallCard: "{name} оставил(а) тебе поздравление на стене",
    wallCardBody: "Нажми, чтобы прочитать.",
    scheduledFailed: "Не удалось отправить поздравление: {name}",
    scheduledFailedBody:
      "Открой приложение, чтобы отправить его другим способом.",
  },
  tr: {
    newMessage: "Yeni mesaj",
    photo: "📷 Fotoğraf",
    inGroup: "{name}: {text}",
    scheduledSent: "🎉 Doğum günü kutlamanı {name} adlı kişiye gönderdik",
    scheduledSentBody: "Mesajın artık duvarda.",
    wallCard: "{name} duvarına sana doğum günü mesajı bıraktı",
    wallCardBody: "Okumak için dokun.",
    scheduledFailed: "Mesaj {name} adlı kişiye gönderilemedi",
    scheduledFailedBody: "Başka bir yolla göndermek için uygulamayı aç.",
  },
  ar: {
    newMessage: "رسالة جديدة",
    photo: "📷 صورة",
    inGroup: "{name}: {text}",
    scheduledSent: "🎉 أرسلنا تهنئتك إلى {name}",
    scheduledSentBody: "رسالتك على الحائط الآن.",
    wallCard: "ترك لك {name} تهنئة على حائطك",
    wallCardBody: "اضغط للقراءة.",
    scheduledFailed: "تعذّر إرسال الرسالة إلى {name}",
    scheduledFailedBody: "افتح التطبيق لإرسالها بطريقة أخرى.",
  },
  zh: {
    newMessage: "新消息",
    photo: "📷 照片",
    inGroup: "{name}: {text}",
    scheduledSent: "🎉 我们已把你的生日祝福发给 {name}",
    scheduledSentBody: "你的消息已经在留言墙上了。",
    wallCard: "{name} 在留言墙上给你送来了生日祝福",
    wallCardBody: "点按查看。",
    scheduledFailed: "无法将消息发送给 {name}",
    scheduledFailedBody: "打开 App，换一种方式发送。",
  },
  ja: {
    newMessage: "新着メッセージ",
    photo: "📷 写真",
    inGroup: "{name}: {text}",
    scheduledSent: "🎉 {name}さんにお祝いのメッセージを送りました",
    scheduledSentBody: "メッセージはウォールに投稿されています。",
    wallCard: "{name}さんがウォールにお祝いのメッセージを残しました",
    wallCardBody: "タップして読みましょう。",
    scheduledFailed: "{name}さんにメッセージを送れませんでした",
    scheduledFailedBody: "アプリを開いて、別の方法で送ってください。",
  },
};

const fill = (t: string, values: Record<string, string>) =>
  t.replace(/\{(\w+)\}/g, (m, k: string) => values[k] ?? m);

function build(t: Templates): Copy {
  return {
    newMessage: t.newMessage,
    photo: t.photo,
    photoCaption: (text) => `📷 ${text}`,
    gif: "GIF",
    sticker: "Sticker",
    inGroup: (name, text) => fill(t.inGroup, { name, text }),
    scheduledSent: (name) => fill(t.scheduledSent, { name }),
    scheduledSentBody: t.scheduledSentBody,
    wallCard: (name) => fill(t.wallCard, { name }),
    wallCardBody: t.wallCardBody,
    scheduledFailed: (name) => fill(t.scheduledFailed, { name }),
    scheduledFailedBody: t.scheduledFailedBody,
  };
}

const copies = Object.fromEntries(
  pushLangs.map((l) => [l, build(templates[l])]),
) as Record<PushLang, Copy>;

export const pushCopy = (lang: string): Copy =>
  copies[
    (pushLangs as readonly string[]).includes(lang) ? (lang as PushLang) : "pt"
  ];

/** O que aparece de uma mensagem do chat (como na app: ChatMessage.previewOf). */
export function previewOf(c: Copy, kind: string, body: string): string {
  switch (kind) {
    case "image":
      return body ? c.photoCaption(body) : c.photo;
    case "gif":
      return c.gif;
    case "sticker":
      return c.sticker;
    default:
      return body.length > 300 ? `${body.slice(0, 300)}…` : body;
  }
}
