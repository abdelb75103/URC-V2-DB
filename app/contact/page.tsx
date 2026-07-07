import { Mail } from 'lucide-react';
import { PageHeader } from '@/components/dashboard/page-header';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';

export const metadata = { title: 'Contact — SCRIIPT' };

const contacts = [
  { name: 'Greg Hawe', title: 'PhD Researcher & Lead Physiotherapist', email: 'Greg.hawe1@ucdconnect.ie' },
  { name: 'Nicol Van Dyk', title: 'Research & Performance Leader', email: 'Nicol.vandyk@ucd.ie' },
  {
    name: 'Amy Monaghan',
    title: 'Head of Operations, United Rugby Championship (URC)',
    email: 'amy.monaghan@unitedrugby.com',
  },
];

export default function ContactPage() {
  return (
    <div className="flex flex-col">
      <PageHeader title="Contact Us" />
      <div className="flex flex-1 items-start justify-center p-4 sm:p-6">
        <div className="mx-auto w-full max-w-5xl">
          <div className="mb-8 text-center">
            <h2 className="text-3xl font-bold">Get in Touch</h2>
            <p className="text-muted-foreground">
              For any inquiries, please reach out to the project leads below.
            </p>
          </div>
          <div className="grid grid-cols-1 gap-6 md:grid-cols-3">
            {contacts.map((contact) => (
              <Card key={contact.name} className="flex flex-col">
                <CardHeader className="text-center">
                  <CardTitle>{contact.name}</CardTitle>
                  <CardDescription className="text-primary md:flex md:min-h-[2.5rem] md:items-center md:justify-center">
                    {contact.title}
                  </CardDescription>
                </CardHeader>
                <CardContent className="flex flex-grow flex-col items-center justify-center">
                  <a
                    href={`mailto:${contact.email}`}
                    className="group/email inline-flex max-w-full items-start gap-2 text-sm text-muted-foreground transition-colors hover:text-primary"
                  >
                    <Mail className="mt-0.5 h-4 w-4 shrink-0 text-primary" />
                    <span className="break-words group-hover/email:underline">{contact.email}</span>
                  </a>
                </CardContent>
              </Card>
            ))}
          </div>
        </div>
      </div>
    </div>
  );
}
