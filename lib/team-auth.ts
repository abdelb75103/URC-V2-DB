import 'server-only';

import {
  parseSessionTtl,
  parseSigningKey,
  parseTeamPasswordConfig,
  verifyTeamSession,
  type TeamPasswordConfig,
} from '@/lib/team-session';

export type TeamAuthSettings = {
  passwords: TeamPasswordConfig;
  signingKey: Buffer;
  ttlSeconds: number;
};

export function getTeamAuthSettings(): TeamAuthSettings | undefined {
  const passwords = parseTeamPasswordConfig(process.env.TEAM_PASSWORD_HASHES_JSON);
  const signingKey = parseSigningKey(process.env.TEAM_SESSION_SIGNING_KEY);
  const ttlSeconds = parseSessionTtl(process.env.TEAM_SESSION_TTL_SECONDS);
  return passwords && signingKey && ttlSeconds
    ? { passwords, signingKey, ttlSeconds }
    : undefined;
}
export function isTeamSessionAuthorized(
  teamId: string,
  token: string | undefined,
  settings = getTeamAuthSettings()
): boolean {
  const entry = settings?.passwords[teamId];
  return Boolean(
    settings &&
      entry &&
      verifyTeamSession(token, teamId, entry.sessionVersion, settings.signingKey)
  );
}
