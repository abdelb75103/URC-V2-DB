'use client';

import { useState } from 'react';
import Image from 'next/image';
import { useRouter, useSearchParams } from 'next/navigation';
import { AlertCircle, Eye, EyeOff, LockKeyhole } from 'lucide-react';
import { Button } from '@/components/ui/button';
import {
  Card,
  CardContent,
  CardDescription,
  CardFooter,
  CardHeader,
  CardTitle,
} from '@/components/ui/card';
import { getTeamById } from '@/config/teams';
import { StaticImages } from '@/lib/placeholder-images';

export function UnlockForm() {
  const [showPassword, setShowPassword] = useState(false);
  const [notice, setNotice] = useState<string | null>(null);
  const [submitting, setSubmitting] = useState(false);
  const router = useRouter();
  const searchParams = useSearchParams();

  const teamId = searchParams.get('teamId');
  const team = teamId ? getTeamById(teamId) : null;
  const contextTitle = team ? `${team.name} Dashboard` : 'Access Restricted';
  const imageUrl = team?.crest ?? StaticImages.urcLogo;

  const onSubmit = async (event: React.FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    if (!team) {
      setNotice('Unable to unlock this dashboard.');
      return;
    }
    const form = new FormData(event.currentTarget);
    setSubmitting(true);
    setNotice(null);
    try {
      const response = await fetch('/api/team-session/unlock', {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({ teamId: team.id, password: form.get('password') }),
      });
      if (!response.ok) throw new Error('unlock failed');
      router.replace(`/team/${team.id}`);
      router.refresh();
    } catch {
      setNotice('Unable to unlock this dashboard. Check the password and try again.');
      setSubmitting(false);
    }
  };

  return (
    <Card className="w-full max-w-sm">
      <form action="/api/team-session/unlock" method="post" onSubmit={onSubmit}>
        <CardHeader className="text-center">
          {team ? (
            <div className="mx-auto mb-4">
              <Image
                src={imageUrl}
                alt={`${contextTitle} crest`}
                width={80}
                height={80}
                className="object-contain"
              />
            </div>
          ) : (
            <div className="mx-auto mb-4 w-fit rounded-full bg-primary p-3 text-primary-foreground">
              <LockKeyhole className="h-8 w-8" />
            </div>
          )}
          <CardTitle>{contextTitle}</CardTitle>
          <CardDescription>Enter the password to view this content.</CardDescription>
        </CardHeader>
        <CardContent className="space-y-4">
          {notice && (
            <div role="alert" className="relative rounded-lg border p-4 pl-11 text-sm">
              <AlertCircle className="absolute left-4 top-4 h-4 w-4" />
              <p className="font-medium">Access Not Granted</p>
              <p className="mt-1 text-muted-foreground">{notice}</p>
            </div>
          )}
          <div className="space-y-2">
            <label htmlFor="password" className="text-sm font-medium leading-none">
              Password
            </label>
            <div className="relative">
              <input
                id="password"
                name="password"
                type={showPassword ? 'text' : 'password'}
                required
                autoFocus
                maxLength={256}
                autoComplete="current-password"
                className="flex h-11 w-full rounded-md border border-input bg-background px-3 py-2 pr-11 text-base ring-offset-background focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2 disabled:opacity-50 md:text-sm"
              />
              <Button
                type="button"
                variant="ghost"
                size="icon"
                className="absolute right-0 top-0 h-full w-11 px-3 text-muted-foreground hover:text-foreground"
                onClick={() => setShowPassword((visible) => !visible)}
                aria-label={showPassword ? 'Hide password' : 'Show password'}
              >
                {showPassword ? <EyeOff className="h-4 w-4" /> : <Eye className="h-4 w-4" />}
              </Button>
            </div>
          </div>
        </CardContent>
        <CardFooter>
          <Button type="submit" className="h-11 w-full" disabled={submitting || !team}>
            {submitting ? 'Unlocking…' : 'Unlock'}
          </Button>
        </CardFooter>
      </form>
    </Card>
  );
}
