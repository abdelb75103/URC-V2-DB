import { monthIndex } from './dashboard-month';
import type { MonthlySettingRow, PreliminaryMonthlyRateRow } from './reporting-types';

/** Use a released rate; team-only fallback is valid when its own count and hours align. */
export function monthlyIncidence(count: number | null | undefined, hours: number | null | undefined, releasedRate: number | null | undefined, allowFallback = true) {
  return releasedRate ?? (allowFallback && count != null && hours != null && hours > 0 ? count / hours * 1000 : null);
}

export function buildSeasonTimelineRows(
  rows: readonly MonthlySettingRow[],
  allowFallback = true,
  preliminaryRows: readonly PreliminaryMonthlyRateRow[] = [],
): MonthlySettingRow[] {
  const preliminaryByMonth = new Map(preliminaryRows.map((row) => [monthIndex(row.month), row]));
  return rows.map((row) => ({
    ...row,
    overall_incidence_per_1000h: monthlyIncidence(row.recorded_injuries, row.exposure_hours, row.overall_incidence_per_1000h, allowFallback),
    incidence_per_1000h: monthlyIncidence(
      row.time_loss_injuries,
      row.exposure_hours,
      row.incidence_per_1000h ?? preliminaryByMonth.get(monthIndex(row.month))?.incidence_per_1000h,
      allowFallback,
    ),
  }));
}
