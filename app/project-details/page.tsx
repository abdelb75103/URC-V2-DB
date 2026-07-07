import Image from 'next/image';
import { ClipboardList, FlaskConical, Database } from 'lucide-react';
import { PageHeader } from '@/components/dashboard/page-header';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';

export const metadata = { title: 'Project Details — SCRIIPT' };

const stages: {
  step: string;
  icon: React.ComponentType<{ className?: string }>;
  title: string;
  body: React.ReactNode;
}[] = [
  {
    step: '01',
    icon: ClipboardList,
    title: 'Surveillance & Reporting',
    body: (
      <>
        <p>
          Each club collects data capturing all injuries and illnesses, as defined in the appendices,
          alongside exposure data (GPS-derived metrics as per definitions). Data is collected using
          club-specific and/or union-mandated procedures, with the software used in each club&apos;s
          daily practice or per union instructions.
        </p>
        <p>
          Each player is given a unique identifier, and all personal data (name, date of birth,
          demographics) is de-identified (anonymised).
        </p>
      </>
    ),
  },
  {
    step: '02',
    icon: FlaskConical,
    title: 'Research & Analysis',
    body: (
      <p>
        De-identified data is shared in aggregated format with the Research Team for analysis and
        reporting. No personal data is shared, and all appropriate measures are taken around data
        security and protection. A comprehensive Data Processing Agreement is in place between the URC
        and University College Dublin (UCD): the URC remains the data controller at all times, and UCD
        is a data processor with restricted access to anonymised, aggregated data only.
      </p>
    ),
  },
  {
    step: '03',
    icon: Database,
    title: 'Data Storage & Processing',
    body: (
      <p>
        All data is transferred monthly into a URC Secured Database (Data Lakehouse). Data collection
        and management are strictly confidential and adhere to GDPR and data-privacy guidelines and
        legislation.
      </p>
    ),
  },
];

export default function ProjectDetailsPage() {
  return (
    <div className="flex flex-col">
      <PageHeader title="Project Details" />
      <div className="flex-1 p-4 sm:p-6">
        <div className="mx-auto max-w-6xl space-y-10">
          <Card className="overflow-hidden">
            <div className="grid items-stretch md:grid-cols-5">
              <div className="md:col-span-3 md:row-start-1">
                <CardHeader>
                  <p className="text-xs font-semibold uppercase tracking-[0.2em] text-primary">
                    The SCRIIPT Project
                  </p>
                  <CardTitle className="text-2xl sm:text-3xl">
                    Injury, illness and performance across the URC
                  </CardTitle>
                </CardHeader>
                <CardContent className="max-w-[64ch] space-y-4 text-muted-foreground">
                  <p>
                    Over the past four seasons, the URC has evolved significantly, reflecting broader
                    shifts within rugby. Notable trends include a rise in reported concussions, driven
                    by improved awareness and reporting protocols, and an increase in soft tissue
                    injuries due to the game&apos;s escalating physical demands and shorter recovery
                    times. Performance metrics show a rise in points per game, indicating a shift
                    towards more attacking play, while defensive strategies have also improved.
                  </p>
                  <p>
                    The URC&apos;s focus on player welfare is evident in the upcoming introduction of
                    mandatory instrumented mouth guards and the strategic use of player rotations and
                    squad depth management. Younger players are being integrated into senior squads,
                    promoting long-term development. Technological advancements in performance analysis
                    and injury prevention are providing deeper insights into player health and
                    performance, while tactical variability has made matches more unpredictable and
                    strategic.
                  </p>
                  <p>
                    To further enhance player safety and performance, the URC SCRIIPT Project aims to
                    quantify injury and illness incidence, ensure accurate reporting, and monitor
                    trends over time. Integrating diverse data sources will offer nuanced insights into
                    the impact of injuries on game metrics and team performance. A structured approach
                    with defined work packages will ensure the project&apos;s successful
                    implementation, contributing to the championship&apos;s integrity and
                    competitiveness.
                  </p>
                </CardContent>
              </div>
              <div className="relative h-56 w-full border-t border-border/50 bg-background/30 md:col-span-2 md:col-start-4 md:row-start-1 md:h-full md:border-l md:border-t-0">
                <Image
                  src="/images/URCXUCD.png"
                  alt="URC and UCD logos"
                  fill
                  sizes="(max-width: 768px) 100vw, 40vw"
                  className="object-contain p-6"
                />
              </div>
            </div>
          </Card>

          <section className="space-y-6">
            <div className="space-y-1">
              <p className="text-xs font-semibold uppercase tracking-[0.2em] text-primary">
                How the project works
              </p>
              <h2 className="text-xl font-semibold text-foreground sm:text-2xl">
                From the training ground to the database
              </h2>
              <p className="max-w-2xl text-sm text-muted-foreground">
                Every record follows the same governed path — collected at the club, analysed only in
                aggregate, then stored securely.
              </p>
            </div>

            <div className="grid gap-6 md:grid-cols-3">
              {stages.map(({ step, icon: Icon, title, body }) => (
                <Card key={step} className="flex h-full flex-col border-t-2 border-t-primary/60">
                  <CardHeader className="space-y-4">
                    <div className="flex items-center justify-between">
                      <span className="flex h-10 w-10 items-center justify-center rounded-lg bg-primary/10 text-primary">
                        <Icon className="h-5 w-5" />
                      </span>
                      <span className="text-3xl font-bold tabular-nums text-primary/25">{step}</span>
                    </div>
                    <CardTitle className="text-lg leading-snug">{title}</CardTitle>
                  </CardHeader>
                  <CardContent className="space-y-4 text-sm leading-relaxed text-muted-foreground">
                    {body}
                  </CardContent>
                </Card>
              ))}
            </div>
          </section>
        </div>
      </div>
    </div>
  );
}
