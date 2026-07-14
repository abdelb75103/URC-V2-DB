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
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Alert, AlertDescription, AlertTitle } from '@/components/ui/alert';
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

  const onSubmit = async (e: React.FormEvent<HTMLFormElement>) => {
    e.preventDefault();
    if (!team) {
      setNotice('Unable to unlock this dashboard.');
      return;
    }
    const form = new FormData(e.currentTarget);
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
      <form onSubmit={onSubmit}>
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
            <Alert>
              <AlertCircle className="h-4 w-4" />
              <AlertTitle>Access not granted</AlertTitle>
              <AlertDescription>{notice}</AlertDescription>
            </Alert>
          )}
          <div className="space-y-2">
            <Label htmlFor="password">Password</Label>
            <div className="relative">
              <Input
                id="password"
                name="password"
                type={showPassword ? 'text' : 'password'}
                required
                autoFocus
                maxLength={256}
                autoComplete="current-password"
                className="pr-10"
              />
              <Button
                type="button"
                variant="ghost"
                size="icon"
                className="absolute right-0 top-0 h-full px-3 text-muted-foreground hover:text-foreground"
                onClick={() => setShowPassword((s) => !s)}
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
