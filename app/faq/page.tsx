import Link from 'next/link';
import { PageHeader } from '@/components/dashboard/page-header';
import {
  Accordion,
  AccordionContent,
  AccordionItem,
  AccordionTrigger,
} from '@/components/ui/accordion';

export const metadata = { title: 'FAQ — SCRIIPT' };

const faqItems: { question: string; answer: React.ReactNode }[] = [
  {
    question: 'What is the aim of this project?',
    answer: (
      <p>
        The project aims to better understand the relationship between workload (GPS exposure), match
        performance, and the occurrence of injury and illness in elite rugby union. Our goal is to
        improve injury surveillance, identify risk factors, and support data-driven decision-making
        for player welfare.
      </p>
    ),
  },
  {
    question: 'Who is running the project?',
    answer: (
      <p>
        The project is being led by a dedicated research team in collaboration with URC medical and
        performance staff. It is supported by a parallel PhD project focusing on complex systems
        approaches to athlete health and performance. See the{' '}
        <Link href="/about-us" className="underline hover:text-primary">
          about us
        </Link>{' '}
        section for more details.
      </p>
    ),
  },
  {
    question: 'Who can access the microsite?',
    answer: (
      <p>
        Access is restricted to approved URC players, medical staff, and performance team members.
        You will need a password to log in.
      </p>
    ),
  },
  {
    question: 'What kind of data will be collected?',
    answer: (
      <div className="space-y-2">
        <p>We are collecting anonymised data on:</p>
        <ul className="list-disc space-y-1 pl-5">
          <li>Training and match exposure (e.g., GPS metrics like total distance, high-speed running)</li>
          <li>Injury and illness records (type, severity, time-loss)</li>
        </ul>
      </div>
    ),
  },
  {
    question: 'How is player privacy protected?',
    answer: (
      <p>
        All data submitted will be anonymised using unique IDs. Personal identifiers will not be
        included. Data handling follows GDPR regulations and institutional ethical approvals to ensure
        confidentiality and security.
      </p>
    ),
  },
  {
    question: 'How often do we need to submit data?',
    answer: (
      <p>
        Data submissions will be requested on a monthly basis. Specific submission schedules and
        deadlines will be communicated through the microsite and email reminders.
      </p>
    ),
  },
  {
    question: 'What data do I upload?',
    answer: (
      <p>
        Please upload any data that you collect, in the format by which you collect the data. This is
        to avoid double entry on your behalf. The research team will conduct all necessary data
        cleaning and organisation.
      </p>
    ),
  },
  {
    question: 'What will we get back in return?',
    answer: (
      <div className="space-y-2">
        <p>Participating teams will receive:</p>
        <ul className="list-disc space-y-1 pl-5">
          <li>Regular summary reports and insights</li>
          <li>Benchmarking data (aggregated across the URC)</li>
          <li>Opportunities to co-author publications</li>
        </ul>
      </div>
    ),
  },
  {
    question: 'Can my team or I be involved in publishing research papers?',
    answer: (
      <p>
        Yes! We are forming a collaborative Author Group involving team representatives and academic
        contributors. If you&apos;re interested in participating, please contact the study team.
      </p>
    ),
  },
  {
    question: 'Who do I contact if I have a question?',
    answer: (
      <p>
        Please visit our{' '}
        <Link href="/contact" className="underline hover:text-primary">
          contact page
        </Link>{' '}
        or reach out directly to:{' '}
        <a href="mailto:Greg.hawe1@ucdconnect.ie" className="underline hover:text-primary">
          Greg.hawe1@ucdconnect.ie
        </a>{' '}
        or{' '}
        <a href="mailto:Nicol.vandyk@ucd.ie" className="underline hover:text-primary">
          Nicol.vandyk@ucd.ie
        </a>
        .
      </p>
    ),
  },
];

export default function FaqPage() {
  return (
    <div className="flex flex-col">
      <PageHeader title="Frequently Asked Questions" />
      <div className="flex-1 p-4 sm:p-6">
        <div className="mx-auto max-w-4xl">
          <Accordion type="single" collapsible className="w-full">
            {faqItems.map((item, index) => (
              <AccordionItem key={index} value={`item-${index}`}>
                <AccordionTrigger className="text-left">{item.question}</AccordionTrigger>
                <AccordionContent className="text-muted-foreground">{item.answer}</AccordionContent>
              </AccordionItem>
            ))}
          </Accordion>
        </div>
      </div>
    </div>
  );
}
