'use client';

import type { InjuryTypeFamilyRow } from '@/lib/reporting-types';

export type InjuryTypeMetric =
  | 'time_loss_injuries'
  | 'incidence_per_1000h'
  | 'burden_per_1000h';

export const INJURY_FAMILY_COLORS: Record<string, string> = {
  muscle: 'hsl(2 58% 53%)',
  tendon: 'hsl(43 42% 82%)',
  ligament_sprain: 'hsl(47 64% 70%)',
  joint_capsule: 'hsl(187 48% 54%)',
  bone: 'hsl(38 24% 83%)',
  cartilage: 'hsl(188 74% 52%)',
  nervous_system: 'hsl(43 82% 59%)',
  skin_superficial: 'hsl(18 54% 67%)',
  internal_organ: 'hsl(346 45% 57%)',
  vascular: 'hsl(351 70% 58%)',
};

const METRIC_LABELS: Record<InjuryTypeMetric, { label: string; unit: string; longUnit: string }> = {
  time_loss_injuries: { label: 'TL injuries', unit: 'injuries', longUnit: 'TL injuries' },
  incidence_per_1000h: { label: 'TL incidence', unit: '/1,000 h', longUnit: 'TL injuries per 1,000 player-hours' },
  burden_per_1000h: { label: 'Burden', unit: 'days /1,000 h', longUnit: 'days per 1,000 player-hours' },
};

function metricValue(row: InjuryTypeFamilyRow | undefined, metric: InjuryTypeMetric) {
  const value = row?.[metric];
  return typeof value === 'number' && Number.isFinite(value) ? value : 0;
}

function formatValue(value: number | null | undefined, digits = 1) {
  if (value === null || value === undefined || !Number.isFinite(value)) return 'Not available';
  return new Intl.NumberFormat('en-IE', {
    maximumFractionDigits: digits,
    minimumFractionDigits: Number.isInteger(value) ? 0 : digits,
  }).format(value);
}

// Rates show 1dp, and bars are drawn from that same rounded value, so two rows
// displaying 3.1 render identical bars instead of contradicting the label.
function formatMetric(value: number | null | undefined, metric: InjuryTypeMetric) {
  if (metric === 'time_loss_injuries') return formatValue(value, 0);
  if (value === null || value === undefined || !Number.isFinite(value)) return 'Not available';
  return new Intl.NumberFormat('en-IE', {
    maximumFractionDigits: 1,
    minimumFractionDigits: 1,
  }).format(value);
}

/** The value a ranked bar is drawn from: rounded to what its label shows. */
export function rankedTypeValue(value: number, metric: InjuryTypeMetric) {
  return metric === 'time_loss_injuries' ? value : Math.round(value * 10) / 10;
}

function caseLabel(value: number) {
  return value === 1 ? 'time-loss case' : 'time-loss cases';
}

export function InjuryTypeRanking({
  rows,
  metric,
  activeCode,
  selectedCode,
  onHover,
  onSelect,
}: {
  rows: InjuryTypeFamilyRow[];
  metric: InjuryTypeMetric;
  activeCode?: string;
  selectedCode?: string;
  onHover: (code?: string) => void;
  onSelect: (code: string) => void;
}) {
  const max = Math.max(...rows.map((row) => rankedTypeValue(metricValue(row, metric), metric)), 1);
  const metricMeta = METRIC_LABELS[metric];

  return (
    <div aria-label={`Injury types ranked by ${metricMeta.label.toLowerCase()}`}>
      <div className="mb-2 grid grid-cols-[minmax(0,1fr)_4.75rem] items-end gap-3 px-3 text-[11px] text-muted-foreground sm:grid-cols-[2rem_minmax(8rem,0.7fr)_minmax(7rem,1fr)_4.75rem]">
        <span className="hidden sm:block" aria-hidden="true">Rank</span>
        <span>Injury type</span>
        <span className="hidden sm:block" aria-hidden="true" />
        <span className="text-right">{metricMeta.label}</span>
      </div>
      <div className="space-y-1">
        {rows.map((row, index) => {
          const value = rankedTypeValue(metricValue(row, metric), metric);
          const active = activeCode === row.code;
          const selected = selectedCode === row.code;
          const color = INJURY_FAMILY_COLORS[row.code] ?? 'hsl(var(--primary))';

          return (
            <button
              key={row.code}
              type="button"
              aria-pressed={selected}
              aria-label={`${row.label}, ranked ${index + 1} of ${rows.length}: ${formatMetric(row[metric], metric)} ${metricMeta.longUnit}. ${formatValue(row.time_loss_injuries, 0)} ${caseLabel(row.time_loss_injuries)}.`}
              onMouseEnter={() => onHover(row.code)}
              onMouseLeave={() => onHover()}
              onFocus={() => onHover(row.code)}
              onBlur={() => onHover()}
              onClick={() => onSelect(row.code)}
              className={`grid min-h-16 w-full grid-cols-[minmax(0,1fr)_4.75rem] items-center gap-x-3 gap-y-2 rounded-md border-l-2 px-3 py-2 text-left focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring sm:min-h-14 sm:grid-cols-[2rem_minmax(8rem,0.7fr)_minmax(7rem,1fr)_4.75rem] sm:gap-y-0 sm:py-0 ${active ? 'bg-primary/[0.055] text-foreground' : 'border-l-transparent text-muted-foreground'}`}
              style={{ borderLeftColor: active ? color : 'transparent' }}
            >
              <span className={`hidden text-xs tabular-nums sm:block ${active ? 'font-semibold text-foreground' : 'text-muted-foreground'}`}>
                {String(index + 1).padStart(2, '0')}
              </span>
              <span className={`col-start-1 row-start-1 truncate text-sm sm:col-start-auto sm:row-start-auto ${active ? 'font-semibold text-foreground' : ''}`}>{row.label}</span>
              <span className="col-span-2 col-start-1 row-start-2 h-2.5 overflow-hidden rounded-full bg-background/70 sm:col-span-1 sm:col-start-auto sm:row-start-auto" aria-hidden="true">
                <span
                  className="block h-full rounded-full"
                  style={{
                    width: `${Math.max((value / max) * 100, value > 0 ? 2 : 0)}%`,
                    backgroundColor: color,
                    opacity: active ? 1 : activeCode ? 0.28 : 0.75,
                  }}
                />
              </span>
              <span className="col-start-2 row-start-1 text-right text-base font-semibold tabular-nums text-foreground sm:col-start-auto sm:row-start-auto">{formatMetric(row[metric], metric)}</span>
            </button>
          );
        })}
      </div>
    </div>
  );
}

export function InjuryTypeDossier({
  row,
  metric,
  rank,
  total,
}: {
  row?: InjuryTypeFamilyRow;
  metric: InjuryTypeMetric;
  rank?: number;
  total: number;
}) {
  const contributingSubtypes = row?.subtypes.filter((subtype) => subtype.time_loss_injuries > 0) ?? [];
  const color = row ? INJURY_FAMILY_COLORS[row.code] ?? 'hsl(var(--primary))' : 'hsl(var(--border))';

  return (
    <section className="flex h-full min-h-0 flex-col overflow-hidden lg:min-h-[25rem]">
      <div className="flex items-start justify-between gap-4 px-5 py-4" style={{ boxShadow: `inset 3px 0 0 ${color}` }}>
        <div className="min-w-0">
          <p className="text-xs font-medium text-muted-foreground">Selected injury type</p>
          <h3 className="mt-1 truncate text-xl font-semibold leading-tight text-foreground capitalize">{row?.label ?? 'Not Available'}</h3>
        </div>
        {rank && total > 0 ? (
          <p className="shrink-0 text-xs tabular-nums text-muted-foreground">Rank {rank} of {total}</p>
        ) : null}
      </div>

      <div className="grid grid-cols-3 border-y border-border/60">
        <DossierMetric label="TL injuries" value={formatValue(row?.time_loss_injuries, 0)} unit="injuries" active={metric === 'time_loss_injuries'} />
        <DossierMetric label="TL incidence" value={formatMetric(row?.incidence_per_1000h, 'incidence_per_1000h')} unit="/1,000 h" active={metric === 'incidence_per_1000h'} />
        <DossierMetric label="Burden" value={formatMetric(row?.burden_per_1000h, 'burden_per_1000h')} unit="days /1,000 h" active={metric === 'burden_per_1000h'} />
      </div>

      <div className="flex flex-1 flex-col px-5 py-4">
        <div className="flex items-baseline justify-between gap-4">
          <h4 className="text-sm font-semibold text-foreground">Included injury types</h4>
          <span className="text-[11px] text-muted-foreground">TL injuries</span>
        </div>
        {contributingSubtypes.length ? (
          <div className="mt-3 space-y-1">
            {contributingSubtypes.map((subtype) => (
              <div key={subtype.code} className="grid min-h-11 grid-cols-[minmax(0,1fr)_3rem] items-center gap-4 rounded px-2">
                <span className="truncate text-sm text-muted-foreground">{subtype.label}</span>
                <span className="text-right text-sm font-semibold tabular-nums text-foreground">{formatValue(subtype.time_loss_injuries, 0)}</span>
              </div>
            ))}
          </div>
        ) : (
          <p className="mt-4 text-sm text-muted-foreground">No contributing type is available.</p>
        )}
      </div>
    </section>
  );
}

function DossierMetric({
  label,
  value,
  unit,
  active,
}: {
  label: string;
  value: string;
  unit: string;
  active: boolean;
}) {
  return (
    <div className={`min-w-0 border-r border-border/50 px-3 py-4 last:border-r-0 sm:px-4 ${active ? 'bg-primary/[0.055]' : ''}`}>
      <p className="text-[11px] text-muted-foreground">{label}</p>
      <p className="mt-1 truncate text-xl font-semibold tabular-nums text-foreground">{value}</p>
      <p className="truncate text-[10px] text-muted-foreground">{unit}</p>
    </div>
  );
}
