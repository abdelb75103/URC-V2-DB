import Link from 'next/link';
import Image from 'next/image';
import { unions } from '@/config/unions';

export const metadata = { title: 'Union Dashboards — SCRIIPT' };

export default function UnionsPage() {
  return (
    <div className="flex min-h-screen flex-col items-center px-4 pb-16 pt-10 sm:px-8 md:px-12">
      <div className="w-full max-w-5xl">
        <h1 className="text-2xl font-semibold text-foreground">Union Dashboards</h1>
        <p className="mt-2 max-w-2xl text-sm leading-relaxed text-muted-foreground">
          Union-level views aggregate the approved data of each union&apos;s URC teams.
          They unlock as cleared aggregate releases are published.
        </p>

        <div className="mt-8 grid grid-cols-2 gap-4 sm:grid-cols-3 md:grid-cols-5">
          {unions.map((union) => (
            <Link
              key={union.id}
              href={`/union/${union.id}`}
              className="group flex flex-col items-center justify-center gap-3 rounded-lg border border-border/60 bg-card/60 px-3 py-6 text-center transition-colors hover:border-primary/50"
            >
              {union.crest && (
                <Image
                  src={union.crest}
                  alt={`${union.governingBody} crest`}
                  width={56}
                  height={56}
                  className="h-14 w-14 object-contain"
                />
              )}
              <span className="text-sm font-medium text-muted-foreground transition-colors group-hover:text-foreground">
                {union.name}
              </span>
            </Link>
          ))}
        </div>
      </div>
    </div>
  );
}
