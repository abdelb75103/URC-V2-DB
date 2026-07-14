import { NextRequest, NextResponse } from 'next/server';

import { TEAM_SESSION_COOKIE, isSameOrigin } from '@/lib/team-session';

export async function POST(request: NextRequest) {
  if (!isSameOrigin(request.url, request.headers.get('origin'))) {
    return NextResponse.json({ error: 'Unable to sign out.' }, { status: 403 });
  }
  const response = NextResponse.redirect(new URL('/', request.url), 303);
  response.cookies.set(TEAM_SESSION_COOKIE, '', {
    httpOnly: true,
    secure: true,
    sameSite: 'lax',
    path: '/',
    maxAge: 0,
  });
  return response;
}
