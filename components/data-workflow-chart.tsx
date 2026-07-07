import Image from 'next/image';
import { ArrowDown, ArrowDownRight, ArrowDownLeft } from 'lucide-react';

const WorkflowStep = ({ text }: { text: string }) => (
  <div className="w-full max-w-md rounded-lg border border-border/60 bg-muted/60 px-6 py-4 text-center text-sm text-foreground shadow-md sm:text-base">
    {text}
  </div>
);

const Arrow = () => (
  <div className="my-2 flex justify-center text-primary">
    <ArrowDown className="h-8 w-8" />
  </div>
);

export function DataWorkflowChart() {
  return (
    <div className="flex flex-col items-center rounded-lg bg-card/40 p-4 text-foreground sm:p-6">
      <div className="mb-6 flex w-full items-center justify-between px-4">
        <div className="relative h-12 w-12 sm:h-16 sm:w-16">
          <Image src="/images/URC.png" alt="URC logo" fill className="object-contain" />
        </div>
        <div className="relative h-12 w-12 sm:h-16 sm:w-16">
          <Image src="/images/UCDLogo.png" alt="UCD logo" fill className="object-contain" />
        </div>
      </div>

      <div className="mb-6 rounded-lg bg-primary px-6 py-4 text-center text-lg font-bold text-primary-foreground shadow-lg">
        Data Management Workflow
      </div>

      <div className="flex w-full flex-col items-center">
        <WorkflowStep text="Data Collected by Team at Source" />
        <Arrow />
        <WorkflowStep text="Uploaded by Team to Secure Google Drive on a Monthly Basis" />
        <Arrow />
        <WorkflowStep text="Data Deposited Into Secure URC Lakehouse" />
        <Arrow />
        <WorkflowStep text="Data Anonymised by the URC as Data Controller" />

        {/* Split section */}
        <div className="my-2 flex w-full max-w-md justify-center">
          <div className="relative h-12 w-full">
            <div className="absolute left-1/2 top-0 h-6 w-px -translate-x-1/2 bg-border" />
            <div className="absolute left-0 top-5 h-px w-full bg-border" />
            <div className="absolute left-0 top-5 h-6 w-px bg-border" />
            <div className="absolute right-0 top-5 h-6 w-px bg-border" />
            <ArrowDownLeft className="absolute left-0 top-9 h-8 w-8 -translate-x-4 text-primary" />
            <ArrowDownRight className="absolute right-0 top-9 h-8 w-8 translate-x-4 text-primary" />
          </div>
        </div>

        <div className="mt-6 flex w-full flex-col justify-between gap-4 sm:flex-row">
          <div className="flex-1 rounded-lg border border-border/60 bg-muted/60 px-6 py-4 text-center text-sm text-foreground shadow-md sm:text-base">
            Data Returned to UCD for Research Purposes as Data Processor
          </div>
          <div className="flex-1 rounded-lg border border-border/60 bg-muted/60 px-6 py-4 text-center text-sm text-foreground shadow-md sm:text-base">
            Data Utilised to Produce URC SCRIIPT Project Reports
          </div>
        </div>
      </div>
    </div>
  );
}
