import {
  createHmac,
  randomBytes,
  scrypt as nodeScrypt,
  timingSafeEqual,
} from 'node:crypto';

export const TEAM_SESSION_COOKIE = '__Host-urc-team-session';
export const MAX_PASSWORD_BYTES = 256;

const SCRYPT_N = 131_072;
const SCRYPT_R = 8;
const SCRYPT_P = 1;
const SCRYPT_KEY_LENGTH = 32;
const SCRYPT_MAX_MEMORY = 256 * 1024 * 1024;
const HASH_PREFIX = `urc$scrypt$v1$${SCRYPT_N}$${SCRYPT_R}$${SCRYPT_P}`;
const MAX_TOKEN_LENGTH = 1024;
const MAX_SESSION_SECONDS = 86_400;

export type TeamPasswordEntry = {
  hash: string;
  sessionVersion: number;
};

export type TeamPasswordConfig = Record<string, TeamPasswordEntry>;

type TeamSessionPayload = {
  team: string;
  sessionVersion: number;
  iat: number;
  exp: number;
};

function isAcceptablePassword(password: string): boolean {
  return password.length > 0 && Buffer.byteLength(password, 'utf8') <= MAX_PASSWORD_BYTES;
}

function encodeBase64Url(value: Buffer | string): string {
  return Buffer.from(value).toString('base64url');
}

function decodeBase64Url(value: string): Buffer | undefined {
  if (!/^[A-Za-z0-9_-]+$/.test(value)) return undefined;
  const decoded = Buffer.from(value, 'base64url');
  return encodeBase64Url(decoded) === value ? decoded : undefined;
}

function scrypt(password: string, salt: Buffer): Promise<Buffer> {
  return new Promise((resolve, reject) => {
    nodeScrypt(
      password,
      salt,
      SCRYPT_KEY_LENGTH,
      { N: SCRYPT_N, r: SCRYPT_R, p: SCRYPT_P, maxmem: SCRYPT_MAX_MEMORY },
      (error, derivedKey) => (error ? reject(error) : resolve(derivedKey as Buffer))
    );
  });
}

function parsePasswordHash(encoded: string): { salt: Buffer; derivedKey: Buffer } | undefined {
  const parts = encoded.split('$');
  if (parts.length !== 8 || parts.slice(0, 6).join('$') !== HASH_PREFIX) return undefined;

  const salt = decodeBase64Url(parts[6]);
  const derivedKey = decodeBase64Url(parts[7]);
  if (!salt || salt.length !== 16 || !derivedKey || derivedKey.length !== SCRYPT_KEY_LENGTH) {
    return undefined;
  }
  return { salt, derivedKey };
}

export async function hashTeamPassword(
  password: string,
  salt = randomBytes(16)
): Promise<string> {
  if (!isAcceptablePassword(password)) throw new Error('password must be 1-256 UTF-8 bytes');
  if (salt.length !== 16) throw new Error('salt must be 16 bytes');
  const derivedKey = await scrypt(password, salt);
  return `${HASH_PREFIX}$${encodeBase64Url(salt)}$${encodeBase64Url(derivedKey)}`;
}

export async function verifyTeamPassword(password: string, encoded: string): Promise<boolean> {
  if (!isAcceptablePassword(password)) return false;
  const parsed = parsePasswordHash(encoded);
  if (!parsed) return false;
  const candidate = await scrypt(password, parsed.salt);
  return timingSafeEqual(candidate, parsed.derivedKey);
}

export function parseSigningKey(encoded: string | undefined): Buffer | undefined {
  if (!encoded) return undefined;
  const key = decodeBase64Url(encoded);
  return key?.length === 32 ? key : undefined;
}

export function parseTeamPasswordConfig(raw: string | undefined): TeamPasswordConfig | undefined {
  if (!raw) return undefined;
  let value: unknown;
  try {
    value = JSON.parse(raw);
  } catch {
    return undefined;
  }
  if (!value || typeof value !== 'object' || Array.isArray(value)) return undefined;

  const config: TeamPasswordConfig = {};
  for (const [team, entry] of Object.entries(value)) {
    if (!/^[a-z0-9-]+$/.test(team) || !entry || typeof entry !== 'object' || Array.isArray(entry)) {
      return undefined;
    }
    const keys = Object.keys(entry).sort();
    if (keys.length !== 2 || keys[0] !== 'hash' || keys[1] !== 'sessionVersion') return undefined;
    const { hash, sessionVersion } = entry as Record<string, unknown>;
    if (
      typeof hash !== 'string' ||
      !parsePasswordHash(hash) ||
      !Number.isSafeInteger(sessionVersion) ||
      (sessionVersion as number) < 1
    ) {
      return undefined;
    }
    config[team] = { hash, sessionVersion: sessionVersion as number };
  }
  return config;
}

export function parseSessionTtl(raw: string | undefined): number | undefined {
  if (!raw || !/^\d+$/.test(raw)) return undefined;
  const ttl = Number(raw);
  return Number.isSafeInteger(ttl) && ttl >= 300 && ttl <= MAX_SESSION_SECONDS ? ttl : undefined;
}

function sessionSignature(payload: string, signingKey: Buffer): Buffer {
  return createHmac('sha256', signingKey).update(payload).digest();
}

export function createTeamSession(
  team: string,
  sessionVersion: number,
  signingKey: Buffer,
  ttlSeconds: number,
  nowSeconds = Math.floor(Date.now() / 1000)
): string {
  if (!/^[a-z0-9-]+$/.test(team)) throw new Error('invalid team id');
  if (!Number.isSafeInteger(sessionVersion) || sessionVersion < 1) {
    throw new Error('invalid session version');
  }
  if (signingKey.length !== 32) throw new Error('signing key must be 32 bytes');
  if (!Number.isSafeInteger(ttlSeconds) || ttlSeconds < 300 || ttlSeconds > MAX_SESSION_SECONDS) {
    throw new Error('invalid session TTL');
  }
  const payload: TeamSessionPayload = {
    team,
    sessionVersion,
    iat: nowSeconds,
    exp: nowSeconds + ttlSeconds,
  };
  const encodedPayload = encodeBase64Url(JSON.stringify(payload));
  return `${encodedPayload}.${encodeBase64Url(sessionSignature(encodedPayload, signingKey))}`;
}

export function verifyTeamSession(
  token: string | undefined,
  expectedTeam: string,
  expectedSessionVersion: number,
  signingKey: Buffer,
  nowSeconds = Math.floor(Date.now() / 1000)
): boolean {
  if (!token || token.length > MAX_TOKEN_LENGTH || signingKey.length !== 32) return false;
  const parts = token.split('.');
  if (parts.length !== 2) return false;
  const payloadBuffer = decodeBase64Url(parts[0]);
  const suppliedSignature = decodeBase64Url(parts[1]);
  if (!payloadBuffer || !suppliedSignature || suppliedSignature.length !== 32) return false;

  const expectedSignature = sessionSignature(parts[0], signingKey);
  if (!timingSafeEqual(suppliedSignature, expectedSignature)) return false;

  let payload: unknown;
  try {
    payload = JSON.parse(payloadBuffer.toString('utf8'));
  } catch {
    return false;
  }
  if (!payload || typeof payload !== 'object' || Array.isArray(payload)) return false;
  const keys = Object.keys(payload).sort();
  if (keys.join(',') !== 'exp,iat,sessionVersion,team') return false;
  const { team, sessionVersion, iat, exp } = payload as Record<string, unknown>;
  return (
    team === expectedTeam &&
    sessionVersion === expectedSessionVersion &&
    Number.isSafeInteger(iat) &&
    Number.isSafeInteger(exp) &&
    (iat as number) <= nowSeconds &&
    (exp as number) > nowSeconds &&
    (exp as number) > (iat as number) &&
    (exp as number) - (iat as number) <= MAX_SESSION_SECONDS
  );
}

export function isSameOrigin(requestUrl: string, origin: string | null): boolean {
  if (!origin) return false;
  try {
    return new URL(origin).origin === new URL(requestUrl).origin;
  } catch {
    return false;
  }
}
