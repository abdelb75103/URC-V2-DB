import Link from 'next/link';
import Image from 'next/image';
import { Lock, ArrowLeft } from 'lucide-react';
import { Card, CardContent } from '@/components/ui/card';

interface LockedShellProps {
  title: string;
  subtitle?: string;
  crest?: string;
  accent?: string;
  /** Short reason shown to the visitor. */
  reason?: string;
}

export function LockedShell({
  title,
  subtitle,
  crest,
  accent = '#02D5F0',
  reason = 'This dashboard unlocks once a governance-approved, disclosure-controlled aggregate has been released for publication.',
}: LockedShellProps) {
  return (
    <div className="mx-auto w-full max-w-4xl px-4 pb-16 pt-8 sm:px-6">
      <Link
        href="/"
        className="mb-6 inline-flex items-center gap-2 text-sm text-muted-foreground transition-colors hover:text-primary"
      >
        <ArrowLeft className="h-4 w-4" />
        Back to dashboards
      </Link>

      <Card className="border-2 border-border/60">
        <CardContent className="flex flex-col items-center gap-6 px-6 py-16 text-center">
          {crest ? (
            <div className="relative h-24 w-24 opacity-80 grayscale">
              <Image src={crest} alt={`${title} crest`} fill sizes="96px" className="object-contain" />
            </div>
          ) : (
            <div
              className="flex h-20 w-20 items-center justify-center rounded-full"
              style={{ backgroundColor: `${accent}22`, color: accent }}
            >
              <Lock className="h-8 w-8" />
            </div>
          )}

          <div className="space-y-1">
            <h1 className="text-2xl font-bold text-foreground sm:text-3xl">{title}</h1>
            {subtitle && <p className="text-sm text-muted-foreground">{subtitle}</p>}
          </div>

          <span className="inline-flex items-center gap-2 rounded-full bg-background/70 px-3 py-1 text-xs font-medium text-muted-foreground">
            <Lock className="h-3.5 w-3.5" />
            Awaiting governance-cleared data
          </span>

          <p className="max-w-md text-sm leading-relaxed text-muted-foreground">{reason}</p>
        </CardContent>
      </Card>
    </div>
  );
}
