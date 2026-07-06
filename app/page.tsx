import Link from 'next/link';
import { Hero } from '@/components/hero';
import { TeamTile } from '@/components/team-tile';
import { teams } from '@/config/teams';
import { unions } from '@/config/unions';
import { StaticImages } from '@/lib/placeholder-images';

export default function Home() {
  const urcTile = {
    id: 'urc',
    name: 'URC Overall',
    crest: StaticImages.urcLogo,
    status: 'locked' as const,
  };

  return (
    <div className="flex min-h-screen flex-col items-center px-4 pb-16 pt-8 sm:px-8 md:px-12">
      <div className="w-full max-w-5xl">
        <Hero />

        {/* League overall */}
        <div className="mb-4 w-full">
          <TeamTile team={urcTile} href="/urc" featured />
        </div>

        {/* Team grid */}
        <div className="grid w-full grid-cols-2 gap-4 sm:grid-cols-4">
          {teams.map((team) => (
            <TeamTile key={team.id} team={team} href={`/team/${team.id}`} />
          ))}
        </div>

        {/* Unions */}
        <section className="mt-12 w-full">
          <h2 className="mb-4 text-lg font-semibold text-foreground">Union Dashboards</h2>
          <div className="grid grid-cols-2 gap-3 sm:grid-cols-3 md:grid-cols-5">
            {unions.map((union) => (
              <Link
                key={union.id}
                href={`/union/${union.id}`}
                className="group flex items-center justify-center rounded-lg border border-border/60 bg-card/60 px-3 py-4 text-center text-sm font-medium text-muted-foreground transition-colors hover:border-primary/50 hover:text-foreground"
              >
                {union.name}
              </Link>
            ))}
          </div>
        </section>

        <p className="mx-auto mt-10 max-w-2xl text-center text-xs leading-relaxed text-muted-foreground">
          Only aggregates that have passed governance-approved disclosure control are
          published. Munster is the pilot; remaining teams and unions unlock as their
          cleared aggregates are released.
        </p>
      </div>
    </div>
  );
}
