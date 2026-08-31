export type ExposureChartMeasure = 'hours' | 'distance' | 'hsr';

type ExposureChartRow = {
  exposure_hours?: number | null;
  distance_km?: number | null;
  hsr_distance_km?: number | null;
  exposure_contributor_count?: number;
  distance_contributor_count?: number;
};

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
