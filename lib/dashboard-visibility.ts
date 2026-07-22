type DashboardCategoryRow = {
  code?: string;
  key?: string;
  label?: string;
  setting?: string;
};

export function isFrontFacingUnknown(row: DashboardCategoryRow): boolean {
  const identifiers = [row.code, row.key]
    .filter((value): value is string => typeof value === 'string')
    .map((value) => value.trim().toLowerCase());
  const label = row.label?.trim() ?? '';

  return row.setting?.trim().toLowerCase() === 'unknown'
    || identifiers.some((value) => /(^|__)unknown(?:_|__|$)/.test(value))
    || /(^|[\s·/])unknown(?:\b|\s*\/)/i.test(label);
}

export function withoutFrontFacingUnknown<T extends DashboardCategoryRow>(rows: readonly T[]): T[] {
  return rows.filter((row) => !isFrontFacingUnknown(row));
}
