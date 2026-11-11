/** Texto das notificações push, na língua da app de cada telemóvel. */
export type PushLang = 'pt' | 'en' | 'es' | 'fr';

interface Copy {
  newMessage: string;
  photo: string;
  photoCaption: (text: string) => string;
  gif: string;
  sticker: string;
  /** Mensagem num grupo: "Ana: olá". */
  inGroup: (name: string, text: string) => string;
  scheduledSent: (name: string) => string;
  scheduledSentBody: string;
  scheduledFailed: (name: string) => string;
  scheduledFailedBody: string;
  wallCard: (name: string) => string;
  wallCardBody: string;
}

const copy: Record<PushLang, Copy> = {
  pt: {
    newMessage: 'Nova mensagem',
    photo: '📷 Fotografia',
    photoCaption: (t) => `📷 ${t}`,
    gif: 'GIF',
    sticker: 'Sticker',
    inGroup: (n, t) => `${n}: ${t}`,
    scheduledSent: (n) => `🎉 Enviámos os teus parabéns a ${n}`,
    scheduledSentBody: 'A tua mensagem já está no mural.',
    wallCard: (n) => `${n} deixou-te parabéns no mural`,
    wallCardBody: 'Toca para leres.',
    scheduledFailed: (n) => `Não foi possível enviar a mensagem a ${n}`,
    scheduledFailedBody: 'Abre a app para a enviares de outra forma.',
  },
  en: {
    newMessage: 'New message',
    photo: '📷 Photo',
    photoCaption: (t) => `📷 ${t}`,
    gif: 'GIF',
    sticker: 'Sticker',
    inGroup: (n, t) => `${n}: ${t}`,
    scheduledSent: (n) => `🎉 We sent your birthday wishes to ${n}`,
    scheduledSentBody: 'Your message is on their wall.',
    wallCard: (n) => `${n} left you birthday wishes on your wall`,
    wallCardBody: 'Tap to read.',
    scheduledFailed: (n) => `We couldn't send your message to ${n}`,
    scheduledFailedBody: 'Open the app to send it another way.',
  },
  es: {
    newMessage: 'Mensaje nuevo',
    photo: '📷 Foto',
    photoCaption: (t) => `📷 ${t}`,
    gif: 'GIF',
    sticker: 'Sticker',
    inGroup: (n, t) => `${n}: ${t}`,
    scheduledSent: (n) => `🎉 Hemos enviado tu felicitación a ${n}`,
    scheduledSentBody: 'Tu mensaje ya está en su muro.',
    wallCard: (n) => `${n} te ha felicitado en tu muro`,
    wallCardBody: 'Toca para leerlo.',
    scheduledFailed: (n) => `No se pudo enviar tu mensaje a ${n}`,
    scheduledFailedBody: 'Abre la app para enviarlo de otra forma.',
  },
  fr: {
    newMessage: 'Nouveau message',
    photo: '📷 Photo',
    photoCaption: (t) => `📷 ${t}`,
    gif: 'GIF',
    sticker: 'Sticker',
    inGroup: (n, t) => `${n} : ${t}`,
    scheduledSent: (n) => `🎉 Nous avons envoyé vos vœux à ${n}`,
    scheduledSentBody: 'Votre message est sur son mur.',
    wallCard: (n) => `${n} vous a souhaité un joyeux anniversaire sur votre mur`,
    wallCardBody: 'Touchez pour lire.',
    scheduledFailed: (n) => `Impossible d'envoyer votre message à ${n}`,
    scheduledFailedBody: "Ouvrez l'app pour l'envoyer autrement.",
  },
};

export const pushCopy = (lang: string): Copy => copy[(lang as PushLang) in copy ? (lang as PushLang) : 'pt'];

/** O que aparece de uma mensagem do chat (como na app: ChatMessage.previewOf). */
export function previewOf(c: Copy, kind: string, body: string): string {
  switch (kind) {
    case 'image':
      return body ? c.photoCaption(body) : c.photo;
    case 'gif':
      return c.gif;
    case 'sticker':
      return c.sticker;
    default:
      return body.length > 300 ? `${body.slice(0, 300)}…` : body;
  }
}
