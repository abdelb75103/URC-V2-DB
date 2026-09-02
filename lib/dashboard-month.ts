const MONTHS = ['jan', 'feb', 'mar', 'apr', 'may', 'jun', 'jul', 'aug', 'sep', 'oct', 'nov', 'dec'];

/** Both approved readers use calendar months, encoded as Sep 2024 or 2025-09. */
export function monthIndex(value: string) {
  const iso = /^\d{4}-(\d{2})$/.exec(value.trim());
  if (iso) {
    const month = Number(iso[1]) - 1;
    return month >= 0 && month < 12 ? month : -1;
  }
  return MONTHS.indexOf(value.trim().slice(0, 3).toLowerCase());
}

export function monthOrder(value: string) {
  const month = monthIndex(value);
  const year = value.match(/\d{4}/)?.[0];
  return month < 0 || !year ? null : Number(year) * 12 + month;
}

export function sortSeasonMonths<T extends { month: string }>(rows: readonly T[]) {
  return [...rows].sort((a, b) => {
    const left = monthOrder(a.month), right = monthOrder(b.month);
    return left !== null && right !== null ? left - right : a.month.localeCompare(b.month);
  });
}
