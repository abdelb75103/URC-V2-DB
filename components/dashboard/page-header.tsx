import Image from 'next/image';
import Link from 'next/link';
import { ChevronLeft } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { getTeamById } from '@/config/teams';

interface PageHeaderProps {
  title: string;
  crestId?: string;
  crestUrl?: string;
  crestAlt?: string;
  backHref?: string;
  backLabel?: string;
}

export function PageHeader({
  title,
  crestId,
  crestUrl,
  crestAlt = 'Crest',
  backHref = '/',
  backLabel = 'Back to Home',
}: PageHeaderProps) {
  const team = crestId ? getTeamById(crestId) : null;
  const imageUrl = team?.crest ?? crestUrl;

  return (
    <header className="border-b border-border/50">
      <div className="mx-auto flex w-full max-w-6xl items-center gap-4 px-4 py-4 sm:px-6">
        <Button variant="outline" size="icon" asChild>
          <Link href={backHref}>
            <ChevronLeft className="h-4 w-4" />
            <span className="sr-only">{backLabel}</span>
          </Link>
        </Button>
        {imageUrl && (
          <div className="relative h-10 w-10 flex-shrink-0 sm:h-12 sm:w-12">
            <Image src={imageUrl} alt={crestAlt} width={48} height={48} className="object-contain" />
          </div>
        )}
        <h1 className="truncate text-2xl font-bold leading-tight text-foreground capitalize sm:text-3xl">{title}</h1>
      </div>
    </header>
  );
}
