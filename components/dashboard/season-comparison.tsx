'use client';

import { useState, type ReactNode } from 'react';
import { ArrowDown, ArrowUp, Minus } from 'lucide-react';
import { Card, CardContent } from '@/components/ui/card';
import { Tabs, TabsList, TabsTrigger } from '@/components/ui/tabs';
import type { SeasonComparisonData } from '@/lib/season-comparison';
import {
  ImpactBubbles,
  MonthlyBars,
  type ComparisonMonthlyPoint,
  type ComparisonSeasonPoint,
} from '@/components/dashboard/season-comparison-charts';

type Setting = 'all' | 'match' | 'training';
type Kpi = SeasonComparisonData['kpis'][number];
type ImpactRow = SeasonComparisonData['impact'][number];
type DiagnosisRow = SeasonComparisonData['diagnoses'][number];
type DiagnosisValue = DiagnosisRow['previous'][number];
type DiagnosisMetric = 'count' | 'incidence' | 'burden';

const SETTINGS: Setting[] = ['all', 'match', 'training'];
const SETTING_LABELS: Record<Setting, string> = {
  all: 'Overall',
  match: 'Match',
  training: 'Training',
};
const KPI_LABELS: Record<Kpi['key'], string> = {
  time_loss_incidence: 'TL Injury Incidence',
  mean_severity: 'Mean Severity',
  injury_burden: 'Injury Burden',
  time_loss_injuries: 'Time-Loss Injuries',
};
const KPI_UNITS: Record<Kpi['key'], string> = {
  time_loss_incidence: '/1,000 h',
  mean_severity: 'days',
  injury_burden: 'days/1,000 h',
  time_loss_injuries: 'injuries',
};
const SEASON_STYLES = [
  { dot: 'bg-blue-400', text: 'text-blue-300', surface: 'bg-blue-400/[0.06]' },
  { dot: 'bg-cyan-300', text: 'text-cyan-200', surface: 'bg-cyan-300/[0.06]' },
] as const;
const SEASON_BAR_COLOURS = ['hsl(var(--chart-3))', 'hsl(var(--chart-1))'] as const;
const DIAGNOSIS_METRICS: Array<{ value: DiagnosisMetric; label: string }> = [
  { value: 'count', label: 'Count' },
  { value: 'incidence', label: 'Incidence' },
  { value: 'burden', label: 'Burden' },
];
const DIAGNOSIS_METRIC_UNITS: Record<DiagnosisMetric, string> = {
  count: 'Injuries',
  incidence: '/1,000 h',
  burden: 'days/1,000 h',
};
const SECTION_HEADING_CLASS = 'text-2xl font-semibold tracking-tight text-foreground sm:text-3xl';
const PANEL_HEADING_CLASS = 'text-lg font-semibold leading-snug text-foreground';

function format(value: number | null | undefined, digits = 1): string {
  if (value === null || value === undefined || !Number.isFinite(value)) return 'Not available';
  return new Intl.NumberFormat('en-IE', {
    minimumFractionDigits: digits,
    maximumFractionDigits: digits,
  }).format(value);
}

function formatPercent(value: number | null): string {
  if (value === null || !Number.isFinite(value)) return 'Not comparable';
  return `${format(Math.abs(value), 1)}%`;
}

function improvementState(value: number | null): 'favourable' | 'adverse' | 'neutral' | 'unavailable' {
  if (value === null || !Number.isFinite(value)) return 'unavailable';
  if (value > 0) return 'favourable';
  if (value < 0) return 'adverse';
  return 'neutral';
}

function Panel({ title, children }: { title: string; children: ReactNode }) {
  return (
    <Card className="min-w-0 border-border/70 bg-card/70 shadow-none">
      <CardContent className="p-4 sm:p-5">
        <h3 className={`mb-4 ${PANEL_HEADING_CLASS}`}>{title}</h3>
        {children}
      </CardContent>
    </Card>
  );
}

function EmptyState({ children }: { children: ReactNode }) {
  return <div className="grid min-h-32 place-items-center rounded-md border border-dashed border-border p-5 text-center text-sm text-muted-foreground">{children}</div>;
}

function KpiTile({ metric }: { metric: Kpi }) {
  const improvement = metric.outcome_improvement_percent;
  const state = improvementState(improvement);
  const direction = state === 'favourable'
    ? 'Improved'
    : state === 'adverse'
      ? 'Increased'
      : state === 'neutral'
        ? 'No Change'
        : 'Not comparable';
  const stateClass = state === 'favourable'
    ? 'text-emerald-300'
    : state === 'adverse'
      ? 'text-red-300'
      : 'text-muted-foreground';
  const DirectionIcon = state === 'favourable' ? ArrowUp : state === 'adverse' ? ArrowDown : Minus;
  const digits = metric.key === 'time_loss_injuries' ? 0 : metric.key === 'injury_burden' ? 0 : 1;
  return (
    <Card className="min-w-0 border-border/70 bg-card/70 shadow-none">
      <CardContent className="p-4 sm:p-5">
        <p className="text-xs font-semibold text-muted-foreground">{KPI_LABELS[metric.key]}</p>
        <div className={`mt-2 flex items-center gap-1.5 ${stateClass}`} aria-label={`${direction} by ${formatPercent(improvement)}`}>
          <DirectionIcon className="h-6 w-6" strokeWidth={2.5} aria-hidden="true" />
          <span className="text-3xl font-bold leading-none tracking-tight tabular-nums sm:text-4xl">{formatPercent(improvement)}</span>
        </div>
        <p className={`mt-1 text-xs font-semibold ${stateClass}`}>{direction}</p>
        <div className="mt-4 grid grid-cols-2 border-t border-border/60 pt-3">
          {[metric.previous, metric.current].map((season, index) => (
            <div key={index} className={`min-w-0 ${index === 0 ? 'pr-2' : 'border-l border-border/60 pl-3'}`}>
              <p className={`flex items-center gap-1.5 text-[10px] font-semibold ${SEASON_STYLES[index].text}`}>
                <span className={`h-1.5 w-1.5 rounded-full ${SEASON_STYLES[index].dot}`} aria-hidden="true" />
                {index === 0 ? '2024-25' : '2025-26'}
              </p>
              <p className="mt-1 text-sm font-semibold leading-tight tabular-nums text-foreground">
                {format(season.value, digits)} <span className="text-[10px] font-normal text-muted-foreground">{KPI_UNITS[metric.key]}</span>
              </p>
            </div>
          ))}
        </div>
      </CardContent>
    </Card>
  );
}

function impactPoints(row: ImpactRow): ComparisonSeasonPoint[] {
  const values: Array<[ImpactRow['previous'], string]> = [
    [row.previous, '2024-25'],
    [row.current, '2025-26'],
  ];
  return values.map(([value, season]) => ({
    season,
    exposureHours: value.exposure_hours,
    timeLossInjuries: value.time_loss_injuries,
    incidence: value.time_loss_incidence_per_1000h,
    severity: value.mean_severity_days,
    burden: value.burden_per_1000h,
  }));
}

function monthlyPoints(data: SeasonComparisonData): ComparisonMonthlyPoint[] {
  return data.monthly.map((row) => ({
    month: row.label,
    prior: row.previous_time_loss_injuries,
    current: row.current_time_loss_injuries,
  }));
}

function diagnosisValue(value: DiagnosisValue | undefined, season: string, rank: number) {
  return {
    season,
    rank,
    diagnosis: value?.diagnosis ?? null,
    count: value?.time_loss_injuries ?? null,
    incidence: value?.incidence_per_1000h ?? null,
    burden: value?.burden_per_1000h ?? null,
  };
}

function diagnosisPoints(data: SeasonComparisonData) {
  return data.diagnoses.map((row) => ({
    setting: row.setting,
    ranks: [1, 2, 3].map((rank) => ({
      rank,
      seasons: [
        diagnosisValue(row.previous.find((value) => value.rank === rank), data.previous_season, rank),
        diagnosisValue(row.current.find((value) => value.rank === rank), data.current_season, rank),
      ],
    })),
  }));
}

function diagnosisColourMap(rows: ReturnType<typeof diagnosisPoints>) {
  const diagnoses = [...new Set(rows.flatMap((row) => row.ranks.flatMap((rank) => (
    rank.seasons.map((season) => season.diagnosis)
  ))).filter((diagnosis): diagnosis is string => Boolean(diagnosis)))].sort((a, b) => a.localeCompare(b));
  return new Map(diagnoses.map((diagnosis, index) => [
    diagnosis,
    `hsl(${Math.round((index * 137.508 + 218) % 360)} 72% 72%)`,
  ]));
}

function diagnosisMetricValue(
  season: ReturnType<typeof diagnosisValue>,
  metric: DiagnosisMetric,
): number | null {
  return season[metric];
}

function diagnosisMetricFormat(value: number | null, metric: DiagnosisMetric): string {
  if (value === null || !Number.isFinite(value)) return 'N/A';
  return format(value, metric === 'incidence' ? 2 : 0);
}

function DiagnosisDrivers({ data }: { data: SeasonComparisonData }) {
  const [metric, setMetric] = useState<DiagnosisMetric>('count');
  const rows = diagnosisPoints(data);
  const diagnosisColours = diagnosisColourMap(rows);
  const values = rows.flatMap((row) => row.ranks.flatMap((rank) => (
    rank.seasons.map((season) => diagnosisMetricValue(season, metric))
  )))
    .filter((value): value is number => value !== null && Number.isFinite(value));
  const max = Math.max(...values, 0);
  const barWidth = (value: number | null) => `${max > 0 && value !== null
    ? Math.max((value / max) * 100, value > 0 ? 2 : 0)
    : 0}%`;

  return (
    <Card className="min-w-0 border-border/70 bg-card/70 shadow-none">
      <CardContent className="p-4 sm:p-5">
        <div className="mb-5 flex flex-wrap items-center justify-between gap-3">
          <h3 className={PANEL_HEADING_CLASS}>Diagnosis Drivers</h3>
          <Tabs value={metric} onValueChange={(value) => setMetric(value as DiagnosisMetric)}>
            <TabsList aria-label="Diagnosis measure" className="h-auto bg-muted/80 p-1">
              {DIAGNOSIS_METRICS.map((item) => (
                <TabsTrigger key={item.value} value={item.value} className="min-h-9 px-3 text-xs">
                  {item.label}
                </TabsTrigger>
              ))}
            </TabsList>
          </Tabs>
        </div>

        <div className="overflow-x-auto">
          <div className="min-w-[280px]">
            <div className="mb-3 grid grid-cols-[2.5rem_minmax(0,1fr)_4.5rem_minmax(0,1fr)_2.5rem] items-center gap-1.5 text-[10px] font-semibold sm:grid-cols-[3.5rem_minmax(0,1fr)_6rem_minmax(0,1fr)_3.5rem] sm:gap-2">
              <span />
              <span className={`flex items-center justify-end gap-1.5 ${SEASON_STYLES[0].text}`}>
                {data.previous_season}
                <span className={`h-2 w-2 shrink-0 rounded-full ${SEASON_STYLES[0].dot}`} aria-hidden="true" />
              </span>
              <span className="text-center text-[9px] font-medium leading-tight text-muted-foreground">
                {DIAGNOSIS_METRIC_UNITS[metric]}
              </span>
              <span className={`flex items-center gap-1.5 ${SEASON_STYLES[1].text}`}>
                <span className={`h-2 w-2 shrink-0 rounded-full ${SEASON_STYLES[1].dot}`} aria-hidden="true" />
                {data.current_season}
              </span>
              <span />
            </div>

            <ul className="space-y-5">
              {SETTINGS.map((setting) => {
                const row = rows.find((item) => item.setting === setting);
                return (
                  <li
                    key={setting}
                    className="rounded-lg border border-border/55 bg-muted/[0.14] px-1.5 pb-2.5 pt-2 sm:px-2.5"
                  >
                    <p className="mb-2 text-center text-xs font-semibold uppercase tracking-[0.12em] text-foreground">
                      {SETTING_LABELS[setting]}
                    </p>
                    <ol className="space-y-2.5">
                      {(row?.ranks ?? []).map((rankRow) => {
                        const previous = rankRow.seasons[0];
                        const current = rankRow.seasons[1];
                        const previousValue = diagnosisMetricValue(previous, metric);
                        const currentValue = diagnosisMetricValue(current, metric);
                        const previousColour = previous.diagnosis
                          ? diagnosisColours.get(previous.diagnosis)
                          : 'hsl(var(--muted-foreground))';
                        const currentColour = current.diagnosis
                          ? diagnosisColours.get(current.diagnosis)
                          : 'hsl(var(--muted-foreground))';
                        return (
                          <li
                            key={rankRow.rank}
                            className="grid min-h-14 grid-cols-[2.5rem_minmax(0,1fr)_2rem_minmax(0,1fr)_2.5rem] items-end gap-1.5 sm:grid-cols-[3.5rem_minmax(0,1fr)_2.5rem_minmax(0,1fr)_3.5rem] sm:gap-2"
                          >
                            <span className="pb-0.5 text-left text-[11px] tabular-nums text-muted-foreground">
                              {diagnosisMetricFormat(previousValue, metric)}
                            </span>
                            <span className="min-w-0">
                              <span className="mb-1 flex min-h-6 min-w-0 items-end justify-end gap-1 text-right text-[10px] font-medium leading-tight text-foreground sm:text-xs">
                                <span className="min-w-0 break-words [overflow-wrap:anywhere]">{previous.diagnosis ?? 'Not Available'}</span>
                                <span className="mb-0.5 h-2 w-2 shrink-0 rounded-sm" style={{ backgroundColor: previousColour }} />
                              </span>
                              <span className="flex h-3 justify-end overflow-hidden rounded-sm bg-muted/60">
                                <span className="block h-full rounded-sm" style={{ width: barWidth(previousValue), backgroundColor: SEASON_BAR_COLOURS[0] }} />
                              </span>
                            </span>
                            <span className="pb-0.5 text-center text-[10px] font-semibold tabular-nums text-muted-foreground sm:text-xs">
                              #{rankRow.rank}
                            </span>
                            <span className="min-w-0">
                              <span className="mb-1 flex min-h-6 min-w-0 items-end gap-1 text-left text-[10px] font-medium leading-tight text-foreground sm:text-xs">
                                <span className="mb-0.5 h-2 w-2 shrink-0 rounded-sm" style={{ backgroundColor: currentColour }} />
                                <span className="min-w-0 break-words [overflow-wrap:anywhere]">{current.diagnosis ?? 'Not Available'}</span>
                              </span>
                              <span className="flex h-3 justify-start overflow-hidden rounded-sm bg-muted/60">
                                <span className="block h-full rounded-sm" style={{ width: barWidth(currentValue), backgroundColor: SEASON_BAR_COLOURS[1] }} />
                              </span>
                            </span>
                            <span className="pb-0.5 text-right text-[11px] tabular-nums text-muted-foreground">
                              {diagnosisMetricFormat(currentValue, metric)}
                            </span>
                          </li>
                        );
                      })}
                    </ol>
                  </li>
                );
              })}
            </ul>
          </div>
        </div>
      </CardContent>
    </Card>
  );
}

export function SeasonComparison({ comparison }: { comparison?: SeasonComparisonData }) {
  const [setting, setSetting] = useState<Setting>('all');
  if (!comparison) {
    return <EmptyState>No approved season comparison is available for this dashboard.</EmptyState>;
  }
  const impact = comparison.impact.find((row) => row.setting === setting);
  const qualifications = [comparison.exposure.previous.qualification, comparison.exposure.current.qualification]
    .filter((value): value is string => Boolean(value));
  const uniqueQualifications = [...new Set(qualifications)];

  return (
    <div className="space-y-5">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <h2 className={SECTION_HEADING_CLASS}>Season Comparison</h2>
        <div className="flex items-center gap-4 text-xs font-semibold" aria-label="Season colours">
          {[comparison.previous_season, comparison.current_season].map((season, index) => (
            <span key={season} className={`flex items-center gap-1.5 ${SEASON_STYLES[index].text}`}>
              <span className={`h-2.5 w-2.5 rounded-full ${SEASON_STYLES[index].dot}`} aria-hidden="true" />
              {season}
            </span>
          ))}
        </div>
      </div>

      {uniqueQualifications.length > 0 && (
        <div role="note" className="flex flex-wrap gap-x-2 rounded-md border border-amber-400/50 bg-amber-950/30 px-3 py-2 text-xs text-amber-100">
          {uniqueQualifications.map((qualification) => <p key={qualification}>{qualification}</p>)}
        </div>
      )}

      <Tabs value={setting} onValueChange={(value) => setSetting(value as Setting)}>
        <TabsList aria-label="Rugby setting" className="h-auto bg-muted/80 p-1">
          {SETTINGS.map((item) => (
            <TabsTrigger key={item} value={item} className="min-h-10 px-5">{SETTING_LABELS[item]}</TabsTrigger>
          ))}
        </TabsList>
      </Tabs>

      <section aria-label="Season change KPIs" className="grid gap-3 sm:grid-cols-2 xl:grid-cols-4">
        {comparison.kpis.map((metric) => <KpiTile key={metric.key} metric={metric} />)}
      </section>

      <Panel title="Injury Impact By Season">
        {impact ? <ImpactBubbles seasons={impactPoints(impact)} /> : <EmptyState>No approved injury-impact values are available for this setting.</EmptyState>}
      </Panel>

      <Panel title="Time-Loss Injuries By Month">
        <MonthlyBars monthly={monthlyPoints(comparison)} />
      </Panel>

      <DiagnosisDrivers data={comparison} />
    </div>
  );
}

export default SeasonComparison;
