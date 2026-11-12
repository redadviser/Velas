import { describe, expect, it } from 'vitest';

import { pushCopy, pushLangs } from '../src/modules/push/push.copy.js';

describe('textos das notificações push', () => {
  it('existem nas 16 línguas da app e preenchem os nomes', () => {
    expect(pushLangs).toHaveLength(16);
    for (const lang of pushLangs) {
      const c = pushCopy(lang);
      expect(c.newMessage.length, lang).toBeGreaterThan(0);
      expect(c.scheduledSent('Ana'), lang).toContain('Ana');
      expect(c.scheduledSent('Ana'), lang).not.toContain('{');
      expect(c.inGroup('Ana', 'olá'), lang).toContain('olá');
    }
  });

  it('uma língua desconhecida recebe português', () => {
    expect(pushCopy('xx').newMessage).toBe('Nova mensagem');
    expect(pushCopy('de').newMessage).not.toBe('Nova mensagem');
  });
});
