// Testes de integração: a API completa contra um PostgreSQL real em memória
// (PGlite), com as migrações aplicadas.
import { mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';

import type { FastifyInstance } from 'fastify';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';

import { buildApp } from '../src/app.js';
import { HttpError } from '../src/core/errors.js';
import { AccessTokens } from '../src/modules/auth/tokens.js';
import type { GoogleIdentity } from '../src/modules/auth/google.js';
import type { Config } from '../src/config/env.js';
import type { Mail } from '../src/core/mailer.js';
import { migrate } from '../src/core/migrations.js';
import { PhotoStorage } from '../src/core/storage.js';
import type { Db } from '../src/core/database.js';
import { GifsService } from '../src/modules/gifs/gifs.service.js';
import type { GatewayStatus, PaymentsGateway } from '../src/modules/payments/gateway.js';
import { createTestDb } from './pglite-pool.js';

const secret = 'test-secret-with-at-least-32-characters!!';
const sent: Mail[] = [];
const googleTokens = new Map<string, GoogleIdentity>();

let db: Db;
let closeDb: () => Promise<void>;
let app: FastifyInstance;
let uploadDir: string;

// Respostas do GIPHY (só a parte que a API usa).
const giphyCalls: string[] = [];
const fakeGiphy: typeof fetch = async (input) => {
  giphyCalls.push(String(input));
  const image = (id: string, w: string) => ({ url: `https://media1.giphy.com/media/${id}/${w}.gif`, width: '200', height: '150' });
  return new Response(
    JSON.stringify({
      data: [
        { id: 'abc', images: { fixed_width: image('abc', '200w'), fixed_width_small: image('abc', '100w') } },
        // URL fora do GIPHY: ignorado.
        { id: 'bad', images: { fixed_width: { url: 'https://evil.example/x.gif', width: '1', height: '1' } } },
      ],
      pagination: { total_count: 100, count: 2, offset: 0 },
    }),
    { headers: { 'content-type': 'application/json' } },
  );
};

// Stripe falsa: guarda o que lhe pedem e responde como a verdadeira.
const stripeCalls: { op: string; args: Record<string, unknown> }[] = [];
const intentStatus = new Map<string, GatewayStatus>();
const fakeStripe: PaymentsGateway = {
  async createAccount(p) {
    stripeCalls.push({ op: 'createAccount', args: p });
    return { id: `acct_${p.userId.slice(0, 8)}` };
  },
  async onboardingLink(accountId, urls) {
    stripeCalls.push({ op: 'onboardingLink', args: { accountId, ...urls } });
    return `https://connect.stripe.test/setup/${accountId}`;
  },
  async accountReady() {
    return true;
  },
  async startMbWay(p) {
    stripeCalls.push({ op: 'startMbWay', args: p });
    const id = `pi_${stripeCalls.length}`;
    intentStatus.set(id, 'pending');
    return { paymentIntentId: id, status: 'pending' };
  },
  async createCheckout(p) {
    stripeCalls.push({ op: 'createCheckout', args: p });
    return { sessionId: `cs_${stripeCalls.length}`, url: `https://checkout.stripe.test/${p.method}` };
  },
  async paymentIntentStatus(id) {
    return { status: intentStatus.get(id) ?? 'pending' };
  },
  async checkoutStatus() {
    return { status: 'pending' };
  },
  parseWebhook(raw, signature) {
    if (signature !== 'assinatura-valida') throw new Error('invalid signature');
    const e = JSON.parse(raw.toString()) as { type: string; data: { object: { id: string } } };
    return { type: e.type, object: e.data.object };
  },
};

// JPEG mínimo (só os bytes iniciais interessam à validação).
const jpeg = Buffer.from([0xff, 0xd8, 0xff, 0xe0, 0, 0x10, 0x4a, 0x46, 0x49, 0x46, 0, 1]);

beforeAll(async () => {
  ({ db, close: closeDb } = await createTestDb());
  await migrate(db, () => {});
  uploadDir = await mkdtemp(path.join(tmpdir(), 'velas-test-'));
  const config: Config = {
    port: 0,
    host: '127.0.0.1',
    database: { host: '', port: 5432, database: 'test', user: '', password: '', ssl: false },
    jwtSecret: secret,
    publicUrl: 'http://api.test',
    googleClientIds: ['test'],
    uploadDir,
    mail: { from: 'test@velas' },
    appScheme: 'com.eupasoft.velas',
    rateLimit: false,
    docs: true,
    androidPackage: 'com.velas.app',
    playStoreUrl: 'https://play.google.com/store/apps/details?id=com.velas.app',
    giphyApiKey: 'giphy-test-key',
  };
  app = await buildApp({
    config,
    db,
    storage: new PhotoStorage(uploadDir, config.publicUrl, secret),
    tokens: new AccessTokens(secret),
    mail: async (m) => {
      sent.push(m);
    },
    verifyGoogle: async (token) => {
      const identity = googleTokens.get(token);
      if (!identity) throw new HttpError(401, 'invalid_google_token');
      return identity;
    },
    fetch: fakeGiphy,
    payments: fakeStripe,
  });
}, 60_000);

afterAll(async () => {
  await app?.close();
  await closeDb?.();
  if (uploadDir) await rm(uploadDir, { recursive: true, force: true });
});

interface Session {
  access_token: string;
  refresh_token: string;
  user: { id: string; username: string | null; email: string; display_name: string };
}

async function call(method: string, url: string, opts: { token?: string; body?: unknown; raw?: Buffer } = {}) {
  const res = await app.inject({
    method: method as 'GET',
    url,
    headers: {
      ...(opts.token ? { authorization: `Bearer ${opts.token}` } : {}),
      ...(opts.raw ? { 'content-type': 'image/jpeg' } : {}),
    },
    ...(opts.raw ? { payload: opts.raw } : opts.body !== undefined ? { payload: opts.body as object } : {}),
  });
  const json = res.headers['content-type']?.toString().includes('json');
  if (res.statusCode >= 500) console.error(method, url, res.body);
  return { status: res.statusCode, body: json ? res.json() : null, raw: res };
}

const uuid = () => crypto.randomUUID();

async function signup(name: string, username: string, email: string, password = 'password1') {
  const res = await call('POST', '/auth/signup', { body: { name, username, email, password } });
  expect(res.status).toBe(201);
  return res.body as Session;
}

describe('autenticação', () => {
  it('regista, entra por email e por username, e recusa duplicados', async () => {
    const s = await signup('Ana Silva', 'Ana.Silva', 'ana@ex.pt');
    expect(s.user.username).toBe('ana.silva');
    expect(s.user.display_name).toBe('Ana Silva');

    expect((await call('POST', '/auth/signup', { body: { name: 'X', username: 'ana.silva', email: 'x@ex.pt', password: 'password1' } })).body.error).toBe('username_taken');
    expect((await call('POST', '/auth/signup', { body: { name: 'X', username: 'outro', email: 'ANA@ex.pt', password: 'password1' } })).body.error).toBe('email_taken');

    expect((await call('POST', '/auth/login', { body: { identifier: 'ana@ex.pt', password: 'password1' } })).status).toBe(200);
    expect((await call('POST', '/auth/login', { body: { identifier: '@ana.silva', password: 'password1' } })).status).toBe(200);
    const wrong = await call('POST', '/auth/login', { body: { identifier: 'ana@ex.pt', password: 'errada123' } });
    expect(wrong.status).toBe(401);
    expect(wrong.body.error).toBe('invalid_credentials');

    const check = await call('POST', '/auth/signup-check', { body: { username: 'ANA.SILVA', phone: null } });
    expect(check.body).toEqual({ username_taken: true, phone_taken: false });
  });

  it('roda o refresh token e rejeita o antigo', async () => {
    const s = await signup('Rui', 'rui', 'rui@ex.pt');
    const r1 = await call('POST', '/auth/refresh', { body: { refresh_token: s.refresh_token } });
    expect(r1.status).toBe(200);
    expect((await call('POST', '/auth/refresh', { body: { refresh_token: s.refresh_token } })).status).toBe(401);
    expect((await call('GET', '/me', { token: r1.body.access_token })).body.username).toBe('rui');
    expect((await call('GET', '/me')).status).toBe(401);
  });

  it('entra com Google: cria conta, reutiliza-a e liga a uma conta existente', async () => {
    googleTokens.set('tok-new-0123456789abcdef', { sub: 'g-1', email: 'Joana.Costa@gmail.com', emailVerified: true, name: 'Joana Costa' });
    const first = await call('POST', '/auth/google', { body: { id_token: 'tok-new-0123456789abcdef' } });
    expect(first.status).toBe(200);
    expect(first.body.user.username).toBe('joana.costa');
    expect(first.body.user.has_password).toBe(false);
    const again = await call('POST', '/auth/google', { body: { id_token: 'tok-new-0123456789abcdef' } });
    expect(again.body.user.id).toBe(first.body.user.id);

    // Conta só Google a tentar palavra-passe.
    const pw = await call('POST', '/auth/login', { body: { identifier: 'joana.costa@gmail.com', password: 'qualquer1' } });
    expect(pw.body.error).toBe('google_account');

    // Liga a uma conta criada com email e palavra-passe.
    const s = await signup('Marta', 'marta', 'marta@ex.pt');
    googleTokens.set('tok-link-0123456789abcdef', { sub: 'g-2', email: 'marta@ex.pt', emailVerified: true, name: 'Marta G' });
    const linked = await call('POST', '/auth/google', { body: { id_token: 'tok-link-0123456789abcdef' } });
    expect(linked.body.user.id).toBe(s.user.id);
    expect(linked.body.user.google_linked).toBe(true);

    // Email não verificado não liga contas.
    await signup('Pedro', 'pedro', 'pedro@ex.pt');
    googleTokens.set('tok-unverified-0123456789abcdef', { sub: 'g-3', email: 'pedro@ex.pt', emailVerified: false, name: 'P' });
    expect((await call('POST', '/auth/google', { body: { id_token: 'tok-unverified-0123456789abcdef' } })).body.error).toBe('email_taken');
    expect((await call('POST', '/auth/google', { body: { id_token: 'tok-invalido-xxxxxxxxxxxx' } })).status).toBe(401);
  });

  it('recupera a palavra-passe pelo link do email', async () => {
    await signup('Sofia', 'sofia', 'sofia@ex.pt');
    expect((await call('POST', '/auth/password/forgot', { body: { email: 'naoexiste@ex.pt' } })).status).toBe(204);
    expect(sent).toHaveLength(0);
    expect((await call('POST', '/auth/password/forgot', { body: { email: 'sofia@ex.pt' } })).status).toBe(204);
    const token = /token=([A-Za-z0-9_-]+)/.exec(sent.at(-1)!.text)![1]!;

    const page = await call('GET', `/auth/reset?token=${token}`);
    expect(page.raw.body).toContain(`com.eupasoft.velas://auth-callback?type=recovery&token=${token}`);

    const session = await call('POST', '/auth/password/recover', { body: { token } });
    expect(session.status).toBe(200);
    expect((await call('POST', '/auth/password/recover', { body: { token } })).status).toBe(400);
    expect((await call('PUT', '/me/password', { token: session.body.access_token, body: { password: 'nova-pass-1' } })).status).toBe(204);
    expect((await call('POST', '/auth/login', { body: { identifier: 'sofia', password: 'nova-pass-1' } })).status).toBe(200);
  });
});

describe('dados pessoais', () => {
  let a: Session;
  let b: Session;
  const personId = uuid();

  beforeAll(async () => {
    a = await signup('Alice', 'alice', 'alice@ex.pt');
    b = await signup('Bruno', 'bruno', 'bruno@ex.pt');
  });

  it('começa com as categorias por defeito', async () => {
    const data = (await call('GET', '/data', { token: a.access_token })).body;
    expect(data.categories.map((c: { name: string }) => c.name)).toEqual(['Família', 'Amigos', 'Trabalho']);
    expect(data.people).toEqual([]);
  });

  it('guarda pessoas, prendas e mensagens no formato da app', async () => {
    const cat = (await call('GET', '/data', { token: a.access_token })).body.categories[0].id;
    const p = await call('PUT', `/people/${personId}`, {
      token: a.access_token,
      body: {
        id: personId, name: 'Helena', birth_day: 29, birth_month: 2, birth_year: 1960, relation: 'Mãe',
        category_id: cat, photo_path: 'outro-user/x.jpg', notes: '', gift_budget: 50.5, reminder_days: [0, 7],
        created_at: '2026-01-01T10:00:00.000Z',
      },
    });
    expect(p.status).toBe(200);
    expect(p.body.gift_budget).toBe(50.5);
    expect(p.body.reminder_days).toEqual([0, 7]);
    expect(p.body.photo_path).toBeNull(); // não se aceita o caminho vindo da app

    const giftId = uuid();
    expect((await call('PUT', `/gift-ideas/${giftId}`, { token: a.access_token, body: { person_id: personId, title: 'Livro', price: 19.9, link: '', notes: '', purchased: false } })).status).toBe(200);
    expect((await call('PUT', `/messages/${uuid()}`, { token: a.access_token, body: { person_id: personId, body: 'Parabéns!', tone: 'carinhoso' } })).status).toBe(200);

    const data = (await call('GET', '/data', { token: a.access_token })).body;
    expect(data.people).toHaveLength(1);
    expect(data.gift_ideas[0].price).toBe(19.9);
    expect(data.messages[0].body).toBe('Parabéns!');
  });

  it('isola os dados entre utilizadores', async () => {
    // B tenta sobrescrever a pessoa de A com o mesmo id.
    const hijack = await call('PUT', `/people/${personId}`, { token: b.access_token, body: { name: 'X', birth_day: 1, birth_month: 1 } });
    expect(hijack.status).toBe(404);
    // B tenta criar uma prenda ligada a uma pessoa de A.
    const gift = await call('PUT', `/gift-ideas/${uuid()}`, { token: b.access_token, body: { person_id: personId, title: 'X' } });
    expect(gift.status).toBe(403);
    expect((await call('GET', '/data', { token: b.access_token })).body.people).toEqual([]);
    await call('DELETE', `/people/${personId}`, { token: b.access_token });
    expect((await call('GET', '/data', { token: a.access_token })).body.people).toHaveLength(1);
  });

  it('carrega fotografias e serve-as por URL assinado', async () => {
    const res = await call('PUT', `/people/${personId}/photo`, { token: a.access_token, raw: jpeg });
    expect(res.status).toBe(200);
    expect(res.body.photo_path).toMatch(new RegExp(`^${a.user.id}/${personId}-\\d+\\.jpg$`));
    const url = new URL(res.body.photo_url);
    const file = await call('GET', url.pathname + url.search);
    expect(file.status).toBe(200);
    expect(file.raw.headers['content-type']).toBe('image/jpeg');
    expect((await call('GET', `${url.pathname}?exp=${url.searchParams.get('exp')}&sig=abc`)).status).toBe(403);

    expect((await call('PUT', `/people/${personId}/photo`, { token: b.access_token, raw: jpeg })).status).toBe(404);
    const notImage = await call('PUT', `/people/${personId}/photo`, { token: a.access_token, raw: Buffer.from('ola mundo, não sou imagem') });
    expect(notImage.status).toBe(415);

    expect((await call('DELETE', `/people/${personId}/photo`, { token: a.access_token })).status).toBe(204);
    expect((await call('GET', url.pathname + url.search)).status).toBe(404);
  });

  it('importa contactos em lote', async () => {
    const people = [
      { id: uuid(), name: 'Contacto 1', birth_day: 3, birth_month: 4 },
      { id: uuid(), name: 'Contacto 2', birth_day: 10, birth_month: 12, birth_year: 1990 },
    ];
    const res = await call('POST', '/people/import', { token: a.access_token, body: { people } });
    expect(res.status).toBe(200);
    expect(res.body.people).toHaveLength(2);
    expect((await call('GET', '/data', { token: a.access_token })).body.people).toHaveLength(3);
    const invalid = await call('POST', '/people/import', { token: a.access_token, body: { people: [{ id: uuid(), name: 'X', birth_day: 40, birth_month: 1 }] } });
    expect(invalid.status).toBe(400);
  });

  it('atualiza o perfil e deteta username ocupado', async () => {
    const res = await call('PATCH', '/me', {
      token: a.access_token,
      body: { display_name: 'Alice M', username: 'alice.m', phone: '+351912345678', reminder_hour: 8, payment_methods: { mbway_phone: '912345678', accepts_cash: true } },
    });
    expect(res.status).toBe(200);
    expect(res.body).toMatchObject({ display_name: 'Alice M', username: 'alice.m', phone: '+351912345678', reminder_hour: 8 });
    expect((await call('PATCH', '/me', { token: b.access_token, body: { username: 'alice.m' } })).body.error).toBe('username_taken');
    expect((await call('PATCH', '/me', { token: b.access_token, body: { phone: '+351912345678' } })).body.error).toBe('phone_taken');
  });
});

describe('prendas em grupo', () => {
  let admin: Session;
  let member: Session;
  let other: Session;
  const groupId = uuid();
  const adminMemberId = uuid();
  const guestId = uuid();

  beforeAll(async () => {
    admin = await signup('Carla', 'carla', 'carla@ex.pt');
    member = await signup('Diogo', 'diogo', 'diogo@ex.pt');
    other = await signup('Eva', 'eva', 'eva@ex.pt');
    await call('PATCH', '/me', { token: admin.access_token, body: { payment_methods: { iban: 'PT50000201231234567890154', accepts_cash: false } } });
  });

  it('cria o grupo com o administrador e um participante sem conta', async () => {
    const res = await call('PUT', `/groups/${groupId}`, {
      token: admin.access_token,
      body: {
        group: { id: groupId, created_by: 'ignorado', title: 'Prenda da Mãe', celebrant_name: 'Helena', target_amount: 90, split_mode: 'equal', buyer_member_id: null, deadline: '2026-12-24' },
        new_members: [
          { id: adminMemberId, user_id: admin.user.id, display_name: 'Carla', payment_methods: {} },
          { id: guestId, user_id: null, display_name: 'Tio Zé', payment_methods: {} },
        ],
      },
    });
    expect(res.status).toBe(200);
    expect(res.body.created_by).toBe(admin.user.id);
    expect(res.body.target_amount).toBe(90);
    expect(res.body.deadline).toBe('2026-12-24');
    expect(res.body.group_members.map((m: { username: string | null }) => m.username)).toEqual(['carla', null]);

    // Não se pode acrescentar outra conta diretamente.
    const sneaky = await call('PUT', `/groups/${groupId}`, {
      token: admin.access_token,
      body: { group: { title: 'Prenda da Mãe', celebrant_name: 'Helena', target_amount: 90 }, new_members: [{ id: uuid(), user_id: other.user.id, display_name: 'Eva' }] },
    });
    expect(sneaky.status).toBe(403);
    // Outro utilizador não edita nem vê.
    expect((await call('PUT', `/groups/${groupId}`, { token: other.access_token, body: { group: { title: 'X', celebrant_name: 'X', target_amount: 1 } } })).status).toBe(403);
    expect((await call('GET', '/groups', { token: other.access_token })).body).toEqual([]);
  });

  it('convida por username; o convidado aceita e vê os dados de pagamento', async () => {
    const found = await call('POST', '/users/find', { token: admin.access_token, body: { identifier: '@diogo' } });
    expect(found.body.user).toMatchObject({ user_id: member.user.id, username: 'diogo' });
    expect((await call('POST', '/users/find', { token: admin.access_token, body: { identifier: 'ninguem@ex.pt' } })).body.user).toBeNull();

    expect((await call('POST', `/groups/${groupId}/invitations`, { token: admin.access_token, body: { user_id: member.user.id } })).body.result).toBe('invited');
    expect((await call('POST', `/groups/${groupId}/invitations`, { token: admin.access_token, body: { user_id: member.user.id } })).body.result).toBe('already_invited');
    expect((await call('POST', `/groups/${groupId}/invitations`, { token: member.access_token, body: { user_id: other.user.id } })).status).toBe(403);

    const inbox = (await call('GET', '/invitations', { token: member.access_token })).body;
    expect(inbox).toHaveLength(1);
    expect(inbox[0]).toMatchObject({ title: 'Prenda da Mãe', inviter_name: 'Carla', member_count: 2 });

    const accepted = await call('POST', `/invitations/${inbox[0].id}/respond`, { token: member.access_token, body: { accept: true } });
    expect(accepted.body.group_id).toBe(groupId);

    const payee = await call('GET', `/groups/${groupId}/payee`, { token: member.access_token });
    expect(payee.body).toEqual({ iban: 'PT50000201231234567890154', accepts_cash: false });
    expect((await call('GET', `/groups/${groupId}/payee`, { token: other.access_token })).status).toBe(403);
  });

  it('aplica as regras de pagamento por papel', async () => {
    const group = (await call('GET', '/groups', { token: member.access_token })).body[0];
    const me = group.group_members.find((m: { user_id: string }) => m.user_id === member.user.id);

    expect((await call('POST', `/group-members/${me.id}/paid`, { token: member.access_token, body: { method: 'mbway' } })).status).toBe(204);
    // O próprio não confirma a receção, nem muda valores.
    expect((await call('POST', `/group-members/${me.id}/confirmed`, { token: member.access_token, body: { confirmed: true } })).status).toBe(403);
    expect((await call('PATCH', `/group-members/${me.id}`, { token: member.access_token, body: { display_name: 'Diogo', custom_amount: 1, payment_methods: {} } })).status).toBe(403);
    // O administrador (comprador por defeito) confirma.
    expect((await call('POST', `/group-members/${me.id}/confirmed`, { token: admin.access_token, body: { confirmed: true } })).status).toBe(204);
    // Confirmar quem não marcou conta como pago em dinheiro.
    expect((await call('POST', `/group-members/${guestId}/confirmed`, { token: admin.access_token, body: { confirmed: true } })).status).toBe(204);

    const after = (await call('GET', '/groups', { token: admin.access_token })).body[0];
    const guest = after.group_members.find((m: { id: string }) => m.id === guestId);
    expect(guest.paid_method).toBe('cash');
    expect(after.group_members.find((m: { id: string }) => m.id === me.id).confirmed_at).not.toBeNull();

    // O administrador não pode sair do próprio grupo.
    expect((await call('DELETE', `/group-members/${adminMemberId}`, { token: admin.access_token })).status).toBe(403);
    // Só o comprador/administrador marca como comprado.
    expect((await call('POST', `/groups/${groupId}/purchased`, { token: member.access_token, body: { purchased: true } })).status).toBe(404);
  });

  it('entra por link e fecha quando a prenda é comprada', async () => {
    const code: string = (await call('GET', '/groups', { token: admin.access_token })).body[0].invite_code;
    // 8 caracteres sem ambiguidades (sem 0/O nem 1/I).
    expect(code).toMatch(/^[A-HJ-NP-Z2-9]{8}$/);
    const spaced = `${code.slice(0, 4)} ${code.slice(4)}`;

    // Página pública do link partilhado, com pré-visualização para as apps de mensagens.
    const page = await call('GET', `/g/${code.toLowerCase()}`);
    expect(page.status).toBe(200);
    expect(page.raw.body).toContain(`<div class="code" id="code">${spaced}</div>`);
    expect(page.raw.body).toContain(`<meta property="og:description" content="Código ${spaced} ·`);
    expect(page.raw.body).toContain('<meta property="og:image" content="http://localhost:80/og/invite.jpg">');
    const image = await call('GET', '/og/invite.jpg');
    expect(image.status).toBe(200);
    expect(image.raw.headers['content-type']).toBe('image/jpeg');
    expect(page.raw.body).toContain(`com.eupasoft.velas://app/join/${code}`);
    expect(page.raw.body).toContain(`intent://app/join/${code}#Intent;scheme=com.eupasoft.velas;package=com.velas.app;S.browser_fallback_url=https%3A%2F%2Fplay.google.com`);
    expect(page.raw.body).toContain('Descarregar para Android');
    expect(page.raw.body).not.toContain('Descarregar para iPhone');
    expect(page.raw.body).not.toContain('Prenda da Mãe'); // não revela o grupo
    expect((await call('GET', '/g/%3Cscript%3E')).status).toBe(404);

    // O código pode vir como a pessoa o escreve: minúsculas, espaços, hífens.
    const typed = encodeURIComponent(`${code.slice(0, 4).toLowerCase()}-${code.slice(4)}`);
    const preview = await call('GET', `/invite-codes/${typed}`, { token: other.access_token });
    expect(preview.body).toMatchObject({ id: groupId, admin_name: 'Carla', member_count: 3, already_member: false, closed: false });
    expect((await call('GET', '/invite-codes/NAOEXISTE1', { token: other.access_token })).body.error).toBe('invalid_code');

    const joined = await call('POST', `/invite-codes/${code}/join`, { token: other.access_token, body: { display_name: '' } });
    expect(joined.body.group_id).toBe(groupId);

    expect((await call('POST', `/groups/${groupId}/purchased`, { token: admin.access_token, body: { purchased: true } })).status).toBe(204);
    const late = await signup('Fábio', 'fabio', 'fabio@ex.pt');
    expect((await call('POST', `/invite-codes/${code}/join`, { token: late.access_token, body: {} })).body.error).toBe('group_closed');
  });

  it('eliminar a conta apaga os grupos de que é administrador', async () => {
    expect((await call('DELETE', '/me', { token: admin.access_token })).status).toBe(204);
    expect((await call('POST', '/auth/login', { body: { identifier: 'carla@ex.pt', password: 'password1' } })).status).toBe(401);
    expect((await call('GET', '/groups', { token: member.access_token })).body).toEqual([]);
    // Membro sai da conta: o grupo de outro administrador mantém-se.
    expect((await call('GET', '/me', { token: member.access_token })).status).toBe(200);
  });
});

describe('amigos e conversas', () => {
  let filipa: Session;
  let gil: Session;
  let hugo: Session;
  let direct: string;

  beforeAll(async () => {
    filipa = await signup('Filipa', 'filipa', 'filipa@ex.pt');
    gil = await signup('Gil', 'gil', 'gil@ex.pt');
    hugo = await signup('Hugo', 'hugo', 'hugo@ex.pt');
  });

  const send = (s: Session, conversation: string, body: object) =>
    call('POST', `/conversations/${conversation}/messages`, { token: s.access_token, body: { id: uuid(), ...body } });

  it('pede, aceita, recusa e remove amizades', async () => {
    const req = (from: Session, to: Session) =>
      call('POST', '/friends/requests', { token: from.access_token, body: { user_id: to.user.id } });

    expect((await req(filipa, gil)).body.result).toBe('sent');
    expect((await req(filipa, gil)).body.result).toBe('already_sent');
    expect((await req(filipa, filipa)).body.result).toBe('self');

    const gilList = (await call('GET', '/friends', { token: gil.access_token })).body;
    expect(gilList.incoming).toEqual([expect.objectContaining({ user_id: filipa.user.id, username: 'filipa' })]);
    expect((await call('GET', '/friends', { token: filipa.access_token })).body.outgoing).toHaveLength(1);
    // Só quem recebeu responde.
    expect((await call('POST', `/friends/requests/${gilList.incoming[0].id}/respond`, { token: filipa.access_token, body: { accept: true } })).status).toBe(404);
    expect((await call('POST', `/friends/requests/${gilList.incoming[0].id}/respond`, { token: gil.access_token, body: { accept: true } })).status).toBe(204);
    expect((await call('GET', '/friends', { token: filipa.access_token })).body.friends).toEqual([
      expect.objectContaining({ user_id: gil.user.id, display_name: 'Gil' }),
    ]);
    expect((await req(gil, filipa)).body.result).toBe('already_friends');

    // Recusar apaga o pedido; pedir de volta aceita logo.
    await req(hugo, filipa);
    const incoming = (await call('GET', '/friends', { token: filipa.access_token })).body.incoming;
    await call('POST', `/friends/requests/${incoming[0].id}/respond`, { token: filipa.access_token, body: { accept: false } });
    expect((await call('GET', '/friends', { token: hugo.access_token })).body.outgoing).toEqual([]);
    await req(hugo, gil);
    expect((await req(gil, hugo)).body.result).toBe('accepted');
    expect((await call('DELETE', `/friends/${hugo.user.id}`, { token: gil.access_token })).status).toBe(204);
    expect((await call('GET', '/friends', { token: hugo.access_token })).body.friends).toEqual([]);
  });

  it('conversa privada só entre amigos, com não lidas, respostas, reações e apagar', async () => {
    expect((await call('POST', '/conversations/direct', { token: hugo.access_token, body: { user_id: filipa.user.id } })).body.error).toBe('not_friends');

    const opened = await call('POST', '/conversations/direct', { token: filipa.access_token, body: { user_id: gil.user.id } });
    expect(opened.body).toMatchObject({ kind: 'direct', title: 'Gil', other_user: { user_id: gil.user.id }, unread_count: 0 });
    direct = opened.body.id;
    expect((await call('POST', '/conversations/direct', { token: gil.access_token, body: { user_id: filipa.user.id } })).body.id).toBe(direct);

    const id = uuid();
    const first = await call('POST', `/conversations/${direct}/messages`, { token: filipa.access_token, body: { id, kind: 'text', body: '  Olá! O que oferecemos à Rita?  ' } });
    expect(first.body).toMatchObject({ id, kind: 'text', body: 'Olá! O que oferecemos à Rita?', sender_name: 'Filipa', reactions: [] });
    // Reenviar a mesma mensagem não duplica.
    await call('POST', `/conversations/${direct}/messages`, { token: filipa.access_token, body: { id, kind: 'text', body: 'Olá!' } });
    expect((await send(filipa, direct, { kind: 'text', body: '   ' })).status).toBe(422);

    let gilConv = (await call('GET', '/conversations', { token: gil.access_token })).body.find((c: { id: string }) => c.id === direct);
    expect(gilConv).toMatchObject({ title: 'Filipa', unread_count: 1, last_message: { body: 'Olá! O que oferecemos à Rita?' } });

    const reply = await send(gil, direct, { kind: 'text', body: 'Um livro 📚', reply_to: id });
    expect(reply.body.reply).toMatchObject({ id, sender_name: 'Filipa' });
    expect((await call('PUT', `/chat-messages/${id}/reaction`, { token: gil.access_token, body: { emoji: '❤️' } })).body.reactions).toEqual([
      { emoji: '❤️', user_id: gil.user.id },
    ]);
    // Uma reação por pessoa: escolher outra substitui.
    expect((await call('PUT', `/chat-messages/${id}/reaction`, { token: gil.access_token, body: { emoji: '😂' } })).body.reactions).toHaveLength(1);

    await call('POST', `/conversations/${direct}/read`, { token: gil.access_token });
    gilConv = (await call('GET', '/conversations', { token: gil.access_token })).body.find((c: { id: string }) => c.id === direct);
    expect(gilConv.unread_count).toBe(0);
    const detail = await call('GET', `/conversations/${direct}`, { token: filipa.access_token });
    expect(detail.body.participants.map((p: { username: string }) => p.username)).toEqual(['filipa', 'gil']);
    expect(detail.body.participants[1].last_read_at).not.toBeNull();

    const page = await call('GET', `/conversations/${direct}/messages?limit=1`, { token: gil.access_token });
    expect(page.body).toMatchObject({ has_more: true, messages: [{ body: 'Um livro 📚' }] });
    const older = await call('GET', `/conversations/${direct}/messages?before=${page.body.messages[0].id}`, { token: gil.access_token });
    expect(older.body).toMatchObject({ has_more: false, messages: [{ id }] });

    // Quem não participa não vê nem escreve.
    expect((await call('GET', `/conversations/${direct}/messages`, { token: hugo.access_token })).status).toBe(404);
    expect((await send(hugo, direct, { kind: 'text', body: 'olá' })).status).toBe(404);

    // Só quem enviou apaga; fica "apagada" para os dois.
    expect((await call('DELETE', `/chat-messages/${id}`, { token: gil.access_token })).status).toBe(404);
    expect((await call('DELETE', `/chat-messages/${id}`, { token: filipa.access_token })).status).toBe(204);
    const after = await call('GET', `/conversations/${direct}/messages`, { token: gil.access_token });
    expect(after.body.messages.find((m: { id: string }) => m.id === id)).toMatchObject({ deleted: true, body: '', reactions: [] });
    expect(after.body.messages[0].reply).toMatchObject({ deleted: true, body: '' });
  });

  it('envia imagens, GIFs e stickers e guarda stickers', async () => {
    const up = await call('POST', `/conversations/${direct}/uploads`, { token: filipa.access_token, raw: jpeg });
    expect(up.status).toBe(200);
    expect(up.body.media_key).toMatch(new RegExp(`^${direct}/[0-9a-f-]+\\.jpg$`));
    expect((await call('POST', `/conversations/${direct}/uploads`, { token: hugo.access_token, raw: jpeg })).status).toBe(404);

    const image = await send(filipa, direct, { kind: 'image', media_key: up.body.media_key, body: 'Este?', width: 800, height: 600 });
    expect(image.body).toMatchObject({ kind: 'image', body: 'Este?', width: 800, height: 600 });
    const imageUrl = new URL(image.body.media_url);
    expect((await call('GET', imageUrl.pathname + imageUrl.search)).status).toBe(200);
    // A chave tem de ser desta conversa.
    expect((await send(filipa, direct, { kind: 'image', media_key: `${gil.user.id}/x.jpg` })).status).toBe(422);

    // GIFs só do GIPHY.
    expect((await send(gil, direct, { kind: 'gif', media_url: 'https://evil.example/a.gif' })).status).toBe(400);
    const gif = await send(gil, direct, { kind: 'gif', media_url: 'https://media1.giphy.com/media/abc/200w.gif', width: 200, height: 150 });
    expect(gif.body.media_url).toBe('https://media1.giphy.com/media/abc/200w.gif');

    // Guardar como sticker: a imagem é copiada (continua lá depois de a mensagem ser apagada).
    const saved = await call('POST', '/stickers', { token: gil.access_token, body: { message_id: image.body.id } });
    expect(saved.status).toBe(200);
    await call('POST', '/stickers', { token: gil.access_token, body: { message_id: gif.body.id } });
    // O mesmo GIF não fica duas vezes.
    await call('POST', '/stickers', { token: gil.access_token, body: { media_url: 'https://media1.giphy.com/media/abc/200w.gif' } });
    const fromGallery = await app.inject({
      method: 'POST',
      url: '/stickers/upload?width=512&height=512',
      headers: { authorization: `Bearer ${gil.access_token}`, 'content-type': 'image/gif' },
      payload: Buffer.from('GIF89a\x01\x00\x01\x00', 'binary'),
    });
    expect(fromGallery.statusCode).toBe(200);
    const stickers = (await call('GET', '/stickers', { token: gil.access_token })).body;
    expect(stickers).toHaveLength(3);
    expect((await call('GET', '/stickers', { token: filipa.access_token })).body).toEqual([]);

    expect((await call('DELETE', `/chat-messages/${image.body.id}`, { token: filipa.access_token })).status).toBe(204);
    expect((await call('GET', imageUrl.pathname + imageUrl.search)).status).toBe(404);
    const savedUrl = new URL(saved.body.url);
    expect((await call('GET', savedUrl.pathname + savedUrl.search)).status).toBe(200);

    const sticker = await send(gil, direct, { kind: 'sticker', sticker_id: saved.body.id });
    expect(sticker.body.kind).toBe('sticker');
    expect(new URL(sticker.body.media_url).pathname).toMatch(new RegExp(`^/files/${direct}/`));
    expect((await send(filipa, direct, { kind: 'sticker', sticker_id: saved.body.id })).status).toBe(404);

    expect((await call('DELETE', `/stickers/${saved.body.id}`, { token: gil.access_token })).status).toBe(204);
    expect((await call('GET', savedUrl.pathname + savedUrl.search)).status).toBe(404);
  });

  it('pesquisa GIFs no GIPHY através da API', async () => {
    const res = await call('GET', '/gifs?q=parab%C3%A9ns&type=stickers', { token: filipa.access_token });
    expect(res.body).toEqual({
      results: [{ id: 'abc', url: 'https://media1.giphy.com/media/abc/200w.gif', preview_url: 'https://media1.giphy.com/media/abc/100w.gif', width: 200, height: 150 }],
      next_offset: 2,
    });
    const url = new URL(giphyCalls.at(-1)!);
    expect(url.pathname).toBe('/v1/stickers/search');
    expect(url.searchParams.get('q')).toBe('parabéns');
    expect(url.searchParams.get('api_key')).toBe('giphy-test-key');
    await call('GET', '/gifs', { token: filipa.access_token });
    expect(new URL(giphyCalls.at(-1)!).pathname).toBe('/v1/gifs/trending');
    expect((await call('GET', '/gifs')).status).toBe(401);
    await expect(new GifsService(undefined).search('gifs', '', 0)).rejects.toMatchObject({ status: 503, code: 'gifs_unavailable' });
  });

  it('cada grupo tem a sua conversa, só para os membros', async () => {
    const groupId = uuid();
    await call('PUT', `/groups/${groupId}`, {
      token: filipa.access_token,
      body: {
        group: { title: 'Prenda da Rita', celebrant_name: 'Rita', target_amount: 60 },
        new_members: [{ id: uuid(), user_id: filipa.user.id, display_name: 'Filipa' }],
      },
    });
    const group = (await call('GET', '/groups', { token: filipa.access_token })).body.find((g: { id: string }) => g.id === groupId);
    const conversation: string = group.conversation_id;
    expect(conversation).toBeTruthy();

    expect((await send(hugo, conversation, { kind: 'text', body: 'olá' })).status).toBe(404);
    await call('POST', `/invite-codes/${group.invite_code}/join`, { token: hugo.access_token, body: {} });
    expect((await send(hugo, conversation, { kind: 'text', body: 'Entrei! 🎉' })).status).toBe(200);

    const conv = (await call('GET', '/conversations', { token: filipa.access_token })).body.find((c: { id: string }) => c.id === conversation);
    expect(conv).toMatchObject({ kind: 'group', group_id: groupId, title: 'Prenda da Rita', celebrant_name: 'Rita', unread_count: 1 });
    // Hugo não é amigo da Filipa, mas fala com ela no grupo.
    expect((await call('GET', `/conversations/${conversation}`, { token: hugo.access_token })).body.participants).toHaveLength(2);

    expect((await call('DELETE', `/groups/${groupId}`, { token: filipa.access_token })).status).toBe(204);
    expect((await call('GET', `/conversations/${conversation}/messages`, { token: hugo.access_token })).status).toBe(404);
  });

  it('avisa em tempo real por WebSocket', async () => {
    const ws = await app.injectWS('/ws');
    const events: { type: string; [k: string]: unknown }[] = [];
    const waiters: (() => void)[] = [];
    ws.on('message', (raw) => {
      events.push(JSON.parse(raw.toString()));
      waiters.splice(0).forEach((w) => w());
    });
    const next = async (type: string) => {
      for (let i = 0; i < 50; i++) {
        const found = events.find((e) => e.type === type);
        if (found) {
          events.splice(events.indexOf(found), 1);
          return found;
        }
        await new Promise<void>((r) => {
          waiters.push(r);
          setTimeout(r, 100);
        });
      }
      throw new Error(`sem evento ${type}`);
    };

    ws.send(JSON.stringify({ type: 'auth', token: gil.access_token }));
    await next('ready');

    await send(filipa, direct, { kind: 'text', body: 'Estás aí?' });
    expect((await next('message')).message).toMatchObject({ body: 'Estás aí?', conversation_id: direct });

    // "A escrever" da Filipa chega ao Gil (e só às conversas onde ela participa).
    const filipaWs = await app.injectWS('/ws');
    filipaWs.send(JSON.stringify({ type: 'auth', token: filipa.access_token }));
    await new Promise((r) => filipaWs.once('message', r));
    // O Gil (amigo) vê que a Filipa ficou online, também na lista de conversas.
    expect(await next('presence')).toMatchObject({ user_id: filipa.user.id, online: true });
    const withFilipa = (await call('GET', '/conversations', { token: gil.access_token })).body.find((c: { id: string }) => c.id === direct);
    expect(withFilipa.other_user).toMatchObject({ user_id: filipa.user.id, online: true });
    expect((await call('GET', '/friends', { token: gil.access_token })).body.friends.find((f: { user_id: string }) => f.user_id === filipa.user.id).online).toBe(true);

    filipaWs.send(JSON.stringify({ type: 'typing', conversation_id: direct }));
    expect(await next('typing')).toMatchObject({ conversation_id: direct, user_id: filipa.user.id, name: 'Filipa' });

    // "Vista por": a Filipa vê na lista quem já leu a última mensagem dela.
    const filipaEvents: { type: string; [k: string]: unknown }[] = [];
    filipaWs.on('message', (raw) => filipaEvents.push(JSON.parse(raw.toString())));
    await send(filipa, direct, { kind: 'text', body: 'Já viste?' });
    const conv = async () =>
      (await call('GET', '/conversations', { token: filipa.access_token })).body.find((c: { id: string }) => c.id === direct);
    expect((await conv()).seen_by).toEqual([]);
    await call('POST', `/conversations/${direct}/read`, { token: gil.access_token });
    expect((await conv()).seen_by).toEqual([{ user_id: gil.user.id, display_name: 'Gil' }]);
    await new Promise((r) => setTimeout(r, 50));
    expect(filipaEvents.find((e) => e.type === 'read')).toMatchObject({ user_id: gil.user.id, name: 'Gil', conversation_id: direct });

    await call('POST', '/friends/requests', { token: hugo.access_token, body: { user_id: gil.user.id } });
    await next('friends');

    // Deixar de ser amigos: a conversa fica para ler, mas já não se escreve.
    await call('DELETE', `/friends/${filipa.user.id}`, { token: gil.access_token });
    expect((await send(gil, direct, { kind: 'text', body: 'adeus' })).body.error).toBe('not_friends');
    expect((await call('GET', `/conversations/${direct}/messages`, { token: gil.access_token })).status).toBe(200);

    ws.terminate();
    filipaWs.terminate();
  });
});

describe('fotografia de perfil', () => {
  it('guarda, mostra aos amigos e nas conversas, substitui e remove', async () => {
    const ines = await signup('Inês', 'ines', 'ines@ex.pt');
    const joao = await signup('João', 'joao', 'joao@ex.pt');
    expect((await call('GET', '/me', { token: ines.access_token })).body.photo_url).toBeNull();

    const up = await call('PUT', '/me/photo', { token: ines.access_token, raw: jpeg });
    expect(up.status).toBe(200);
    const first = new URL(up.body.photo_url);
    expect(first.pathname).toMatch(new RegExp(`^/files/${ines.user.id}/avatar-\\d+\\.jpg$`));
    expect((await call('GET', first.pathname + first.search)).status).toBe(200);
    expect((await call('GET', '/me', { token: ines.access_token })).body.photo_url).toBe(up.body.photo_url);
    expect((await call('PUT', '/me/photo', { token: ines.access_token, raw: Buffer.from('não sou imagem') })).status).toBe(415);

    // Aparece a quem a procura, aos amigos e na conversa privada.
    expect((await call('POST', '/users/find', { token: joao.access_token, body: { identifier: '@ines' } })).body.user.photo_url).toBe(up.body.photo_url);
    await call('POST', '/friends/requests', { token: joao.access_token, body: { user_id: ines.user.id } });
    await call('POST', '/friends/requests', { token: ines.access_token, body: { user_id: joao.user.id } });
    expect((await call('GET', '/friends', { token: joao.access_token })).body.friends[0].photo_url).toBe(up.body.photo_url);
    const conv = await call('POST', '/conversations/direct', { token: joao.access_token, body: { user_id: ines.user.id } });
    expect(conv.body.other_user.photo_url).toBe(up.body.photo_url);
    const sent = await call('POST', `/conversations/${conv.body.id}/messages`, { token: ines.access_token, body: { id: uuid(), kind: 'text', body: 'Olá!' } });
    expect(sent.body.sender_photo_url).toBe(up.body.photo_url);
    // E aos outros membros de um grupo.
    const groupId = uuid();
    await call('PUT', `/groups/${groupId}`, {
      token: ines.access_token,
      body: { group: { title: 'Prenda', celebrant_name: 'Rui', target_amount: 20 }, new_members: [{ id: uuid(), user_id: ines.user.id, display_name: 'Inês' }] },
    });
    const group = (await call('GET', '/groups', { token: ines.access_token })).body.find((g: { id: string }) => g.id === groupId);
    expect(group.group_members[0].photo_url).toBe(up.body.photo_url);
    expect(group.group_members[0].photo_path).toBeUndefined();

    // Uma nova substitui (e apaga) a anterior.
    const png = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0, 0, 0, 0]);
    await new Promise((r) => setTimeout(r, 5));
    const second = await call('PUT', '/me/photo', { token: ines.access_token, raw: png });
    expect(second.body.photo_url).toMatch(/avatar-\d+\.png/);
    expect((await call('GET', first.pathname + first.search)).status).toBe(404);

    const removed = await call('DELETE', '/me/photo', { token: ines.access_token });
    expect(removed.body.photo_url).toBeNull();
    const secondUrl = new URL(second.body.photo_url);
    expect((await call('GET', secondUrl.pathname + secondUrl.search)).status).toBe(404);
  });
});

describe('definições das conversas', () => {
  it('privacidade: confirmações de leitura e presença (nos dois sentidos), silenciar e fixar', async () => {
    const lia = await signup('Lia', 'lia', 'lia@ex.pt');
    const max = await signup('Max', 'max', 'max@ex.pt');
    await call('POST', '/friends/requests', { token: lia.access_token, body: { user_id: max.user.id } });
    await call('POST', '/friends/requests', { token: max.access_token, body: { user_id: lia.user.id } });
    const conv = (await call('POST', '/conversations/direct', { token: lia.access_token, body: { user_id: max.user.id } })).body.id;
    await call('POST', `/conversations/${conv}/messages`, { token: lia.access_token, body: { id: uuid(), kind: 'text', body: 'Olá Max' } });
    await call('POST', `/conversations/${conv}/read`, { token: max.access_token });
    // O Max também fica com "visto por último".
    await call('PATCH', '/me', { token: max.access_token, body: {} });
    await db.query('update profiles set last_seen_at = now() where id = $1', [max.user.id]);

    const liaConv = async () =>
      (await call('GET', '/conversations', { token: lia.access_token })).body.find((c: { id: string }) => c.id === conv);
    const maxReadAt = async () =>
      (await call('GET', `/conversations/${conv}`, { token: lia.access_token })).body.participants.find(
        (p: { user_id: string }) => p.user_id === max.user.id,
      ).last_read_at;
    expect((await liaConv()).seen_by).toHaveLength(1);
    expect(await maxReadAt()).not.toBeNull();
    expect((await liaConv()).other_user.last_seen_at).not.toBeNull();

    // O Max desliga as confirmações de leitura: a Lia deixa de ver "vista".
    const off = await call('PATCH', '/me', { token: max.access_token, body: { read_receipts: false, show_presence: false } });
    expect(off.body).toMatchObject({ read_receipts: false, show_presence: false, typing_indicator: true });
    expect((await liaConv()).seen_by).toEqual([]);
    expect(await maxReadAt()).toBeNull();
    expect((await liaConv()).other_user).toMatchObject({ online: false, last_seen_at: null });
    // ...e ele também deixa de ver os da Lia (mas as suas não lidas continuam certas).
    await call('POST', `/conversations/${conv}/read`, { token: lia.access_token });
    const maxView = (await call('GET', `/conversations/${conv}`, { token: max.access_token })).body;
    expect(maxView.participants.find((p: { user_id: string }) => p.user_id === lia.user.id).last_read_at).toBeNull();
    expect(maxView.unread_count).toBe(0);

    // Silenciar e fixar são só para quem muda.
    expect((await liaConv())).toMatchObject({ muted_until: null, pinned: false });
    const prefs = await call('PATCH', `/conversations/${conv}/prefs`, {
      token: lia.access_token,
      body: { muted_until: '9999-12-31T00:00:00Z', pinned: true },
    });
    expect(prefs.status).toBe(200);
    expect(prefs.body.pinned).toBe(true);
    expect(new Date(prefs.body.muted_until).getUTCFullYear()).toBe(9999);
    expect((await call('GET', `/conversations/${conv}`, { token: max.access_token })).body).toMatchObject({ muted_until: null, pinned: false });
    // Fixada fica no topo da lista.
    expect((await call('GET', '/conversations', { token: lia.access_token })).body[0].id).toBe(conv);
    await call('PATCH', `/conversations/${conv}/prefs`, { token: lia.access_token, body: { muted_until: null } });
    expect((await liaConv())).toMatchObject({ muted_until: null, pinned: true });
    expect((await call('PATCH', `/conversations/${conv}/prefs`, { token: lia.access_token, body: { muted_until: 'amanhã' } })).status).toBe(400);
    const outsider = await signup('Noé', 'noe', 'noe@ex.pt');
    expect((await call('PATCH', `/conversations/${conv}/prefs`, { token: outsider.access_token, body: { pinned: true } })).status).toBe(404);
  });
});

describe('fotografia do grupo e métodos de pagamento', () => {
  it('só o administrador muda a fotografia; aparece aos membros e na conversa; regista cartão e Skrill', async () => {
    const ivo = await signup('Ivo', 'ivo', 'ivo@ex.pt');
    const zoe = await signup('Zoe', 'zoe', 'zoe@ex.pt');
    const groupId = uuid();
    await call('PUT', `/groups/${groupId}`, {
      token: ivo.access_token,
      body: { group: { title: 'Prenda do Tó', celebrant_name: 'Tó', target_amount: 40 }, new_members: [{ id: uuid(), user_id: ivo.user.id, display_name: 'Ivo' }] },
    });
    const code = (await call('GET', '/groups', { token: ivo.access_token })).body.find((g: { id: string }) => g.id === groupId).invite_code;
    await call('POST', `/invite-codes/${code}/join`, { token: zoe.access_token, body: {} });

    expect((await call('PUT', `/groups/${groupId}/photo`, { token: zoe.access_token, raw: jpeg })).status).toBe(404);
    const up = await call('PUT', `/groups/${groupId}/photo`, { token: ivo.access_token, raw: jpeg });
    expect(up.status).toBe(200);
    expect(up.body.photo_url).toMatch(new RegExp(`/files/${groupId}/photo-\\d+\\.jpg`));
    expect(up.body.photo_path).toBeUndefined();
    const url = new URL(up.body.photo_url);
    expect((await call('GET', url.pathname + url.search)).status).toBe(200);

    const zoeGroup = (await call('GET', '/groups', { token: zoe.access_token })).body.find((g: { id: string }) => g.id === groupId);
    expect(zoeGroup.photo_url).toBe(up.body.photo_url);
    const conv = (await call('GET', '/conversations', { token: zoe.access_token })).body.find((c: { group_id: string }) => c.group_id === groupId);
    expect(conv.photo_url).toBe(up.body.photo_url);

    // Pagar com cartão (pelo link do Revolut/PayPal de quem recebe) ou Skrill.
    const zoeMember = zoeGroup.group_members.find((m: { user_id: string }) => m.user_id === zoe.user.id);
    expect((await call('POST', `/group-members/${zoeMember.id}/paid`, { token: zoe.access_token, body: { method: 'card' } })).status).toBe(204);
    expect((await call('POST', `/group-members/${zoeMember.id}/paid`, { token: zoe.access_token, body: { method: 'skrill' } })).status).toBe(204);
    expect((await call('POST', `/group-members/${zoeMember.id}/paid`, { token: zoe.access_token, body: { method: 'bitcoin' } })).status).toBe(400);
    const after = (await call('GET', '/groups', { token: ivo.access_token })).body.find((g: { id: string }) => g.id === groupId);
    expect(after.group_members.find((m: { id: string }) => m.id === zoeMember.id).paid_method).toBe('skrill');

    expect((await call('DELETE', `/groups/${groupId}/photo`, { token: ivo.access_token })).body.photo_url).toBeNull();
    expect((await call('GET', url.pathname + url.search)).status).toBe(404);
  });
});

describe('pagamentos na app (Stripe)', () => {
  it('quem compra liga a conta; MB WAY com número guardado; cartão pelo Checkout; webhook confirma', async () => {
    const bia = await signup('Bia', 'bia', 'bia@ex.pt');
    const caio = await signup('Caio', 'caio', 'caio@ex.pt');
    const dani = await signup('Dani', 'dani', 'dani@ex.pt');
    const groupId = uuid();
    await call('PUT', `/groups/${groupId}`, {
      token: bia.access_token,
      body: { group: { title: 'Prenda da Rosa', celebrant_name: 'Rosa', target_amount: 40 }, new_members: [{ id: uuid(), user_id: bia.user.id, display_name: 'Bia' }] },
    });
    const code = (await call('GET', '/groups', { token: bia.access_token })).body.find((g: { id: string }) => g.id === groupId).invite_code;
    await call('POST', `/invite-codes/${code}/join`, { token: caio.access_token, body: {} });
    await call('POST', `/invite-codes/${code}/join`, { token: dani.access_token, body: {} });
    const group = async (s: Session) => (await call('GET', '/groups', { token: s.access_token })).body.find((g: { id: string }) => g.id === groupId);
    const memberOf = async (s: Session) => (await group(s)).group_members.find((m: { user_id: string }) => m.user_id === s.user.id);
    const caioMember = await memberOf(caio);
    const daniMember = await memberOf(dani);
    const checkout = (s: Session, memberId: string, body: object) =>
      call('POST', `/group-members/${memberId}/checkout`, { token: s.access_token, body });

    // A Bia (quem compra) ainda não ligou a conta Stripe.
    expect((await call('GET', `/groups/${groupId}/payee`, { token: caio.access_token })).body.in_app).toBeUndefined();
    expect((await checkout(caio, caioMember.id, { method: 'card' })).body.error).toBe('payee_not_ready');
    expect(await (await call('GET', '/me/payouts', { token: bia.access_token })).body).toMatchObject({ enabled: true, connected: false, ready: false });

    const onboarding = await call('POST', '/me/payouts/onboarding', { token: bia.access_token });
    expect(onboarding.body.url).toMatch(/^https:\/\/connect\.stripe\.test\/setup\/acct_/);
    expect(stripeCalls.find((c) => c.op === 'onboardingLink')!.args).toMatchObject({ returnUrl: 'http://api.test/stripe/return' });
    expect((await call('POST', '/me/payouts/refresh', { token: bia.access_token })).body).toMatchObject({ connected: true, ready: true });
    const payee = (await call('GET', `/groups/${groupId}/payee`, { token: caio.access_token })).body;
    expect(payee).toMatchObject({ in_app: true, in_app_fees: { card: { percent: 1.5, fixed: 0.25 } } });

    // Quem compra não paga a si próprio; um membro só paga a sua parte.
    const biaMember = await memberOf(bia);
    expect((await checkout(bia, biaMember.id, { method: 'card' })).body.error).toBe('is_buyer');
    expect((await checkout(dani, caioMember.id, { method: 'card' })).status).toBe(404);

    // MB WAY: sem número guardado tem de o indicar; pode guardá-lo para a próxima.
    expect((await checkout(caio, caioMember.id, { method: 'mb_way' })).body.error).toBe('invalid_phone');
    const mbway = await checkout(caio, caioMember.id, { method: 'mb_way', phone: '912 345 678', save_phone: true });
    expect(mbway.status).toBe(200);
    // 40 € a três: a Bia 13,34 €, o Caio e a Dani 13,33 €. A comissão vai por cima.
    expect(mbway.body).toMatchObject({ method: 'mb_way', status: 'pending', amount: 13.33, fee: 0.46, total: 13.79, checkout_url: null });
    expect(stripeCalls.at(-1)!.args).toMatchObject({ amountCents: 1379, transferCents: 1333, phone: '+351912345678', destination: expect.stringMatching(/^acct_/) });
    expect((await call('GET', '/me', { token: caio.access_token })).body.mbway_pay_phone).toBe('+351912345678');
    expect((await call('GET', `/payments/${mbway.body.id}`, { token: dani.access_token })).status).toBe(404);

    // O Caio aprova na app MB WAY: a parte fica paga e confirmada.
    intentStatus.set([...intentStatus.keys()].at(-1)!, 'succeeded');
    expect((await call('GET', `/payments/${mbway.body.id}`, { token: caio.access_token })).body.status).toBe('succeeded');
    expect(await memberOf(caio)).toMatchObject({ paid_method: 'mbway', confirmed_at: expect.any(String) });
    expect((await checkout(caio, caioMember.id, { method: 'card' })).body.error).toBe('already_paid');

    // Cartão: página da Stripe; o webhook confirma.
    const card = await checkout(dani, daniMember.id, { method: 'card', locale: 'pt' });
    expect(card.body).toMatchObject({ status: 'pending', checkout_url: 'https://checkout.stripe.test/card' });
    expect(stripeCalls.at(-1)!.args).toMatchObject({ method: 'card', locale: 'pt', successUrl: 'http://api.test/pay/done', email: 'dani@ex.pt' });
    const event = JSON.stringify({ type: 'checkout.session.completed', data: { object: { id: 'cs_x', payment_status: 'paid', metadata: { payment_id: card.body.id } } } });
    const webhook = (signature: string) =>
      app.inject({ method: 'POST', url: '/stripe/webhook', headers: { 'content-type': 'application/json', 'stripe-signature': signature }, payload: event });
    expect((await webhook('falsa')).statusCode).toBe(400);
    expect(await memberOf(dani)).toMatchObject({ confirmed_at: null });
    expect((await webhook('assinatura-valida')).statusCode).toBe(200);
    expect(await memberOf(dani)).toMatchObject({ paid_method: 'card', confirmed_at: expect.any(String) });
    expect((await call('GET', `/payments/${card.body.id}`, { token: dani.access_token })).body.status).toBe('succeeded');

    // Páginas para voltar à app.
    const done = await call('GET', '/pay/done');
    expect(done.raw.body).toContain('Pagamento concluído');
    expect(done.raw.body).toContain('com.eupasoft.velas://app/payments');
  });

  it('transferência (IBAN na Stripe): paga ao autorizar, confirmada quando chega, por pagar se falhar', async () => {
    const eli = await signup('Eli', 'eli', 'eli@ex.pt');
    const fil = await signup('Fil', 'fil', 'fil@ex.pt');
    const gui = await signup('Gui', 'gui', 'gui@ex.pt');
    const groupId = uuid();
    await call('PUT', `/groups/${groupId}`, {
      token: eli.access_token,
      body: { group: { title: 'Prenda do Zé', celebrant_name: 'Zé', target_amount: 30 }, new_members: [{ id: uuid(), user_id: eli.user.id, display_name: 'Eli' }] },
    });
    const code = (await call('GET', '/groups', { token: eli.access_token })).body.find((g: { id: string }) => g.id === groupId).invite_code;
    for (const s of [fil, gui]) await call('POST', `/invite-codes/${code}/join`, { token: s.access_token, body: {} });
    await call('POST', '/me/payouts/onboarding', { token: eli.access_token });
    await call('POST', '/me/payouts/refresh', { token: eli.access_token });
    const memberOf = async (s: Session) =>
      (await call('GET', '/groups', { token: s.access_token })).body
        .find((g: { id: string }) => g.id === groupId)
        .group_members.find((m: { user_id: string }) => m.user_id === s.user.id);
    const webhook = (type: string, object: object) =>
      app.inject({
        method: 'POST',
        url: '/stripe/webhook',
        headers: { 'content-type': 'application/json', 'stripe-signature': 'assinatura-valida' },
        payload: JSON.stringify({ type, data: { object: { id: 'cs_y', ...object } } }),
      });

    for (const [payer, outcome] of [[fil, 'checkout.session.async_payment_succeeded'], [gui, 'checkout.session.async_payment_failed']] as const) {
      const member = await memberOf(payer);
      const pay = await call('POST', `/group-members/${member.id}/checkout`, { token: payer.access_token, body: { method: 'sepa_debit' } });
      // 30 € a três = 10 €; a transferência só tem a parte fixa (0,35 €).
      expect(pay.body).toMatchObject({ method: 'sepa_debit', amount: 10, fee: 0.35, total: 10.35 });
      expect(stripeCalls.at(-1)!.args).toMatchObject({ method: 'sepa_debit', amountCents: 1035, transferCents: 1000 });

      await webhook('checkout.session.completed', { payment_status: 'unpaid', metadata: { payment_id: pay.body.id } });
      expect((await call('GET', `/payments/${pay.body.id}`, { token: payer.access_token })).body.status).toBe('processing');
      expect(await memberOf(payer)).toMatchObject({ paid_method: 'transfer', paid_at: expect.any(String), confirmed_at: null });

      await webhook(outcome, { metadata: { payment_id: pay.body.id } });
      if (outcome.endsWith('succeeded')) {
        expect(await memberOf(payer)).toMatchObject({ paid_method: 'transfer', confirmed_at: expect.any(String) });
      } else {
        expect(await memberOf(payer)).toMatchObject({ paid_at: null, paid_method: null, confirmed_at: null });
        expect((await call('GET', `/payments/${pay.body.id}`, { token: payer.access_token })).body.status).toBe('failed');
      }
    }

    // Revolut Pay também vai pelo Checkout.
    const fil2 = await call('POST', `/group-members/${(await memberOf(gui)).id}/checkout`, { token: gui.access_token, body: { method: 'revolut_pay' } });
    expect(fil2.body).toMatchObject({ method: 'revolut_pay', checkout_url: 'https://checkout.stripe.test/revolut_pay' });
  });
});

describe('sistema', () => {
  it('o /health mostra a versão da base de dados e se as imagens podem ser gravadas', async () => {
    const res = await call('GET', '/health');
    expect(res.body).toEqual({ ok: true, schema: expect.stringMatching(/^\d{3}_.+\.sql$/), storage: true });
  });

  it('sem pasta gravável, falha com um erro claro (e não um erro interno)', async () => {
    const broken = new PhotoStorage('/dev/null/uploads', 'http://api.test', secret);
    expect(await broken.writable()).toBe(false);
    await expect(broken.put(`${uuid()}/x.jpg`, jpeg)).rejects.toMatchObject({ status: 503, code: 'storage_unavailable' });
  });
});

describe('documentação', () => {
  it('serve o Swagger UI e a especificação OpenAPI gerada a partir dos schemas', async () => {
    expect((await app.inject({ method: 'GET', url: '/docs/' })).statusCode).toBe(200);
    const spec = (await call('GET', '/docs/json')).body;
    expect(spec.openapi).toBe('3.0.3');

    const login = spec.paths['/auth/login'].post;
    expect(login.security).toBeUndefined();
    expect(login.requestBody.content['application/json'].schema.required).toEqual(['identifier', 'password']);

    const person = spec.paths['/people/{id}'].put;
    expect(person.security).toEqual([{ bearerAuth: [] }]);
    expect(person.parameters).toContainEqual(expect.objectContaining({ in: 'path', name: 'id', required: true }));
    expect(person.requestBody.content['application/json'].schema.properties.id).toBeUndefined();
  });
});
