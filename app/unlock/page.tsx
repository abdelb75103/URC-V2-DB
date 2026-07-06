import { Suspense } from 'react';
import { UnlockForm } from '@/components/unlock-form';

export const metadata = { title: 'Unlock — SCRIIPT' };

export default function UnlockPage() {
  return (
    <div className="flex min-h-[70vh] flex-col items-center justify-center p-4">
      <Suspense fallback={<div className="text-muted-foreground">Loading…</div>}>
        <UnlockForm />
      </Suspense>
    </div>
  );
}
