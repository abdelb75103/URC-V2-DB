import { Card } from '@/components/ui/card';
import { cn } from '@/lib/utils';

interface KpiCardProps {
  label: string;
  value: string;
  unit?: string;
  hint?: string;
  emphasis?: boolean;
  className?: string;
}

export function KpiCard({ label, value, unit, hint, emphasis, className }: KpiCardProps) {
  return (
    <Card
      className={cn(
        'flex flex-col justify-between gap-1 p-4',
        emphasis && 'border-primary/40 bg-primary/5',
        className
      )}
    >
      <span className="text-xs font-medium text-muted-foreground">
        {label}
      </span>
      <span
        className={cn(
          'font-bold leading-tight text-foreground',
          emphasis ? 'text-3xl text-primary' : 'text-2xl'
        )}
      >
        {value}
      </span>
      {unit && <span className="text-xs text-muted-foreground">{unit}</span>}
      {hint && <span className="mt-1 text-[11px] leading-snug text-muted-foreground">{hint}</span>}
    </Card>
  );
}
