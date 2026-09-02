import type { MonthlySettingRow } from './reporting-types';

/** Use an existing rate, otherwise calculate it from that month's released count and hours. */
export function monthlyIncidence(count: number | null | undefined, hours: number | null | undefined, releasedRate: number | null | undefined) {
  return releasedRate ?? (count != null && hours != null && hours > 0 ? count / hours * 1000 : null);
}

export function buildSeasonTimelineRows(rows: readonly MonthlySettingRow[]): MonthlySettingRow[] {
  return rows.map((row) => ({
    ...row,
    overall_incidence_per_1000h: monthlyIncidence(row.recorded_injuries, row.exposure_hours, row.overall_incidence_per_1000h),
    incidence_per_1000h: monthlyIncidence(row.time_loss_injuries, row.exposure_hours, row.incidence_per_1000h),
  }));
}
