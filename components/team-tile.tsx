import Link from 'next/link';
import Image from 'next/image';
import { Lock } from 'lucide-react';
import { Card, CardContent } from '@/components/ui/card';
import { cn } from '@/lib/utils';

export type TileData = {
  id: string;
  name: string;
  crest: string;
  status: 'live' | 'locked';
};

interface TeamTileProps {
  team: TileData;
  href: string;
  /** Larger treatment for the league/URC overall tile. */
  featured?: boolean;
}

export function TeamTile({ team, href, featured = false }: TeamTileProps) {
  const isLive = team.status === 'live';

  const inner = (
    <Card
      className={cn(
        'h-full border-2 transition-all duration-300 ease-in-out',
        isLive
          ? 'border-primary/30 hover:border-primary/60 hover:shadow-lg hover:shadow-primary/20'
          : 'border-border/60 opacity-70'
      )}
    >
      <CardContent
        className={cn(
          'flex flex-col items-center justify-center h-full relative',
          featured ? 'p-8' : 'p-6'
        )}
      >
        {!isLive && (
          <span className="absolute top-2 right-2 inline-flex items-center gap-1 rounded-full bg-background/70 px-2 py-0.5 text-[10px] font-medium text-muted-foreground">
            <Lock className="h-3 w-3" />
            Locked
          </span>
        )}
        <div
          className={cn(
            'relative mb-4',
            featured ? 'w-28 h-28' : 'w-24 h-24',
            !isLive && 'grayscale'
          )}
        >
          <Image
            src={team.crest}
            alt={`${team.name} crest`}
            fill
            sizes="112px"
            className={cn(
              'object-contain transition-transform duration-300',
              isLive && 'group-hover:scale-110'
            )}
          />
        </div>
        <p
          className={cn(
            'text-center font-semibold text-foreground',
            featured ? 'text-xl' : 'text-lg'
          )}
        >
          {team.name}
        </p>
        <p className="mt-1 text-center text-xs text-muted-foreground">
          {isLive ? 'View dashboard' : 'Awaiting cleared data'}
        </p>
      </CardContent>
    </Card>
  );

  if (!isLive) {
    return (
      <div className="block cursor-not-allowed" aria-disabled title="Awaiting governance-cleared data">
        {inner}
      </div>
    );
  }

  return (
    <Link href={href} prefetch={false} className="group block">
      {inner}
    </Link>
  );
}
