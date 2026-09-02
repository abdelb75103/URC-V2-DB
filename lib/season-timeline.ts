import { monthOrder } from './dashboard-month';
import type { MonthlySettingRow, PreliminaryMonthlyRateRow } from './reporting-types';

export type SeasonTimelineRow = MonthlySettingRow & {
  preliminary_rate?: PreliminaryMonthlyRateRow;
};

export const PRELIMINARY_TIMELINE_NOTE = 'Time Loss Incidence uses preliminary contributor-aligned monthly data. Its numerator and exposure include only contributing clubs; the bars show the full injury cohort.';

/** Select a released rate without recalculating it against another cohort. */
export function timelineRate(month: string, officialRate: number | null | undefined, preliminary: readonly PreliminaryMonthlyRateRow[]) {
  if (officialRate != null) return { incidence: officialRate, preliminary: undefined };
  const key = monthOrder(month);
  const row = key === null ? undefined : preliminary.find((item) => monthOrder(item.month) === key);
  return { incidence: row?.incidence_per_1000h ?? null, preliminary: row };
}

export function buildSeasonTimelineRows(rows: readonly MonthlySettingRow[], preliminary: readonly PreliminaryMonthlyRateRow[]): SeasonTimelineRow[] {
  return rows.map((row) => {
    const rate = timelineRate(row.month, row.incidence_per_1000h, row.setting === 'all' ? preliminary : []);
    return { ...row, incidence_per_1000h: rate.incidence, ...(rate.preliminary ? { preliminary_rate: rate.preliminary } : {}) };
  });
}
