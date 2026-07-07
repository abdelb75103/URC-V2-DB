import Link from 'next/link';
import { MessageCircleQuestion } from 'lucide-react';
import { PageHeader } from '@/components/dashboard/page-header';
import { Card, CardContent } from '@/components/ui/card';
import { Button } from '@/components/ui/button';

export const metadata = { title: 'Participant Information — SCRIIPT' };

const lead = {
  title:
    'The URC Surveillance of Continental Rugby Injury-Illness and Performance Tracking (SCRIIPT) Project',
  body: (
    <p>
      The purpose of the URC SCRIIPT Project is to provide comprehensive, accurate and reliable
      injury and illness surveillance, as well as benchmarking athletic performance and workload
      exposure, in professional rugby.
    </p>
  ),
};

const sections: { title: string; body: React.ReactNode }[] = [
  {
    title: 'Why are we doing this research?',
    body: (
      <p>
        This aim of this project is to provide general insights into risk of injury, injury trends,
        and the burden of injury and illness, as well as understanding around the performance of the
        competition and each team. Individualised reports to each club, as well as a comprehensive
        overview of the competition, will allow each club to develop their own unique plans relating
        to injury, as well as contribute to the health and sustained future of the competition.
      </p>
    ),
  },
  {
    title: 'Why have you been invited to take part?',
    body: (
      <p>
        Participation in the injury reporting is mandatory as per player/club agreements with the
        URC. You have the right to withdraw any of your data for utilisation in future academic
        published research papers.
      </p>
    ),
  },
  {
    title: 'How will your data be used?',
    body: (
      <p>
        Your existing and future training, match, and injury data will be used for analysis—no
        additional testing or time commitment is required. Following the completion of the study, the
        collected, anonymised data may be uploaded to a data repository within UCD allowing for
        future research to be undertaken using the available data set.
      </p>
    ),
  },
  {
    title: 'What will happen if you decide to take part in this research study?',
    body: (
      <p>
        Each club will be responsible for collecting data that captures all injuries and illnesses,
        as well as exposure data collected via GPS. Data will be collected using club specific and/or
        union mandated procedure and processes, with the software that is used in the daily practice
        of each club or per union instructions.
      </p>
    ),
  },
  {
    title: 'How will your privacy be protected?',
    body: (
      <>
        <p>
          Each player in each team will be provided with a unique identifier, and all personal data
          (name, date of birth, demographics) will be de-identified (anonymised). De-identified
          (anonymised) data will be shared in aggregated format with the Research Team for further
          analysis and reporting purposes. No personal data will be shared, and all appropriate
          measures will be taken around data security and protection.
        </p>
        <p>
          A full Data Processing Agreement is in place between the URC and UCD. It is important to
          emphasise that the URC remains the data controller at all times, and UCD is a data
          processor with restricted access to pseudonymised data only. As Data Processor, UCD will
          only carry out specific instructions by the URC. This study is subject to ethical approval
          from the UCD Human Research Ethics Committee (HREC).
        </p>
      </>
    ),
  },
  {
    title: 'What are the benefits of taking part in this research study?',
    body: (
      <p>
        By participating, players and clubs will contribute to a better understanding of injury and
        illness risk in elite rugby. This project allows for benchmarking across the URC and provides
        tailored feedback to each club, helping to inform injury prevention, return-to-play
        strategies, and long-term athlete welfare planning. Participation supports a broader goal of
        improving player health and performance across the competition.
      </p>
    ),
  },
  {
    title: 'What are the benefits to the researcher of taking part in the study?',
    body: (
      <p>
        The Primary Investigator is conducting this project on behalf of the URC, but there will be a
        PhD project running concurrently alongside this. The benefits for the URC have been
        highlighted above while the PhD candidate will gain valuable insights from the real-world
        application of injury surveillance, performance analytics, and workload data in elite sport.
      </p>
    ),
  },
];

export default function ParticipantInformationPage() {
  return (
    <div className="flex flex-col">
      <PageHeader title="Participant Information" />
      <div className="flex-1 p-4 sm:p-6">
        <div className="mx-auto max-w-5xl space-y-6">
          <Card>
            <div className="p-6 sm:p-8 md:p-10">
              <div className="max-w-3xl space-y-4">
                <p className="text-xs font-semibold uppercase tracking-[0.2em] text-primary">
                  Participant Information Sheet
                </p>
                <h2 className="text-2xl font-bold leading-tight text-foreground sm:text-3xl">
                  {lead.title}
                </h2>
                <div className="max-w-[65ch] text-base leading-relaxed text-muted-foreground sm:text-lg">
                  {lead.body}
                </div>
              </div>

              <dl className="mt-10 divide-y divide-border/60 border-t border-border/60">
                {sections.map((s) => (
                  <div
                    key={s.title}
                    className="grid gap-x-10 gap-y-3 py-8 md:grid-cols-[minmax(0,15rem)_1fr]"
                  >
                    <dt className="text-base font-semibold leading-snug text-foreground md:text-lg">
                      {s.title}
                    </dt>
                    <dd className="max-w-[68ch] space-y-4 leading-relaxed text-muted-foreground">
                      {s.body}
                    </dd>
                  </div>
                ))}
              </dl>
            </div>
          </Card>

          <Card className="border-primary/30 bg-primary/5">
            <CardContent className="flex flex-col gap-4 p-6 sm:flex-row sm:items-center sm:justify-between">
              <div className="flex items-start gap-3">
                <span className="mt-0.5 flex h-9 w-9 shrink-0 items-center justify-center rounded-lg bg-primary/10 text-primary">
                  <MessageCircleQuestion className="h-5 w-5" />
                </span>
                <div className="space-y-1">
                  <p className="font-semibold text-foreground">Questions about the project?</p>
                  <p className="text-sm text-muted-foreground">
                    If anything you have read is not clear, or you would like more information, the
                    project team is happy to help.
                  </p>
                </div>
              </div>
              <Button asChild className="shrink-0 sm:self-center">
                <Link href="/contact">Contact the team</Link>
              </Button>
            </CardContent>
          </Card>
        </div>
      </div>
    </div>
  );
}
