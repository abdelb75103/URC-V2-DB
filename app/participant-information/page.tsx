import Link from 'next/link';
import { Info } from 'lucide-react';
import { PageHeader } from '@/components/dashboard/page-header';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Alert, AlertDescription, AlertTitle } from '@/components/ui/alert';

export const metadata = { title: 'Participant Information — SCRIIPT' };

const sections: { title: string; body: React.ReactNode }[] = [
  {
    title:
      'The URC Surveillance of Continental Rugby Injury-Illness and Performance Tracking (SCRIIPT) Project',
    body: (
      <p>
        The purpose of the URC SCRIIPT Project is to provide comprehensive, accurate and reliable
        injury and illness surveillance, as well as benchmarking athletic performance and workload
        exposure, in professional rugby.
      </p>
    ),
  },
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
        <div className="mx-auto max-w-4xl space-y-6">
          <Alert>
            <Info className="h-4 w-4" />
            <AlertTitle>Welcome</AlertTitle>
            <AlertDescription>
              <p>
                Thank you for participating in this project and for taking the time to read the
                following information carefully. Please feel free to ask questions on our{' '}
                <Link href="/contact" className="underline hover:text-primary">
                  contact page
                </Link>
                . If anything you read is not clear or if you would like more information please
                contact us{' '}
                <Link href="/contact" className="underline hover:text-primary">
                  here
                </Link>
                .
              </p>
            </AlertDescription>
          </Alert>

          {sections.map((s) => (
            <Card key={s.title}>
              <CardHeader>
                <CardTitle className="leading-snug">{s.title}</CardTitle>
              </CardHeader>
              <CardContent className="space-y-4 text-muted-foreground">{s.body}</CardContent>
            </Card>
          ))}
        </div>
      </div>
    </div>
  );
}
