'use client';

import { useLinkStatus } from 'next/link';

export function LinkPendingStatus({ label, className }: { label: string; className: string }) {
  const { pending } = useLinkStatus();

  // ponytail: Keep feedback on the clicked link without changing dashboard loading.
  return (
    <>
      <span
        aria-hidden="true"
        className={`pointer-events-none absolute ${pending ? 'opacity-100 motion-safe:animate-pulse' : 'opacity-0'} ${className}`}
      />
      <span className="sr-only" role="status" aria-live="polite">
        {pending ? label : ''}
      </span>
    </>
  );
}
