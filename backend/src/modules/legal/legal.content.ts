/**
 * Textos legais da Birthdayly: Política de Privacidade e Termos de Utilização.
 *
 * Mudar o conteúdo de forma relevante = mudar [termsVersion]: a app pede a
 * todos que aceitem a nova versão (ver migrations/019_legal.sql).
 *
 * RASCUNHO escrito a partir do que a app faz; deve ser revisto por um jurista
 * antes do lançamento público.
 */
export const termsVersion = '2026-10-22';

/** Idade mínima para usar a app (confirmada no registo). */
export const minimumAge = 16;

export interface LegalSection {
  title: string;
  paragraphs?: string[];
  bullets?: string[];
}

export interface LegalDoc {
  title: string;
  intro: string;
  sections: LegalSection[];
}

/** Quem é responsável e como contactar (LEGAL_ENTITY, SUPPORT_EMAIL). */
export interface LegalContact {
  entity: string;
  email?: string;
}

const contactLine = (c: LegalContact) =>
  c.email ? `pelo email ${c.email}` : 'através da app (Perfil → Ajuda e contacto)';

export function privacyPolicy(c: LegalContact): LegalDoc {
  return {
    title: 'Política de Privacidade',
    intro:
      'Esta política explica que dados a Birthdayly trata, para quê, com quem os partilha e quais são os teus direitos. ' +
      'Escrevemo-la em linguagem simples.',
    sections: [
      {
        title: '1. Quem é responsável',
        paragraphs: [`O responsável pelo tratamento dos dados é ${c.entity}. Podes contactar-nos ${contactLine(c)}.`],
      },
      {
        title: '2. Que dados tratamos',
        bullets: [
          'Conta: nome, email, username, palavra-passe (guardada cifrada, nunca em texto), telemóvel (opcional), fotografia de perfil e, se entrares com o Google, o identificador da tua conta Google.',
          'Aniversários que acrescentas: nome, data de nascimento, relação, categoria, fotografia, notas, ideias de presente, mensagens de parabéns e o histórico do que lhes deste ou escreveste.',
          'Contactos do telemóvel: só quando escolhes "Adicionar dos contactos", e só são enviados os contactos que escolhes acrescentar.',
          'Conteúdo social: amigos, conversas (texto, imagens, GIFs e stickers), cartões de parabéns (com fotografia, vídeo ou áudio, se os juntares), o teu mural e as fotografias do álbum.',
          'Prendas em grupo e pagamentos: os grupos em que participas, os valores, quem pagou e o estado de cada pagamento. Os dados do cartão são tratados pela Stripe e nunca chegam aos nossos servidores. Guardamos o número MB WAY se pedires para o guardar.',
          'Dados técnicos: o endereço IP e a hora dos pedidos (para segurança e para travar abusos), e se estás online, se não desligares essa opção.',
          'Denúncias e bloqueios que fazes, e as denúncias feitas sobre ti.',
        ],
      },
      {
        title: '3. Para que usamos os dados e com que fundamento',
        bullets: [
          'Para prestar o serviço que pedes (execução do contrato): lembrar aniversários, guardar os teus dados, as conversas, os cartões e as prendas em grupo, e processar os pagamentos.',
          'Para manter a app segura (interesse legítimo): prevenir spam e abusos, limitar pedidos, analisar denúncias e aplicar bloqueios.',
          'Com o teu consentimento, que podes retirar a qualquer momento: notificações, acesso aos contactos, à câmara, ao microfone e às fotografias do telemóvel.',
          'Para cumprir obrigações legais, por exemplo de faturação e contabilidade dos pagamentos.',
        ],
        paragraphs: ['Não vendemos os teus dados nem os usamos para publicidade.'],
      },
      {
        title: '4. Com quem partilhamos',
        bullets: [
          'Fornecedor de alojamento dos servidores, onde os dados ficam guardados.',
          'Stripe, para os pagamentos dentro da app.',
          'Google, se escolheres entrar com o Google.',
          'GIPHY, que recebe o que pesquisas quando procuras GIFs ou stickers.',
          'O fornecedor de email, para mensagens como a recuperação da palavra-passe.',
          'Os outros utilizadores, só o que tu partilhas com eles: o teu perfil com amigos e membros dos teus grupos, as tuas mensagens nas conversas e os cartões que envias.',
        ],
        paragraphs: [
          'Os links de cartões de parabéns e de pedido de aniversário funcionam como um segredo: quem tiver o link consegue ver o cartão ou deixar a data. Partilha-os só com quem queres.',
          'Alguns destes serviços podem tratar dados fora do Espaço Económico Europeu. Nesses casos exigimos garantias adequadas, como as cláusulas contratuais-tipo aprovadas pela Comissão Europeia.',
        ],
      },
      {
        title: '5. Dados de outras pessoas',
        paragraphs: [
          'Os aniversários que acrescentas sobre familiares e amigos são guardados só para ti e não são mostrados a mais ninguém. Usa-os apenas para fins pessoais.',
          'Quem deixa a sua data através de um link de pedido escolhe fazê-lo, e essa data só entra na lista de quem pediu se essa pessoa a aceitar.',
        ],
      },
      {
        title: '6. Quanto tempo guardamos',
        paragraphs: [
          'Guardamos os dados enquanto tiveres conta. Ao apagares a conta apagamos todos os teus dados e ficheiros, exceto os registos de pagamentos que a lei nos obriga a guardar, e as denúncias pelo tempo necessário para as analisar.',
          'Os links de pedido de aniversário expiram ao fim de 30 dias.',
        ],
      },
      {
        title: '7. Os teus direitos',
        bullets: [
          'Acesso e portabilidade: no Perfil, em "Exportar os meus dados", recebes um ficheiro com todos os teus dados.',
          'Retificação: podes corrigir os teus dados a qualquer momento na app.',
          'Apagamento: no Perfil, em "Eliminar conta". O apagamento é definitivo.',
          'Oposição, limitação e retirar o consentimento: nas definições da app ou contactando-nos.',
          'Queixa: podes apresentar reclamação à Comissão Nacional de Proteção de Dados (www.cnpd.pt).',
        ],
        paragraphs: [`Para exercer qualquer direito, contacta-nos ${contactLine(c)}. Respondemos no prazo de um mês.`],
      },
      {
        title: '8. Menores',
        paragraphs: [
          `A Birthdayly destina-se a pessoas com ${minimumAge} anos ou mais. Se soubermos que uma conta pertence a alguém mais novo, apagamo-la.`,
        ],
      },
      {
        title: '9. Segurança',
        paragraphs: [
          'As comunicações são cifradas (HTTPS), as palavras-passe são guardadas cifradas, cada conta só acede aos seus dados e as fotografias são servidas por links temporários.',
        ],
      },
      {
        title: '10. Alterações',
        paragraphs: [
          `Esta é a versão de ${termsVersion}. Se a mudarmos de forma relevante, a app pede-te para aceitares a nova versão.`,
        ],
      },
    ],
  };
}

export function termsOfUse(c: LegalContact): LegalDoc {
  return {
    title: 'Termos de Utilização',
    intro: `Estes termos regem a utilização da Birthdayly, prestada por ${c.entity}. Ao criares conta ou ao continuares com o Google, aceitas estes termos e a Política de Privacidade.`,
    sections: [
      {
        title: '1. Quem pode usar',
        paragraphs: [
          `Precisas de ter ${minimumAge} anos ou mais. Para receber pagamentos dentro da app, a Stripe pode exigir que sejas maior de idade.`,
        ],
      },
      {
        title: '2. A tua conta',
        paragraphs: [
          'És responsável por manter a tua palavra-passe segura e pelo que é feito com a tua conta. Os dados que dás têm de ser verdadeiros.',
        ],
      },
      {
        title: '3. Utilização aceitável',
        paragraphs: ['Não é permitido usar a Birthdayly para:'],
        bullets: [
          'assediar, ameaçar ou intimidar outras pessoas;',
          'enviar spam, publicidade não pedida ou nomes e datas falsos pelos links de pedido;',
          'partilhar conteúdo ilegal, violento, sexual explícito ou que incite ao ódio;',
          'fazer-te passar por outra pessoa ou criar contas falsas;',
          'tentar aceder a dados ou contas de outras pessoas, ou perturbar o funcionamento do serviço.',
        ],
      },
      {
        title: '4. O teu conteúdo',
        paragraphs: [
          'O que escreves e envias continua a ser teu. Dás-nos apenas a autorização necessária para o guardar e mostrar a quem o destinas. És responsável pelo conteúdo que partilhas.',
        ],
      },
      {
        title: '5. Denúncias e moderação',
        paragraphs: [
          'Podes denunciar e bloquear qualquer utilizador. Analisamos as denúncias e podemos remover conteúdo e suspender ou apagar contas que não cumpram estes termos.',
        ],
      },
      {
        title: '6. Prendas em grupo e pagamentos',
        paragraphs: [
          'Os pagamentos dentro da app são processados pela Stripe e vão diretamente para quem compra a prenda. A Birthdayly não é parte na compra da prenda nem guarda o dinheiro do grupo.',
          'Cada pagamento dentro da app tem uma taxa de serviço fixa, mostrada antes de pagares, além do custo do método de pagamento. Pagar por MB WAY diretamente a quem compra não tem custos da Birthdayly.',
          'Acertos e reembolsos entre membros de um grupo são da responsabilidade dos próprios membros.',
        ],
      },
      {
        title: '7. Birthdayly+',
        paragraphs: [
          'O Birthdayly+ junta funcionalidades extra. O período experimental é gratuito, dura 30 dias e só pode ser usado uma vez por conta. Quando a subscrição estiver à venda, os preços e as condições são mostrados antes da compra.',
        ],
      },
      {
        title: '8. Disponibilidade e responsabilidade',
        paragraphs: [
          'Fazemos o possível para que a app funcione sem falhas, mas não garantimos que esteja sempre disponível nem que os lembretes cheguem sempre a tempo. Na medida permitida pela lei, não somos responsáveis por danos indiretos resultantes da utilização da app.',
        ],
      },
      {
        title: '9. Terminar',
        paragraphs: ['Podes apagar a tua conta a qualquer momento no Perfil. Podemos suspender contas que violem estes termos.'],
      },
      {
        title: '10. Lei aplicável e contacto',
        paragraphs: [
          `Estes termos regem-se pela lei portuguesa. Para qualquer questão, contacta-nos ${contactLine(c)}. Versão de ${termsVersion}.`,
        ],
      },
    ],
  };
}

export function deleteAccountDoc(c: LegalContact): LegalDoc {
  return {
    title: 'Apagar a conta',
    intro: 'Podes apagar a tua conta da Birthdayly e todos os dados associados a qualquer momento.',
    sections: [
      {
        title: 'Na app',
        bullets: ['Abre a Birthdayly e vai ao Perfil.', 'Em "Privacidade e dados", toca em "Eliminar conta" e confirma.'],
      },
      {
        title: 'Sem a app',
        paragraphs: [
          `Se já não tiveres a app, pede o apagamento ${contactLine(c)}, a partir do email da conta. Tratamos o pedido no prazo de um mês.`,
        ],
      },
      {
        title: 'O que é apagado',
        paragraphs: [
          'O perfil, os aniversários, as ideias de presente, as mensagens, os cartões, as fotografias, as conversas privadas e os grupos que administras. Os registos de pagamentos são guardados apenas pelo tempo que a lei exige.',
        ],
      },
    ],
  };
}
