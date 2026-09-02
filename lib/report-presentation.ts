/**
 * Presentation values the PDF shares with the dashboard.
 *
 * The dashboard renders on dark navy, the PDF on white paper, so a few of the
 * dashboard's colours are recomputed here for a light background. Shared card
 * rankings select from released values without changing the source rows.
 *
 * The card palettes and the colour resolvers live here rather than in the
 * dashboard: `components/dashboard/team-dashboard.tsx` imports them from this
 * module, so the PDF and the dashboard cannot drift apart.
 */

export type CardColour = { background: string; foreground: string };

/** Regions with no cases, matched to the PDF's own rule colour rather than the dashboard's dark tint. */
export const NO_CASE_FILL = "#D7E2EA";

/** The dashboard risk matrix draws one series in this navy, with white numerals. */
export const MATRIX_DOT = "#173F52";

/** Impact-zone gradient stops from the dashboard risk matrix, lower-left to upper-right. */
export const RISK_ZONE_STOPS = [
  { offset: 0, colour: "#2FBF83" },
  { offset: 0.45, colour: "#D8CC55" },
  { offset: 0.72, colour: "#ED8B43" },
  { offset: 1, colour: "#DF4F52" },
] as const;

export function hslToHex(hue: number, saturation: number, lightness: number, alpha = 1, over: [number, number, number] = [1, 1, 1]): string {
  const s = saturation / 100, l = lightness / 100;
  const chroma = (1 - Math.abs(2 * l - 1)) * s;
  const second = chroma * (1 - Math.abs(((hue / 60) % 2) - 1));
  const base = l - chroma / 2;
  const sector = Math.floor(hue / 60) % 6;
  const [r, g, b] = ([
    [chroma, second, 0], [second, chroma, 0], [0, chroma, second],
    [0, second, chroma], [second, 0, chroma], [chroma, 0, second],
  ][sector] ?? [chroma, second, 0]).map((channel) => channel + base);
  // A translucent dashboard colour is composited here, because a PDF fill has no
  // backdrop to blend with: `over` is the colour it is blended against.
  const composite = (channel: number, index: number) => Math.round((channel * alpha + over[index] * (1 - alpha)) * 255);
  return `#${[r, g, b].map((channel, index) => composite(channel, index).toString(16).padStart(2, "0")).join("").toUpperCase()}`;
}

/** The dashboard's `color-mix(in srgb, <background> 90%, black)` card fill. */
export function cardFill(hex: string): string {
  const value = Number.parseInt(hex.slice(1), 16);
  return `#${[(value >> 16) & 255, (value >> 8) & 255, value & 255]
    .map((channel) => Math.round(channel * 0.9).toString(16).padStart(2, "0")).join("").toUpperCase()}`;
}

/** One colour per diagnosis in the season comparison, in the dashboard's order and formula. */
export function diagnosisColourMap(labels: ReadonlyArray<string | null | undefined>): Map<string, string> {
  const diagnoses = [...new Set(labels.filter((label): label is string => Boolean(label)))]
    .sort((a, b) => a.localeCompare(b));
  return new Map(diagnoses.map((diagnosis, index) => [
    diagnosis,
    hslToHex(Math.round((index * 137.508 + 218) % 360), 72, 72),
  ]));
}

/**
 * The dashboard's `locationHeatColor` ramp, continuous, composited for white
 * paper. Hue, saturation, lightness and alpha follow that function exactly.
 */
export function heatColour(value: number, max: number): string {
  if (!(value > 0)) return NO_CASE_FILL;
  const ratio = Math.min(Math.max(value / Math.max(1, max), 0), 1);
  return hslToHex(48 - ratio * 48, 92, 62 - ratio * 8, 0.55 + ratio * 0.45);
}

/** Five stops sampled off the continuous ramp, so print carries a readable key. */
export function heatScaleStops(max: number): Array<{ value: number; colour: string }> {
  const stops = new Map<number, string>();
  for (let step = 1; step <= 5; step += 1) {
    const value = Math.max(1, Math.ceil((max * step) / 5));
    if (value <= max) stops.set(value, heatColour(value, max));
  }
  return [...stops].map(([value, colour]) => ({ value, colour }));
}

/** Ink or white body text, whichever stays legible on a fill. */
export function readableOn(hex: string): string {
  const value = Number.parseInt(hex.slice(1), 16);
  const [r, g, b] = [(value >> 16) & 255, (value >> 8) & 255, value & 255].map((channel) => {
    const s = channel / 255;
    return s <= 0.03928 ? s / 12.92 : ((s + 0.055) / 1.055) ** 2.4;
  });
  return 0.2126 * r + 0.7152 * g + 0.0722 * b > 0.4 ? "#14233B" : "#FFFFFF";
}

export const REFERENCE_INJURY_COLORS: Record<string, CardColour> = {
  concussion: { background: '#e5252a', foreground: '#ffffff' },
  contusion_haematoma: { background: '#f59e0b', foreground: '#ffffff' },
  compound__thigh__contusion_superficial: { background: '#f59e0b', foreground: '#ffffff' },
  compound__knee__joint_sprain: { background: '#3b82f6', foreground: '#ffffff' },
  hamstring_strain: { background: '#9333ea', foreground: '#ffffff' },
  compound__thigh__muscle_injury: { background: '#9333ea', foreground: '#ffffff' },
  compound__ankle__joint_sprain: { background: '#16a34a', foreground: '#ffffff' },
  adductor_groin: { background: '#db2777', foreground: '#ffffff' },
  compound__knee__peripheral_nerve_injury: { background: '#db2777', foreground: '#ffffff' },
  calf_muscle: { background: '#f97316', foreground: '#ffffff' },
  compound__lower_leg__muscle_injury: { background: '#f97316', foreground: '#ffffff' },
  compound__shoulder__joint_sprain: { background: '#14b8a6', foreground: '#ffffff' },
  compound__shoulder__tendon_rupture: { background: '#06b6d4', foreground: '#ffffff' },
  compound__ankle__fracture: { background: '#0d9488', foreground: '#ffffff' },
  compound__lower_leg__fracture: { background: '#4f46e5', foreground: '#ffffff' },
  compound__wrist__fracture: { background: '#0ea5e9', foreground: '#ffffff' },
  compound__wrist__tendinopathy: { background: '#14b8a6', foreground: '#ffffff' },
  compound__shoulder__fracture: { background: '#eab308', foreground: '#ffffff' },
  compound__lumbosacral__synovitis_capsulitis: { background: '#65a30d', foreground: '#ffffff' },
  compound__lumbosacral__cartilage_injury: { background: '#84cc16', foreground: '#ffffff' },
  compound__lumbosacral__tendinopathy: { background: '#eab308', foreground: '#ffffff' },
  compound__lumbosacral__nonspecific: { background: '#c026d3', foreground: '#ffffff' },
  compound__forearm__fracture: { background: '#1e40af', foreground: '#ffffff' },
};

export const FALLBACK_INJURY_COLORS = [
  '#007d92',
  '#6d28d9',
  '#b56000',
  '#00759a',
  '#007a55',
  '#c94b00',
  '#4f46e5',
  '#007a78',
  '#c51b4a',
  '#075fc7',
  '#966b00',
  '#08783f',
  '#1e40af',
  '#7e22ce',
  '#be123c',
  '#007f6d',
  '#0369a1',
  '#5b21b6',
  '#b45309',
  '#0f766e',
  '#4338ca',
  '#0e7490',
  '#15803d',
  '#9f1239',
] as const;

/** Hue-spread so neighbouring illness cards never read as the same colour. */
export const ILLNESS_COLORS = [
  '#e5252a',
  '#0ea5e9',
  '#16a34a',
  '#9333ea',
  '#f59e0b',
  '#0f766e',
  '#db2777',
  '#4f46e5',
  '#84cc16',
  '#c2410c',
  '#06b6d4',
  '#be123c',
] as const;

export const RANKED_LANE_SIZE = 5;

/** The four ranked lanes, in the dashboard's order. */
const PROFILE_METRIC_KEYS = ['time_loss_injuries', 'incidence_per_1000h', 'burden_per_1000h', 'mean_severity_days'] as const;
const ILLNESS_METRIC_KEYS = ['recorded_illnesses', 'incidence_per_1000h', 'burden_per_1000h', 'mean_severity_days'] as const;

export function metricValue<T, K extends keyof T>(row: T, metric: K) {
  const value = row[metric];
  return typeof value === 'number' && Number.isFinite(value) ? value : 0;
}

/**
 * One ranked lane: the rows with a value for this metric, highest first. The
 * lanes, the colour map and the risk matrix all read their selection from here,
 * so they cannot drift apart when a sort changes.
 */
export function rankedForMetric<T extends { label: string }, K extends keyof T>(rows: readonly T[], metric: K) {
  return [...rows]
    .filter((row) => metricValue(row, metric) > 0)
    .sort((a, b) => metricValue(b, metric) - metricValue(a, metric) || a.label.localeCompare(b.label));
}

/** Presentation exclusions requested for the common-injury cards, across seasons. */
export function rankedCommonInjuries<T extends { label: string }, K extends keyof T>(rows: readonly T[], metric: K) {
  const eligible = rows.filter((row) => !/^(?:foot pain(?:$|\/)|medical illness$)/i.test(row.label.trim()));
  return rankedForMetric(eligible, metric).slice(0, RANKED_LANE_SIZE);
}

export function rankedIllnesses<T extends { label: string }>(rows: readonly T[], metric: (typeof ILLNESS_METRIC_KEYS)[number]) {
  return rankedForMetric(rows as ReadonlyArray<T & Record<string, unknown>>, metric).slice(0, RANKED_LANE_SIZE);
}

export function isKneeLigamentDiagnosis(row?: { code: string; label: string }) {
  if (!row) return false;
  const value = `${row.code} ${row.label}`.toLowerCase();
  return row.code.startsWith('dx_acl_')
    || row.code.startsWith('dx_mcl_')
    || row.code.startsWith('dx_pcl_')
    || value.includes('posterior cruciate ligament')
    || value.includes('knee cruciate ligament')
    || value.includes('knee ligament')
    || value.includes('knee multiligament')
    || value.includes('knee posterolateral corner')
    || row.label.toLowerCase() === 'lateral collateral ligament injury';
}

type ColourableProfileRow = {
  code: string;
  label: string;
  setting: string;
  time_loss_injuries?: number | null;
  incidence_per_1000h?: number | null;
  burden_per_1000h?: number | null;
  mean_severity_days?: number | null;
};

/** The codes on screen for one setting: the union of each metric's top five. */
function rankedLaneCodes<T extends ColourableProfileRow>(rows: readonly T[], setting: string) {
  const codes = new Set<string>();
  const scoped = rows.filter((row) => row.setting === setting);
  for (const metric of PROFILE_METRIC_KEYS) {
    for (const row of rankedCommonInjuries(scoped, metric)) codes.add(row.code);
  }
  return codes;
}

function hexColorDistance(a: string, b: string) {
  const channels = (color: string) => [1, 3, 5].map((index) => Number.parseInt(color.slice(index, index + 2), 16));
  const [ar, ag, ab] = channels(a);
  const [br, bg, bb] = channels(b);
  return Math.hypot(ar - br, ag - bg, ab - bb);
}

/**
 * One colour per diagnosis, shared by the dashboard lanes, the risk matrix and
 * the PDF. Reference colours are honoured first, then the remaining palette is
 * assigned to maximise separation between codes that appear together on screen.
 */
export function commonInjuryColorMap<T extends ColourableProfileRow>(rows: readonly T[]) {
  const codes: string[] = [];
  const seen = new Set<string>();
  const visibleBySetting = new Map<string, Set<string>>();
  const addCode = (code: string) => {
    if (!seen.has(code)) {
      seen.add(code);
      codes.push(code);
    }
  };

  for (const setting of ['all', 'match', 'training'] as const) {
    const visibleCodes = rankedLaneCodes(rows, setting);
    visibleCodes.forEach(addCode);
    visibleBySetting.set(setting, visibleCodes);
  }

  [...new Set(rows.map((row) => row.code))].sort().forEach(addCode);
  const neighbours = new Map(codes.map((code) => [code, new Set<string>()]));
  for (const visibleCodes of visibleBySetting.values()) {
    for (const code of visibleCodes) {
      for (const other of visibleCodes) {
        if (other !== code) neighbours.get(code)?.add(other);
      }
    }
  }

  const assigned = new Map<string, CardColour>();
  for (const code of codes) {
    const row = rows.find((candidate) => candidate.code === code);
    const label = row?.label.toLowerCase() ?? '';
    const referenceColor = REFERENCE_INJURY_COLORS[code]
      ?? (label.includes('concussion') && !label.includes('non-concussion') ? REFERENCE_INJURY_COLORS.concussion : undefined)
      ?? (label.includes('hamstring') ? REFERENCE_INJURY_COLORS.hamstring_strain : undefined)
      ?? (isKneeLigamentDiagnosis(row) ? REFERENCE_INJURY_COLORS.compound__knee__joint_sprain : undefined)
      ?? ((label.includes('ankle') && (label.includes('ligament') || label.includes('syndesmosis'))) ? REFERENCE_INJURY_COLORS.compound__ankle__joint_sprain : undefined)
      ?? ((label.includes('contusion') || label.includes('haematoma')) ? REFERENCE_INJURY_COLORS.contusion_haematoma : undefined)
      ?? ((label.includes('groin') || label.includes('adductor')) ? REFERENCE_INJURY_COLORS.adductor_groin : undefined)
      ?? (label.includes('calf') ? REFERENCE_INJURY_COLORS.calf_muscle : undefined);
    if (referenceColor) assigned.set(code, referenceColor);
  }

  const available: string[] = [...FALLBACK_INJURY_COLORS];
  const orderedCodes = [...codes].sort((a, b) =>
    (neighbours.get(b)?.size ?? 0) - (neighbours.get(a)?.size ?? 0) || a.localeCompare(b));

  for (const code of orderedCodes) {
    if (assigned.has(code)) continue;
    const neighbourColors = [...(neighbours.get(code) ?? [])]
      .map((other) => assigned.get(other)?.background)
      .filter((color): color is string => Boolean(color));
    const comparisonColors = neighbourColors.length
      ? neighbourColors
      : [...assigned.values()].map((color) => color.background);
    let selectedIndex = 0;
    let bestDistance = -1;
    for (let index = 0; index < available.length; index += 1) {
      const candidate = available[index];
      const distance = comparisonColors.length
        ? Math.min(...comparisonColors.map((color) => hexColorDistance(candidate, color)))
        : Number.POSITIVE_INFINITY;
      if (distance > bestDistance) {
        selectedIndex = index;
        bestDistance = distance;
      }
    }
    const paletteColor = available.splice(selectedIndex, 1)[0];
    const generatedHue = (205 + assigned.size * 137.508) % 360;
    assigned.set(code, {
      background: paletteColor ?? `hsl(${generatedHue} 76% 38%)`,
      foreground: '#ffffff',
    });
  }

  return assigned;
}

/** One colour per illness on screen, so a code keeps its colour across the four lanes. */
export function illnessColorMap<T extends { code: string; label: string }>(rows: readonly T[]) {
  const codes: string[] = [];
  for (const metric of ILLNESS_METRIC_KEYS) {
    for (const row of rankedIllnesses(rows, metric)) {
      if (!codes.includes(row.code)) codes.push(row.code);
    }
  }
  return new Map(codes.map((code, index) => [
    code,
    { background: ILLNESS_COLORS[index % ILLNESS_COLORS.length], foreground: '#ffffff' },
  ]));
}
