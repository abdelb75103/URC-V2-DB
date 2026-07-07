import { PageHeader } from '@/components/dashboard/page-header';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { DataWorkflowChart } from '@/components/data-workflow-chart';

export const metadata = { title: 'Data Upload Guidelines — SCRIIPT' };

export default function DataUploadPage() {
  return (
    <div className="flex flex-col">
      <PageHeader title="Data Upload Guidelines" />
      <div className="flex-1 p-4 sm:p-6">
        <div className="mx-auto max-w-6xl space-y-6">
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
              <DataWorkflowChart />
            </CardContent>
          </Card>
        </div>
      </div>
    </div>
  );
}
