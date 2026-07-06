import { ArrowRight, FileSpreadsheet, Database, SlidersHorizontal, ShieldCheck, BarChart3 } from 'lucide-react';
import { PageHeader } from '@/components/dashboard/page-header';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';

export const metadata = { title: 'Data Upload Guidelines — SCRIIPT' };

const workflow = [
  { icon: FileSpreadsheet, label: 'Club upload', detail: 'Injury & GPS files in their native format' },
  { icon: Database, label: 'Ingestion manifest', detail: 'Immutable raw records + provenance' },
  { icon: SlidersHorizontal, label: 'Standardise & clean', detail: 'Mapped to canonical schema, row-level audit' },
  { icon: ShieldCheck, label: 'Validate & disclosure control', detail: 'Analysis views, small-cell rules' },
  { icon: BarChart3, label: 'Dashboards & reports', detail: 'Approved aggregates only' },
];

export default function DataUploadPage() {
  return (
    <div className="flex flex-col">
      <PageHeader title="Data Upload Guidelines" />
      <div className="flex-1 p-4 sm:p-6">
        <div className="mx-auto max-w-4xl space-y-6">
          <Card>
            <CardHeader>
              <CardTitle>Data Submission Process</CardTitle>
            </CardHeader>
            <CardContent className="space-y-4 text-muted-foreground">
              <p>
                Data submissions will be requested on a monthly basis, with specific schedules and
                deadlines communicated through the microsite and reinforced via email reminders. You
                should upload any data you collect in the format in which it is originally gathered, to
                avoid duplication of effort; the research team will then complete all required cleaning
                and organisation.
              </p>
              <p>
                While the minimum injury surveillance and GPS data fields must be included, you are
                welcome to provide more detailed information, though this may not necessarily be used
                in reporting. Data can be submitted in formats such as Excel or similar, and the
                frequency and methods of upload are outlined in the workflow below.
              </p>
            </CardContent>
          </Card>

          <Card>
            <CardHeader>
              <CardTitle>Data Management Workflow</CardTitle>
            </CardHeader>
            <CardContent>
              <ol className="flex flex-col gap-4 md:flex-row md:items-stretch md:gap-2">
                {workflow.map((step, i) => (
                  <li key={step.label} className="flex flex-1 items-center gap-3 md:flex-col md:gap-2 md:text-center">
                    <div className="flex flex-1 items-center gap-3 rounded-lg border border-border/60 bg-background/40 p-3 md:h-full md:flex-col md:justify-start">
                      <span className="flex h-10 w-10 shrink-0 items-center justify-center rounded-full bg-primary/10 text-primary">
                        <step.icon className="h-5 w-5" />
                      </span>
                      <div>
                        <p className="text-sm font-semibold text-foreground">{step.label}</p>
                        <p className="mt-0.5 text-xs text-muted-foreground">{step.detail}</p>
                      </div>
                    </div>
                    {i < workflow.length - 1 && (
                      <ArrowRight className="h-5 w-5 shrink-0 rotate-90 text-muted-foreground md:rotate-0" />
                    )}
                  </li>
                ))}
              </ol>
            </CardContent>
          </Card>
        </div>
      </div>
    </div>
  );
}
