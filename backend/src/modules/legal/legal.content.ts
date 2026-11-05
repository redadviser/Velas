/**
 * Textos legais da Birthdayly: Termos de Utilização e como apagar a conta. A
 * Política de Privacidade é a da empresa, no site dela (LegalContact.privacyUrl).
 *
 * Mudar o conteúdo de forma relevante = mudar [termsVersion]: a app pede a
 * todos que aceitem a nova versão (ver migrations/019_legal.sql).
 *
 * RASCUNHO escrito a partir do que a app faz; deve ser revisto por um jurista
 * antes do lançamento público.
 */
export const termsVersion = '2026-11-05';

/** Idade mínima para usar a app (confirmada no registo). */
export const minimumAge = 16;

export interface LegalSection {
  title: string;
  paragraphs?: string[];
  bullets?: string[];
}

export interface LegalDoc {
  title: string;
  /** Parágrafo de abertura (opcional). */
  intro?: string;
  /** Data da versão (AAAA-MM-DD), mostrada como "Última atualização". */
  updated?: string;
  sections: LegalSection[];
}

/** Quem é responsável e como contactar (LEGAL_ENTITY, SUPPORT_EMAIL, PRIVACY_URL). */
export interface LegalContact {
  entity: string;
  email?: string;
  /** A Política de Privacidade (a da empresa, no site dela). */
  privacyUrl: string;
}

const contactLine = (c: LegalContact) =>
  c.email ? `pelo email ${c.email}` : 'através da app (Perfil → Ajuda e contacto)';

export function termsOfUse(c: LegalContact): LegalDoc {
  const contact = c.email ? `pelo email ${c.email}` : 'através da app, em Perfil → Ajuda e contacto';
  return {
    title: 'Termos de Utilização',
    updated: termsVersion,
    sections: [
      {
        title: '1. Objeto',
        paragraphs: [
          `Estes Termos regulam a utilização da aplicação Birthdayly, disponibilizada por ${c.entity.replace(/\.$/, '')}. Ao criar uma conta, o utilizador declara que leu e aceita estes Termos e a Política de Privacidade.`,
        ],
      },
      {
        title: '2. Conta',
        paragraphs: [
          `A Birthdayly destina-se a maiores de ${minimumAge} anos. O utilizador compromete-se a indicar dados verdadeiros e é responsável pela confidencialidade da sua palavra-passe e por toda a atividade realizada na sua conta.`,
          'A conta pode ser eliminada a qualquer momento em Perfil → Eliminar conta, com confirmação por email.',
        ],
      },
      {
        title: '3. Utilização',
        paragraphs: [
          'A aplicação destina-se a uso pessoal e não comercial. Não é permitido utilizá-la para assediar ou ameaçar terceiros, enviar spam ou datas falsas através dos links de pedido, publicar conteúdo ilegal, ofensivo ou de cariz sexual, fazer-se passar por outra pessoa, ou tentar aceder a contas e dados alheios.',
          'Os aniversários de terceiros que o utilizador regista são para seu uso pessoal e não devem ser partilhados para outros fins.',
        ],
      },
      {
        title: '4. Conteúdos',
        paragraphs: [
          'As mensagens, fotografias, vídeos e restantes conteúdos enviados continuam a pertencer ao utilizador, que é responsável pelos mesmos. O utilizador autoriza-nos apenas a guardá-los e a apresentá-los às pessoas a quem os dirige.',
          'Qualquer utilizador pode ser bloqueado ou denunciado. Reservamo-nos o direito de remover conteúdos e de suspender ou eliminar contas que violem estes Termos.',
        ],
      },
      {
        title: '5. Prendas em grupo',
        paragraphs: [
          'A funcionalidade de prendas em grupo serve apenas para organizar a compra. Os pagamentos são feitos diretamente entre os participantes, sem intervenção nem custos da Birthdayly, que não é parte na compra e não responde por acertos ou reembolsos entre membros do grupo.',
        ],
      },
      {
        title: '6. Birthdayly+',
        paragraphs: [
          'O Birthdayly+ é uma subscrição mensal ou anual, adquirida e paga através da App Store ou do Google Play, com o preço indicado antes da compra. Renova-se automaticamente até ser cancelada nas definições de subscrições da respetiva loja, mantendo-se ativa até ao fim do período já pago. Os reembolsos seguem as regras da loja onde foi feita a compra.',
          'Cada conta pode usar uma única vez o período experimental gratuito de 30 dias. Eliminar a conta não cancela a subscrição na loja.',
        ],
      },
      {
        title: '7. Disponibilidade e responsabilidade',
        paragraphs: [
          'Procuramos manter o serviço disponível e os lembretes pontuais, mas não garantimos o funcionamento ininterrupto da aplicação nem a entrega de todas as notificações, que depende também do telemóvel e dos serviços da Apple e da Google. Na medida permitida por lei, não respondemos por danos indiretos decorrentes da utilização da aplicação.',
        ],
      },
      {
        title: '8. Alterações',
        paragraphs: [
          'Podemos alterar estes Termos. Sempre que a alteração for relevante, a aplicação pede ao utilizador que aceite a nova versão antes de continuar.',
        ],
      },
      {
        title: '9. Reclamações e litígios',
        paragraphs: [
          `Reclamações e pedidos de apoio podem ser enviados ${contact}. O utilizador pode ainda recorrer ao Livro de Reclamações Eletrónico (www.livroreclamacoes.pt).`,
          'Em caso de litígio de consumo, o consumidor pode recorrer a uma entidade de resolução alternativa de litígios. A lista está disponível em www.consumidor.gov.pt.',
          'Estes Termos regem-se pela lei portuguesa.',
        ],
      },
    ],
  };
}

export function deleteAccountDoc(c: LegalContact): LegalDoc {
  return {
    title: 'Apagar a conta',
    intro:
      'Podes apagar a tua conta da Birthdayly e todos os dados associados a qualquer momento. Para tua segurança, ' +
      'enviamos primeiro um email com um link: a conta só é apagada quando abres o link e confirmas.',
    sections: [
      {
        title: 'Na app',
        bullets: [
          'Abre a Birthdayly e vai ao Perfil.',
          'Em "Privacidade e dados", toca em "Eliminar conta".',
          'Recebes um email no endereço da conta. Abre o link (vale 24 horas) e confirma.',
        ],
      },
      {
        title: 'Sem a app',
        paragraphs: [
          `Escreve o email da conta no formulário abaixo e recebes o mesmo link de confirmação. Se não tiveres acesso a esse email, contacta-nos ${contactLine(c)}.`,
        ],
      },
      {
        title: 'O que é apagado',
        paragraphs: [
          'O perfil, os aniversários, as ideias de presente, as mensagens, os cartões, as fotografias, as conversas privadas e os grupos que administras, de forma definitiva. Os registos de faturação das subscrições são guardados apenas pelo tempo que a lei exige.',
          'Apagar a conta não cancela uma subscrição do Birthdayly+: cancela-a na App Store ou no Google Play.',
        ],
      },
    ],
  };
}
