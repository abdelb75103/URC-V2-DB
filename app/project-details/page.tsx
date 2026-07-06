import Image from 'next/image';
import { PageHeader } from '@/components/dashboard/page-header';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';

export const metadata = { title: 'Project Details — SCRIIPT' };

export default function ProjectDetailsPage() {
  return (
    <div className="flex flex-col">
      <PageHeader title="Project Details" />
      <div className="flex-1 p-4 sm:p-6">
        <div className="mx-auto max-w-4xl space-y-6">
          <Card className="overflow-hidden">
            <div className="grid items-start md:grid-cols-5">
              <div className="relative h-64 w-full md:col-span-2 md:col-start-4 md:h-full">
                <Image
                  src="/images/URCXUCD.png"
                  alt="URC and UCD logos"
                  fill
                  sizes="(max-width: 768px) 100vw, 40vw"
                  className="object-contain p-4"
                />
              </div>
              <div className="md:col-span-3 md:row-start-1">
                <CardHeader>
                  <CardTitle>Project Details</CardTitle>
                </CardHeader>
                <CardContent className="space-y-4 text-muted-foreground">
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
            </div>
          </Card>

          <Card>
            <CardHeader>
              <CardTitle>
                Injury and Illness Surveillance and Athletic Performance Reporting
              </CardTitle>
            </CardHeader>
            <CardContent className="space-y-4 text-muted-foreground">
              <p>
                Each club will be responsible for collecting data that captures all injuries and
                illnesses as per the definitions explained in the appendices, as well as exposure data
                (GPS derived metrics as per definitions). Data will be collected using club specific
                and/or union mandated procedure and processes, with the software that is used in the
                daily practice of each club or per union instructions.
              </p>
              <p>
                Each player in each team will be provided with a unique identifier, and all personal
                data (name, date of birth, demographics) will be de-identified (anonymised).
              </p>
            </CardContent>
          </Card>

          <Card>
            <CardHeader>
              <CardTitle>Research and Analysis</CardTitle>
            </CardHeader>
            <CardContent className="space-y-4 text-muted-foreground">
              <p>
                De-identified (anonymised) data will be shared in aggregated format with the Research
                Team for further analysis and reporting purposes. No personal data will be shared, and
                all appropriate measures will be taken around data security and protection. A
                comprehensive Data Processing Agreement is in place between the URC and University
                College Dublin (UCD). It is important to emphasize that the URC remains the data
                controller at all times, and UCD is a data processor with restricted access to
                anonymised and aggregated data only.
              </p>
            </CardContent>
          </Card>

          <Card>
            <CardHeader>
              <CardTitle>Data Storage and Processing</CardTitle>
            </CardHeader>
            <CardContent className="space-y-4 text-muted-foreground">
              <p>
                All data will be transferred monthly into a URC Secured Database (Data Lakehouse). The
                data collection and management are strictly confidential and adhere to GDPR and Data
                privacy guidelines and legislation.
              </p>
            </CardContent>
          </Card>
        </div>
      </div>
    </div>
  );
}
