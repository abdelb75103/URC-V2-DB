'use client';

import { useState } from 'react';
import Image from 'next/image';
import { useSearchParams } from 'next/navigation';
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
import { getUnionById } from '@/config/unions';
import { StaticImages } from '@/lib/placeholder-images';

export function UnlockForm() {
  const [showPassword, setShowPassword] = useState(false);
  const [notice, setNotice] = useState<string | null>(null);
  const searchParams = useSearchParams();

  const teamId = searchParams.get('teamId');
  const unionId = searchParams.get('unionId');
  const team = teamId ? getTeamById(teamId) : null;
  const union = unionId ? getUnionById(unionId) : null;

  const contextTitle = team
    ? `${team.name} Dashboard`
    : union
      ? `${union.governingBody} Dashboard`
      : 'Access Restricted';

  const imageUrl = team?.crest ?? union?.crest ?? StaticImages.urcLogo;

  const onSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    // Real password verification (slow hash + signed, expiring HttpOnly cookie)
    // is handled server-side at deployment and is intentionally not part of the
    // static front-end build. See AGENTS.md — Web and Deployment Contracts.
    setNotice(
      'Password access is provisioned per team at deployment. This preview build does not verify credentials.'
    );
  };

  return (
    <Card className="w-full max-w-sm">
      <form onSubmit={onSubmit}>
        <CardHeader className="text-center">
          {team || union ? (
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
              <AlertTitle>Preview build</AlertTitle>
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
          <Button type="submit" className="w-full">
            Unlock
          </Button>
        </CardFooter>
      </form>
    </Card>
  );
}
