import { Hero } from '@/components/hero';
import { TeamTile } from '@/components/team-tile';
import { teams } from '@/config/teams';
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

        <p className="mx-auto mt-10 max-w-2xl text-center text-xs leading-relaxed text-muted-foreground">
          Only aggregates that have passed governance-approved disclosure control are
          published. Team dashboards appear as their cleared aggregates are released.
        </p>
      </div>
    </div>
  );
}
