import nodemailer from 'nodemailer';

import type { MailConfig } from '../config/env.js';

export interface Mail {
  to: string;
  subject: string;
  text: string;
  html: string;
}

export type Mailer = (mail: Mail) => Promise<void>;

/** Onde escrever os emails quando não há servidor SMTP. */
interface Log {
  warn(obj: object, msg: string): void;
}

/** Envia por SMTP; sem SMTP_HOST (desenvolvimento) escreve o email no log. */
export function createMailer(config: MailConfig, log: Log): Mailer {
  const { smtp } = config;
  if (!smtp) {
    return async (mail) => {
      log.warn({ to: mail.to, subject: mail.subject, text: mail.text }, 'SMTP_HOST não definido: email não enviado');
    };
  }
  const transport = nodemailer.createTransport({
    host: smtp.host,
    port: smtp.port,
    secure: smtp.protocol === 'ssl',
    // Com starttls, recusa enviar a palavra-passe se o servidor não passar a TLS.
    requireTLS: smtp.protocol === 'starttls',
    ignoreTLS: smtp.protocol === 'none',
    auth: smtp.user ? { user: smtp.user, pass: smtp.password } : undefined,
  });
  return async (mail) => {
    await transport.sendMail({ from: config.from, ...mail });
  };
}
