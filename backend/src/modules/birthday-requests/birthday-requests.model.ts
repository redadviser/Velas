import { z } from 'zod';

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
  })
  .refine((a) => a.day <= daysIn[a.month - 1]!, { message: 'invalid date', path: ['day'] });
export type AnswerInput = z.infer<typeof answerSchema>;

/** Respostas por link, no máximo (um link partilhado por engano não enche a lista). */
export const maxAnswers = 500;

export interface BirthdayRequest {
  token: string;
  /** Quantas pessoas já deixaram a data por este link. */
  answers: number;
}

/** O que a página do link mostra de quem pede. */
export interface RequestOwner {
  user_id: string;
  name: string;
}
