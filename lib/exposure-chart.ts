export type ExposureChartMeasure = 'hours' | 'distance' | 'hsr';

type ExposureChartRow = {
  exposure_hours?: number | null;
  distance_km?: number | null;
  actual_hsr_distance_km?: number | null;
  hsr_distance_km?: number | null;
  hsr_percentage?: number | null;
  is_imputed?: boolean;
  exposure_contributor_count?: number;
  distance_contributor_count?: number;
};

const MONTHS = [
  ['Jan', 'January'], ['Feb', 'February'], ['Mar', 'March'], ['Apr', 'April'],
  ['May', 'May'], ['Jun', 'June'], ['Jul', 'July'], ['Aug', 'August'],
  ['Sep', 'September'], ['Oct', 'October'], ['Nov', 'November'], ['Dec', 'December'],
] as const;

export function hasReportedExposureValue(row: ExposureChartRow, measure: ExposureChartMeasure) {
  const value = measure === 'hours'
    ? row.exposure_hours
    : measure === 'distance'
      ? row.distance_km
      : row.hsr_distance_km;
  return typeof value === 'number';
}

export function contributingClubsText(row: ExposureChartRow, measure: ExposureChartMeasure) {
  const count = measure === 'hours'
    ? row.exposure_contributor_count
    : measure === 'distance'
      ? row.distance_contributor_count
      : undefined;
  return typeof count === 'number' ? `${count} of 16 clubs` : null;
}

export function exposureMonthLabel(value: string, short = false) {
  const normalized = value.trim();
  const monthIndex = /^\d{4}-(\d{2})$/.exec(normalized)?.[1];
  const index = monthIndex ? Number(monthIndex) - 1 : MONTHS.findIndex(([label]) => (
    normalized.toLowerCase().startsWith(label.toLowerCase())
  ));
  if (index < 0 || index >= MONTHS.length) return normalized;
  return MONTHS[index][short ? 0 : 1];
}

export function showExposureMonthLabel(index: number, compact: boolean) {
  return !compact || index % 2 === 0;
}

export function hsrPercentage(row: ExposureChartRow) {
  return typeof row.hsr_percentage === 'number' && Number.isFinite(row.hsr_percentage)
    ? row.hsr_percentage
    : null;
}

export function hsrStatusLabel(row: ExposureChartRow) {
  if (row.is_imputed) return 'League-mean placeholder';
  return typeof row.actual_hsr_distance_km === 'number'
    ? 'Actual source data'
    : 'HSR not available';
}
