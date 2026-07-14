import { NextRequest, NextResponse } from 'next/server';

import { getTeamById } from '@/config/teams';
import { getTeamAuthSettings } from '@/lib/team-auth';
import {
  MAX_PASSWORD_BYTES,
  TEAM_SESSION_COOKIE,
  createTeamSession,
  isSameOrigin,
  verifyTeamPassword,
} from '@/lib/team-session';

const GENERIC_FAILURE = { error: 'Unable to unlock this dashboard.' };

export const runtime = 'nodejs';

export async function POST(request: NextRequest) {
  if (!isSameOrigin(request.url, request.headers.get('origin'))) {
    return NextResponse.json(GENERIC_FAILURE, { status: 403 });
  }
  if (process.env.TEAM_UNLOCK_RATE_LIMIT_ENFORCED !== 'true') {
    return NextResponse.json(GENERIC_FAILURE, { status: 503 });
  }

  const settings = getTeamAuthSettings();
  if (!settings) return NextResponse.json(GENERIC_FAILURE, { status: 503 });

  let body: unknown;
  try {
    body = await request.json();
  } catch {
    return NextResponse.json(GENERIC_FAILURE, { status: 400 });
  }
  if (!body || typeof body !== 'object' || Array.isArray(body)) {
    return NextResponse.json(GENERIC_FAILURE, { status: 400 });
  }
  const keys = Object.keys(body).sort();
  const { teamId, password } = body as Record<string, unknown>;
  if (
    keys.join(',') !== 'password,teamId' ||
    typeof teamId !== 'string' ||
    typeof password !== 'string' ||
    Buffer.byteLength(password, 'utf8') > MAX_PASSWORD_BYTES
  ) {
    return NextResponse.json(GENERIC_FAILURE, { status: 400 });
  }

  const team = getTeamById(teamId);
  const entry = settings.passwords[teamId];
  if (!team || team.status !== 'live' || !entry || !(await verifyTeamPassword(password, entry.hash))) {
    return NextResponse.json(GENERIC_FAILURE, { status: 401 });
  }

  const token = createTeamSession(
    team.id,
    entry.sessionVersion,
    settings.signingKey,
    settings.ttlSeconds
  );
  const response = NextResponse.json({ ok: true });
  response.cookies.set(TEAM_SESSION_COOKIE, token, {
    httpOnly: true,
    secure: true,
    sameSite: 'lax',
    path: '/',
    maxAge: settings.ttlSeconds,
  });
  return response;
}
