/**
 * Conta tentativas por chave (conta, email) numa janela de tempo. Os limites
 * por IP não chegam: um atacante com muitos IPs ataca a mesma conta ou enche a
 * caixa de email de alguém.
 *
 * shortcut: em memória, por processo. Com mais de uma instância da API, cada
 * uma conta à parte; passar para a base de dados (ou Redis) nessa altura.
 */
export class AttemptLimiter {
  private readonly hits = new Map<string, { count: number; resetAt: number }>();

  constructor(
    private readonly max: number,
    private readonly windowMs: number,
  ) {}

  /** Regista uma tentativa; false se a chave já passou o limite. */
  hit(key: string, now = Date.now()): boolean {
    if (this.hits.size > 10_000) {
      for (const [k, v] of this.hits) if (v.resetAt <= now) this.hits.delete(k);
    }
    const entry = this.hits.get(key);
    if (!entry || entry.resetAt <= now) {
      this.hits.set(key, { count: 1, resetAt: now + this.windowMs });
      return true;
    }
    entry.count++;
    return entry.count <= this.max;
  }

  blocked(key: string, now = Date.now()): boolean {
    const entry = this.hits.get(key);
    return !!entry && entry.resetAt > now && entry.count >= this.max;
  }

  clear(key: string): void {
    this.hits.delete(key);
  }
}

/** Tentativas falhadas de palavra-passe por conta: 10 em 15 minutos. */
export const loginFailures = new AttemptLimiter(10, 15 * 60_000);

/** Emails de recuperação e de eliminação para o mesmo endereço: 3 por hora. */
export const emailQuota = new AttemptLimiter(3, 60 * 60_000);
