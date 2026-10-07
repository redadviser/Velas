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
import { createTestDb } from './pglite-pool.js';

const secret = 'test-secret-with-at-least-32-characters!!';
const sent: Mail[] = [];
const googleTokens = new Map<string, GoogleIdentity>();

let db: Db;
let closeDb: () => Promise<void>;
let app: FastifyInstance;
let uploadDir: string;

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
    androidPackage: 'com.eupasoft.aniversarios',
    playStoreUrl: 'https://play.google.com/store/apps/details?id=com.eupasoft.aniversarios',
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
    const code = (await call('GET', '/groups', { token: admin.access_token })).body[0].invite_code;

    // Página pública do link partilhado.
    const page = await call('GET', `/g/${code.toLowerCase()}`);
    expect(page.status).toBe(200);
    expect(page.raw.body).toContain(`com.eupasoft.velas://app/join/${code}`);
    expect(page.raw.body).toContain(`intent://app/join/${code}#Intent;scheme=com.eupasoft.velas;package=com.eupasoft.aniversarios;S.browser_fallback_url=https%3A%2F%2Fplay.google.com`);
    expect(page.raw.body).toContain('Descarregar para Android');
    expect(page.raw.body).not.toContain('Descarregar para iPhone');
    expect(page.raw.body).not.toContain('Prenda da Mãe'); // não revela o grupo
    expect((await call('GET', '/g/%3Cscript%3E')).status).toBe(404);

    const preview = await call('GET', `/invite-codes/${code.toLowerCase()}`, { token: other.access_token });
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
