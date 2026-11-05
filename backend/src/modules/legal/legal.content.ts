/**
 * Textos legais da Birthdayly: Termos de Utilização e como apagar a conta. A
 * Política de Privacidade é a da empresa, no site dela (LegalContact.privacyUrl).
 *
 * Mudar o conteúdo de forma relevante = mudar [termsVersion]: a app pede a
 * todos que aceitem a nova versão (ver migrations/019_legal.sql).
 *
 * Deve ser revisto por um jurista antes do lançamento público.
 */
export const termsVersion = '2026-11-05';

/** Idade mínima para usar a app (confirmada no registo). */
export const minimumAge = 16;

export interface LegalSection {
  title: string;
  paragraphs?: string[];
  /** Passos numerados (ex.: como apagar a conta). */
  steps?: string[];
}

export interface LegalDoc {
  title: string;
  /** Parágrafo de abertura (opcional). */
  intro?: string;
  /** Data da versão (AAAA-MM-DD), mostrada no topo. */
  updated?: string;
  /** Cláusulas numeradas (1., 1.1., 1.2.) e índice no topo, como num contrato. */
  numbered?: boolean;
  sections: LegalSection[];
}

/** Quem é responsável e como contactar (LEGAL_ENTITY, LEGAL_ADDRESS, SUPPORT_EMAIL, PRIVACY_URL). */
export interface LegalContact {
  entity: string;
  address?: string;
  email?: string;
  /** A Política de Privacidade (a da empresa, no site dela). */
  privacyUrl: string;
}

const contactLine = (c: LegalContact) =>
  c.email ? `pelo email ${c.email}` : 'através da app, na opção «Ajuda e contacto» do Perfil';

export function termsOfUse(c: LegalContact): LegalDoc {
  const entity = c.entity.replace(/\.$/, '');
  const seat = c.address ? `, com sede em ${c.address}` : '';
  return {
    title: 'Termos de Utilização',
    updated: termsVersion,
    numbered: true,
    sections: [
      {
        title: 'Identificação e objeto',
        paragraphs: [
          `A aplicação Birthdayly (a «Aplicação») é disponibilizada pela ${entity}${seat} (a «Birthdayly», «nós»).`,
          'Os presentes Termos regulam o acesso e a utilização da Aplicação por qualquer pessoa que nela crie uma conta (o «Utilizador»).',
          'Ao criar uma conta, o Utilizador declara ter lido e aceite estes Termos e a Política de Privacidade.',
        ],
      },
      {
        title: 'Conta de utilizador',
        paragraphs: [
          `A Aplicação destina-se a pessoas com idade igual ou superior a ${minimumAge} anos.`,
          'O Utilizador obriga-se a fornecer dados verdadeiros e atualizados e é responsável pela confidencialidade da sua palavra-passe e por toda a atividade realizada através da sua conta.',
          'O Utilizador pode eliminar a conta a qualquer momento, na opção «Eliminar conta» do Perfil. A eliminação é confirmada por email e é definitiva.',
        ],
      },
      {
        title: 'Regras de utilização',
        paragraphs: [
          'A Aplicação destina-se exclusivamente a uso pessoal e não comercial.',
          'É proibido utilizar a Aplicação para assediar, ameaçar ou intimidar terceiros; enviar mensagens não solicitadas ou datas falsas através dos links de pedido; publicar conteúdos ilegais, ofensivos ou de natureza sexual; fazer-se passar por outra pessoa; ou tentar aceder a contas e dados de terceiros.',
          'Os dados de terceiros que o Utilizador regista, nomeadamente nomes e datas de aniversário, destinam-se apenas ao seu uso pessoal.',
        ],
      },
      {
        title: 'Conteúdos do utilizador',
        paragraphs: [
          'As mensagens, fotografias, vídeos e demais conteúdos enviados pelo Utilizador permanecem sua propriedade, sendo o Utilizador o único responsável pelos mesmos.',
          'O Utilizador concede à Birthdayly apenas a autorização necessária para armazenar esses conteúdos e apresentá-los aos destinatários que escolher.',
          'A Birthdayly pode remover conteúdos e suspender ou eliminar contas que violem estes Termos, nomeadamente na sequência de denúncias de outros utilizadores.',
        ],
      },
      {
        title: 'Prendas em grupo',
        paragraphs: [
          'A funcionalidade de prendas em grupo destina-se apenas a organizar a compra de uma prenda entre vários participantes.',
          'Os pagamentos são efetuados diretamente entre os participantes. A Birthdayly não intervém nos pagamentos, não cobra qualquer valor e não é parte na compra, não sendo responsável por acertos ou reembolsos entre os membros do grupo.',
        ],
      },
      {
        title: 'Subscrição Birthdayly+',
        paragraphs: [
          'O Birthdayly+ é uma subscrição mensal ou anual que dá acesso a funcionalidades adicionais. É adquirida e paga através da App Store ou do Google Play, pelo preço indicado antes da compra.',
          'A subscrição renova-se automaticamente no fim de cada período, até ser cancelada pelo Utilizador nas definições de subscrições da respetiva loja. Após o cancelamento, mantém-se ativa até ao fim do período já pago.',
          'Os pedidos de reembolso seguem as condições da loja onde a compra foi feita.',
          'Cada conta pode beneficiar uma única vez de um período experimental gratuito de 30 dias.',
          'A eliminação da conta não cancela a subscrição na loja.',
        ],
      },
      {
        title: 'Responsabilidade',
        paragraphs: [
          'A Birthdayly procura assegurar o normal funcionamento da Aplicação, mas não garante que esta esteja sempre disponível nem que todos os lembretes e notificações sejam entregues, uma vez que a entrega depende também do equipamento do Utilizador e de serviços da Apple e da Google.',
          'Na medida permitida por lei, a Birthdayly não é responsável por danos indiretos resultantes da utilização ou da impossibilidade de utilização da Aplicação.',
        ],
      },
      {
        title: 'Propriedade intelectual',
        paragraphs: [
          'A Aplicação, a marca Birthdayly, o seu design e o software são propriedade da Birthdayly ou dos respetivos licenciantes, não sendo permitida a sua reprodução ou utilização fora do âmbito destes Termos.',
        ],
      },
      {
        title: 'Alteração dos Termos',
        paragraphs: [
          'A Birthdayly pode alterar estes Termos. Sempre que a alteração seja relevante, a Aplicação solicita ao Utilizador a aceitação da nova versão antes de continuar a utilizá-la.',
        ],
      },
      {
        title: 'Reclamações e resolução de litígios',
        paragraphs: [
          `Pedidos de apoio e reclamações podem ser enviados ${contactLine(c)}. O Utilizador pode também recorrer ao Livro de Reclamações Eletrónico, em www.livroreclamacoes.pt.`,
          'Em caso de litígio de consumo, o consumidor pode recorrer a uma entidade de resolução alternativa de litígios de consumo. A lista destas entidades está disponível em www.consumidor.gov.pt.',
        ],
      },
      {
        title: 'Lei aplicável',
        paragraphs: ['Estes Termos regem-se pela lei portuguesa.'],
      },
    ],
  };
}

export function deleteAccountDoc(c: LegalContact): LegalDoc {
  return {
    title: 'Eliminar a conta',
    intro:
      'Pode eliminar a sua conta Birthdayly e todos os dados associados a qualquer momento. Por segurança, a eliminação é confirmada através de um link enviado para o email da conta.',
    sections: [
      {
        title: 'Na aplicação',
        steps: [
          'Abra a Birthdayly e aceda ao Perfil.',
          'Na secção «Privacidade e dados», escolha «Eliminar conta».',
          'Abra o link que recebe por email (válido durante 24 horas) e confirme.',
        ],
      },
      {
        title: 'Sem a aplicação',
        paragraphs: [
          `Indique o email da conta no formulário abaixo para receber o link de confirmação. Se já não tiver acesso a esse email, contacte-nos ${contactLine(c)}.`,
        ],
      },
      {
        title: 'Dados eliminados',
        paragraphs: [
          'São eliminados de forma definitiva o perfil, os aniversários, as ideias de presente, as mensagens, os cartões, as fotografias, as conversas privadas e os grupos que administra. Os registos de faturação das subscrições são conservados apenas pelo período exigido por lei.',
          'A eliminação da conta não cancela uma subscrição Birthdayly+, que deve ser cancelada na App Store ou no Google Play.',
        ],
      },
    ],
  };
}
