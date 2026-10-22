import { z } from 'zod';

import { id } from '../../core/validation.js';

/** O token do link (/b/TOKEN): 16 bytes aleatórios em base64url. */
export const requestTokenParams = z.object({ token: z.string().regex(/^[A-Za-z0-9_-]{22}$/) });

/** Dias de cada mês (29 de fevereiro conta: há quem faça anos nesse dia). */
const daysIn = [31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];

/** O que quem abre o link escreve. */
export const answerSchema = z
  .object({
    name: z.string().trim().min(1).max(80),
    day: z.coerce.number().int().min(1).max(31),
    month: z.coerce.number().int().min(1).max(12),
    year: z.coerce.number().int().min(1900).max(new Date().getFullYear()).nullish(),
    /** Identificador aleatório que a página guarda no telemóvel (uma resposta por telemóvel). */
    device: z.string().regex(/^[A-Za-z0-9-]{8,64}$/),
    /** Campo escondido: só um robô o preenche. */
    website: z.string().max(200).optional(),
    /** Milissegundos entre abrir a página e enviar (uma pessoa demora mais de 2 s). */
    elapsed_ms: z.coerce.number().int().min(0).optional(),
  })
  .refine((a) => a.day <= daysIn[a.month - 1]!, { message: 'invalid date', path: ['day'] });
export type AnswerInput = z.infer<typeof answerSchema>;

/** Respostas por hora em cada link, no máximo (um grupo de família nunca lá chega). */
export const maxAnswersPerHour = 30;

/** Respostas por link, no total (um link partilhado por engano não enche os pendentes). */
export const maxAnswers = 500;

/** Menos do que isto entre abrir a página e enviar é um robô. */
export const minElapsedMs = 2000;

export const requestPatchSchema = z.object({ enabled: z.boolean() });
export const answerParams = z.object({ id });

export interface BirthdayRequest {
  token: string;
  /** Quantas pessoas já foram aceites a partir deste link. */
  answers: number;
  /** Respostas à espera de serem aceites ou ignoradas. */
  pending: number;
  enabled: boolean;
  expires_at: string;
  /** Desligado ou expirado: a página não aceita respostas. */
  open: boolean;
}

/** Uma resposta por confirmar (GET /birthday-request/answers). */
export interface PendingAnswer {
  id: string;
  name: string;
  birth_day: number;
  birth_month: number;
  birth_year: number | null;
  created_at: string;
}

/** O que a página do link mostra de quem pede. */
export interface RequestOwner {
  user_id: string;
  name: string;
  open: boolean;
}
