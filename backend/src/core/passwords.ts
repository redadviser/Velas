import bcrypt from 'bcryptjs';

const rounds = 12;
// Comparado quando a conta não existe, para a resposta demorar o mesmo.
const dummyHash = bcrypt.hashSync('velas-dummy-password', rounds);

export const hashPassword = (password: string) => bcrypt.hash(password, rounds);

/** Compara sempre (mesmo sem hash), para não revelar pelo tempo se a conta existe. */
export const verifyPassword = (password: string, hash: string | null | undefined) =>
  bcrypt.compare(password, hash ?? dummyHash);
