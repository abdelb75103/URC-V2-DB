'use client';

import Image from 'next/image';
import Link from 'next/link';
import { ArrowLeft, Info } from 'lucide-react';
import type { TeamDashboardData } from '@/lib/reporting';
import { Card, CardContent } from '@/components/ui/card';
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs';
import { KpiCard } from '@/components/dashboard/kpi-card';
import { TimeSeriesBars, RankedBars } from '@/components/dashboard/charts';

function fmt(value: number | null | undefined, digits = 1) {
  if (value === null || value === undefined || Number.isNaN(value)) return 'Pending';
  return new Intl.NumberFormat('en-IE', {
    maximumFractionDigits: digits,
    minimumFractionDigits: Number.isInteger(value) ? 0 : digits,
  }).format(value);
}

function Panel({
  title,
  description,
  unit,
  children,
}: {
  title: string;
  description?: string;
  unit?: string;
  children: React.ReactNode;
}) {
  return (
    <Card>
      <CardContent className="p-5">
        <div className="mb-4 flex items-start justify-between gap-4">
          <div>
            <h3 className="text-base font-semibold text-foreground">{title}</h3>
            {description && <p className="mt-0.5 text-xs text-muted-foreground">{description}</p>}
          </div>
          {unit && (
            <span className="shrink-0 rounded-full bg-muted/40 px-2 py-0.5 text-[11px] text-muted-foreground">
              {unit}
            </span>
          )}
        </div>
        {children}
      </CardContent>
    </Card>
  );
}

function PendingNote({ children }: { children: React.ReactNode }) {
  return (
    <div className="flex items-start gap-2 rounded-lg border border-dashed border-border/70 bg-background/40 p-4 text-sm text-muted-foreground">
      <Info className="mt-0.5 h-4 w-4 shrink-0 text-primary/70" />
      <p className="leading-relaxed">{children}</p>
    </div>
  );
}

const TAB_HEADINGS: Record<string, { title: string; blurb: string }> = {
  overview: {
    title: 'Team Overview',
    blurb: 'Validated aggregate results for the accepted team coverage window.',
  },
  'common-injuries': {
    title: 'Most Common Injuries & Illnesses',
    blurb: 'Ranked injury burden by body area and injury type from the cleaned dataset.',
  },
  location: {
    title: 'Injury by Location',
    blurb: 'Time-loss injuries, incidence and burden grouped by IOC-aligned body location.',
  },
  'type-tissue': {
    title: 'Injury by Type & Tissue',
    blurb: 'Time-loss injuries, incidence and burden grouped by injury type / pathology.',
  },
  exposure: {
    title: 'Exposure',
    blurb: 'Included exposure aggregated to the reporting month.',
  },
};

export function TeamDashboard({
  dashboard,
  crest,
  teamName,
}: {
  dashboard: TeamDashboardData;
  crest: string;
  teamName: string;
}) {
  const headline = Object.fromEntries(dashboard.headline.map((m) => [m.key, m]));
  const val = (k: string) => headline[k]?.value;
  const medicalAttention = dashboard.severity_distribution.find(
    (r) => r.key === 'zero_days_medical_attention_only'
  )?.recorded_injuries;
  const daysLost = dashboard.setting_split.reduce((s, r) => s + r.days_lost, 0);
  const unknownSeverity = dashboard.severity_distribution.find(
    (r) => r.key === 'unknown_or_censored'
  )?.recorded_injuries;
  const exposureGrain = dashboard.coverage.exposure_grain ?? (dashboard.coverage.weeks > 0 ? 'weekly' : 'unknown');
  const exposurePeriodLabel = exposureGrain === 'weekly' ? 'Reporting weeks' : 'Exposure periods';
  const exposurePeriods = dashboard.coverage.exposure_periods ?? dashboard.coverage.weeks;

  const tabs = ['overview', 'common-injuries', 'location', 'type-tissue', 'exposure'];

  return (
    <div className="mx-auto w-full max-w-7xl px-4 pb-16 pt-6 sm:px-6 lg:px-8">
      {/* Header */}
      <Link
        href="/"
        className="mb-4 inline-flex items-center gap-2 text-sm text-muted-foreground transition-colors hover:text-primary"
      >
        <ArrowLeft className="h-4 w-4" />
        Back to dashboards
      </Link>

      <div className="mb-6 flex items-center gap-4">
        <div className="relative h-16 w-16 shrink-0">
          <Image src={crest} alt={`${teamName} crest`} fill sizes="64px" className="object-contain" />
        </div>
        <div>
          <h1 className="text-2xl font-bold text-foreground sm:text-3xl">{teamName} Dashboard</h1>
          <p className="text-sm text-muted-foreground">
            {`${dashboard.season} injury & exposure surveillance`}
          </p>
        </div>
      </div>

      <Tabs defaultValue="overview">
        <div className="-mx-4 overflow-x-auto px-4 sm:mx-0 sm:px-0">
          <TabsList className="mb-6 inline-flex w-auto">
            {tabs.map((t) => (
              <TabsTrigger key={t} value={t} className="whitespace-nowrap">
                {TAB_HEADINGS[t].title.replace('Most Common Injuries & Illnesses', 'Common Injuries')}
              </TabsTrigger>
            ))}
          </TabsList>
        </div>

        {tabs.map((t) => (
          <TabsContent key={t} value={t}>
            <div className="mb-5">
              <h2 className="text-xl font-semibold text-foreground">{TAB_HEADINGS[t].title}</h2>
              <p className="text-sm text-muted-foreground">{TAB_HEADINGS[t].blurb}</p>
            </div>

            {t === 'overview' && (
              <div className="space-y-6">
                {/* KPI grid */}
                <div className="grid grid-cols-2 gap-3 md:grid-cols-3 xl:grid-cols-6">
                  <KpiCard label="Recorded injuries" value={fmt(val('recorded_injuries'), 0)} unit="in coverage window" emphasis />
                  <KpiCard label="Time-loss injuries" value={fmt(val('time_loss_injuries'), 0)} unit="days injured > 0" />
                  <KpiCard label="Medical-attention only" value={fmt(medicalAttention, 0)} unit="0 days lost" />
                  <KpiCard label="Incidence" value={fmt(val('incidence_per_1000h'))} unit="per 1,000 player-hours" />
                  <KpiCard label="Burden" value={fmt(val('burden_per_1000h'))} unit="days per 1,000 player-hours" />
                  <KpiCard label="Mean severity" value={fmt(val('severity_mean_days'))} unit="days lost per injury" />
                </div>

                {/* Coverage strip */}
                <div className="grid grid-cols-2 gap-3 rounded-xl border border-border/60 bg-card/60 p-4 text-center sm:grid-cols-5">
                  {[
                    ['Player-hours', fmt(dashboard.coverage.hours)],
                    ['Exposed players', fmt(dashboard.coverage.exposed_players, 0)],
                    [exposurePeriodLabel, fmt(exposurePeriods, 0)],
                    ['Days lost', fmt(daysLost, 0)],
                    ['Window', `${dashboard.analysis_window.start} → ${dashboard.analysis_window.end}`],
                  ].map(([k, v]) => (
                    <div key={k}>
                      <dt className="text-[11px] uppercase tracking-wide text-muted-foreground">{k}</dt>
                      <dd className="mt-1 text-sm font-semibold text-foreground">{v}</dd>
                    </div>
                  ))}
                </div>

                <Panel
                  title="Time-Loss Injuries by Month"
                  description="Injuries with more than zero days lost, grouped by injury month."
                  unit="Count"
                >
                  <TimeSeriesBars data={dashboard.monthly} xKey="month" yKey="time_loss_injuries" unit="injuries" />
                </Panel>

                <div className="grid gap-6 lg:grid-cols-2">
                  <Panel title="Incidence by Month" description="Time-loss injuries per 1,000 all-activity player-hours." unit="Per 1,000h">
                    <TimeSeriesBars data={dashboard.monthly} xKey="month" yKey="incidence_per_1000h" unit="per 1,000h" color="hsl(var(--chart-2))" />
                  </Panel>
                  <Panel title="Burden by Month" description="Days lost per 1,000 all-activity player-hours." unit="Days per 1,000h">
                    <TimeSeriesBars data={dashboard.monthly} xKey="month" yKey="burden_per_1000h" unit="days per 1,000h" color="hsl(var(--chart-4))" />
                  </Panel>
                </div>

                <Panel
                  title="Severity of Recorded Injuries"
                  description="IOC-aligned distribution by days lost, including unknown or censored records."
                  unit="Recorded injuries"
                >
                  <RankedBars data={dashboard.severity_distribution} labelKey="label" valueKey="recorded_injuries" unit="injuries" />
                  <div className="mt-4 grid grid-cols-3 gap-3 border-t border-border/60 pt-4 text-center">
                    <div><p className="text-xs text-muted-foreground">Mean severity</p><p className="font-semibold text-foreground">{fmt(val('severity_mean_days'))} days</p></div>
                    <div><p className="text-xs text-muted-foreground">Median severity</p><p className="font-semibold text-foreground">{fmt(val('severity_median_days'), 0)} days</p></div>
                    <div><p className="text-xs text-muted-foreground">Unknown / censored</p><p className="font-semibold text-foreground">{fmt(unknownSeverity, 0)} records</p></div>
                  </div>
                </Panel>

                <div className="grid gap-6 lg:grid-cols-2">
                  <Panel title="Injuries by Setting" description="Counts and days lost only. Setting-specific rates are not calculated for weekly reporters.">
                    <div className="space-y-2">
                      {dashboard.setting_split.map((r) => (
                        <div key={r.label} className="flex items-center justify-between rounded-lg bg-background/40 px-3 py-2 text-sm">
                          <span className="font-medium capitalize text-foreground">{r.label}</span>
                          <span className="text-muted-foreground"><strong className="text-foreground">{r.time_loss_injuries}</strong> injuries</span>
                          <span className="text-muted-foreground"><strong className="text-foreground">{fmt(r.days_lost, 0)}</strong> days</span>
                        </div>
                      ))}
                    </div>
                  </Panel>
                  <Panel title="Prior-Season Comparison" description="A comparable prior-season denominator has not passed the V2 workflow.">
                    <PendingNote>
                      <strong className="text-foreground">{dashboard.prior_season.season}: </strong>
                      {dashboard.prior_season.note}
                    </PendingNote>
                  </Panel>
                </div>

                <Panel title="Calculation basis & limitations">
                  <ul className="space-y-2 text-sm text-muted-foreground">
                    {dashboard.method.map((m) => (
                      <li key={m} className="flex gap-2"><span className="text-primary">•</span>{m}</li>
                    ))}
                  </ul>
                  {dashboard.limitations?.length > 0 && (
                    <div className="mt-4 space-y-2 border-t border-border/60 pt-4">
                      {dashboard.limitations.map((l) => (
                        <PendingNote key={l}>{l}</PendingNote>
                      ))}
                    </div>
                  )}
                </Panel>
              </div>
            )}

            {t === 'common-injuries' && (
              <div className="space-y-6">
                <div className="grid gap-6 lg:grid-cols-2">
                  <Panel title="Top Body Areas" description="By time-loss injury count." unit="Time-loss injuries">
                    <RankedBars data={dashboard.body_locations} labelKey="label" valueKey="time_loss_injuries" unit="injuries" />
                  </Panel>
                  <Panel title="Top Injury Types" description="By time-loss injury count." unit="Time-loss injuries">
                    <RankedBars data={dashboard.injury_types} labelKey="label" valueKey="time_loss_injuries" unit="injuries" />
                  </Panel>
                </div>
                <Panel title="Illness surveillance">
                  <PendingNote>
                    Illness records are not part of the accepted {teamName} V2 aggregate yet. This section
                    unlocks once an illness case definition and cleared illness dataset pass the V2 workflow.
                  </PendingNote>
                </Panel>
              </div>
            )}

            {t === 'location' && (
              <BreakdownTable rows={dashboard.body_locations} title="Injuries by Body Location" />
            )}

            {t === 'type-tissue' && (
              <BreakdownTable rows={dashboard.injury_types} title="Injuries by Type / Tissue" />
            )}

            {t === 'exposure' && (
              <div className="space-y-6">
                <div className="grid grid-cols-2 gap-3 md:grid-cols-4">
                  <KpiCard label="Player-hours" value={fmt(dashboard.coverage.hours)} unit="all-activity" emphasis />
                  <KpiCard label="Distance" value={fmt(dashboard.coverage.distance_km)} unit="km (GPS total)" />
                  <KpiCard label="Exposed players" value={fmt(dashboard.coverage.exposed_players, 0)} />
                  <KpiCard label="Reporting weeks" value={fmt(dashboard.coverage.weeks, 0)} />
                </div>
                <Panel title="Exposure Hours by Month" description="Sum of cleaned weekly minutes / 60, assigned to the week-start month." unit="Player-hours">
                  <TimeSeriesBars data={dashboard.monthly} xKey="month" yKey="exposure_hours" unit="hours" color="hsl(var(--chart-3))" />
                </Panel>
                <Panel title="Distance by Month" description="GPS-derived total distance for included weekly exposure rows." unit="km">
                  <TimeSeriesBars data={dashboard.monthly} xKey="month" yKey="distance_km" unit="km" color="hsl(var(--chart-2))" />
                </Panel>
                <PendingNote>
                  {exposureGrain === 'weekly'
                    ? `${teamName} reports exposure weekly, so match and training exposure cannot be split until setting-specific denominators are approved. Daily observations are not fabricated from weekly totals.`
                    : 'Setting-specific exposure is not split until setting-specific denominators are approved.'}
                </PendingNote>
              </div>
            )}
          </TabsContent>
        ))}
      </Tabs>
    </div>
  );
}

function BreakdownTable({
  rows,
  title,
}: {
  rows: TeamDashboardData['body_locations'];
  title: string;
}) {
  return (
    <div className="space-y-6">
      <Panel title={title} unit="Time-loss injuries">
        <RankedBars data={rows} labelKey="label" valueKey="time_loss_injuries" unit="injuries" />
      </Panel>
      <Panel title="Detail" description="Incidence and burden per 1,000 player-hours; mean severity in days lost.">
        <div className="overflow-x-auto">
          <table className="w-full min-w-[520px] text-sm">
            <thead>
              <tr className="border-b border-border/60 text-left text-xs uppercase tracking-wide text-muted-foreground">
                <th className="py-2 pr-4 font-medium">Category</th>
                <th className="py-2 pr-4 text-right font-medium">Injuries</th>
                <th className="py-2 pr-4 text-right font-medium">Days lost</th>
                <th className="py-2 pr-4 text-right font-medium">Incidence /1,000h</th>
                <th className="py-2 pr-4 text-right font-medium">Burden /1,000h</th>
                <th className="py-2 text-right font-medium">Mean severity</th>
              </tr>
            </thead>
            <tbody>
              {rows.map((r) => (
                <tr key={r.label} className="border-b border-border/40 last:border-0">
                  <td className="py-2 pr-4 font-medium text-foreground">{r.label}</td>
                  <td className="py-2 pr-4 text-right text-muted-foreground">{r.time_loss_injuries}</td>
                  <td className="py-2 pr-4 text-right text-muted-foreground">{r.days_lost}</td>
                  <td className="py-2 pr-4 text-right text-muted-foreground">{fmt(r.incidence_per_1000h)}</td>
                  <td className="py-2 pr-4 text-right text-muted-foreground">{fmt(r.burden_per_1000h)}</td>
                  <td className="py-2 text-right text-muted-foreground">{fmt(r.mean_severity_days)}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </Panel>
    </div>
  );
}
