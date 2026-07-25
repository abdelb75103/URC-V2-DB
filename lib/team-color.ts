/**
 * Club accent identity, resolved against the dark dashboard surfaces.
 *
 * Eleven of the sixteen accents in config/teams.ts fail 3:1 against
 * --background, and eight clubs share #FFFFFF as their secondary, so falling
 * straight back to the secondary would send half the league to the colour that
 * is already --foreground. The resolver therefore lifts lightness in OKLCH
 * first, which keeps Munster red and Leinster blue, and only then considers the
 * secondary. Chroma is reduced (never hue) when a lifted colour leaves sRGB.
 *
 * Nothing here rebinds a CSS custom property: the resolved colours are applied
 * through explicit props and inline styles at named call sites.
 */

export type Rgb = readonly [number, number, number];

/** Dashboard surfaces from app/globals.css, as HSL triples. */
export const SURFACE_HSL: Record<'background' | 'card' | 'muted', readonly [number, number, number]> = {
  background: [205, 47, 14],
  card: [205, 44, 17],
  muted: [205, 44, 25],
};

export type Surface = keyof typeof SURFACE_HSL;

/** WCAG floor for large bold text (1.4.3) and for non-text UI marks (1.4.11). */
export const CONTRAST_TARGET = 3;

/** Below this OKLCH chroma a colour carries no club identity. */
const ACHROMATIC_CHROMA = 0.02;

export function surfaceHex(surface: Surface): string {
  return rgbToHex(hslToRgb(...SURFACE_HSL[surface]));
}

function hslToRgb(h: number, s: number, l: number): Rgb {
  const saturation = s / 100;
  const lightness = l / 100;
  const chroma = (1 - Math.abs(2 * lightness - 1)) * saturation;
  const segment = ((h % 360) + 360) % 360 / 60;
  const second = chroma * (1 - Math.abs((segment % 2) - 1));
  const [r, g, b] = segment < 1 ? [chroma, second, 0]
    : segment < 2 ? [second, chroma, 0]
    : segment < 3 ? [0, chroma, second]
    : segment < 4 ? [0, second, chroma]
    : segment < 5 ? [second, 0, chroma]
    : [chroma, 0, second];
  const offset = lightness - chroma / 2;
  return [r + offset, g + offset, b + offset];
}

export function hexToRgb(hex: string): Rgb {
  const value = hex.replace('#', '');
  const full = value.length === 3 ? value.split('').map((c) => c + c).join('') : value;
  return [0, 2, 4].map((index) => Number.parseInt(full.slice(index, index + 2), 16) / 255) as unknown as Rgb;
}

export function rgbToHex(rgb: Rgb): string {
  return `#${rgb
    .map((channel) => Math.round(Math.min(Math.max(channel, 0), 1) * 255).toString(16).padStart(2, '0'))
    .join('')}`;
}

function srgbToLinear(channel: number) {
  return channel <= 0.04045 ? channel / 12.92 : ((channel + 0.055) / 1.055) ** 2.4;
}

function linearToSrgb(channel: number) {
  return channel <= 0.0031308 ? channel * 12.92 : 1.055 * channel ** (1 / 2.4) - 0.055;
}

function relativeLuminance(rgb: Rgb) {
  const [r, g, b] = rgb.map(srgbToLinear);
  return 0.2126 * r + 0.7152 * g + 0.0722 * b;
}

export function contrastRatio(a: Rgb, b: Rgb) {
  const first = relativeLuminance(a);
  const second = relativeLuminance(b);
  const lighter = Math.max(first, second);
  const darker = Math.min(first, second);
  return (lighter + 0.05) / (darker + 0.05);
}

export type Oklch = { l: number; c: number; h: number };

export function rgbToOklch(rgb: Rgb): Oklch {
  const [r, g, b] = rgb.map(srgbToLinear);
  const l = Math.cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b);
  const m = Math.cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b);
  const s = Math.cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b);
  const lightness = 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s;
  const aAxis = 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s;
  const bAxis = 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s;
  return {
    l: lightness,
    c: Math.hypot(aAxis, bAxis),
    h: (Math.atan2(bAxis, aAxis) * 180 / Math.PI + 360) % 360,
  };
}

function oklchToRgb({ l, c, h }: Oklch): Rgb {
  const radians = h * Math.PI / 180;
  const aAxis = c * Math.cos(radians);
  const bAxis = c * Math.sin(radians);
  const lCube = (l + 0.3963377774 * aAxis + 0.2158037573 * bAxis) ** 3;
  const mCube = (l - 0.1055613458 * aAxis - 0.0638541728 * bAxis) ** 3;
  const sCube = (l - 0.0894841775 * aAxis - 1.2914855480 * bAxis) ** 3;
  return [
    linearToSrgb(4.0767416621 * lCube - 3.3077115913 * mCube + 0.2309699292 * sCube),
    linearToSrgb(-1.2684380046 * lCube + 2.6097574011 * mCube - 0.3413193965 * sCube),
    linearToSrgb(-0.0041960863 * lCube - 0.7034186147 * mCube + 1.7076147010 * sCube),
  ];
}

function inGamut(rgb: Rgb) {
  return rgb.every((channel) => channel >= -0.0001 && channel <= 1.0001);
}

/** Round to the 8-bit colour that will actually render, so the measured ratio is the shipped one. */
function quantise(rgb: Rgb): Rgb {
  return rgb.map((channel) => Math.round(Math.min(Math.max(channel, 0), 1) * 255) / 255) as unknown as Rgb;
}

/** Bring an OKLCH colour into sRGB by reducing chroma only, so hue is exact. */
function fitChroma(candidate: Oklch): Rgb {
  if (inGamut(oklchToRgb(candidate))) return quantise(oklchToRgb(candidate));
  let low = 0;
  let high = candidate.c;
  for (let step = 0; step < 24; step += 1) {
    const mid = (low + high) / 2;
    if (inGamut(oklchToRgb({ ...candidate, c: mid }))) low = mid;
    else high = mid;
  }
  return quantise(oklchToRgb({ ...candidate, c: low }));
}

/** Smallest lightness at or above the base that clears the target, or null. */
function liftToTarget(base: Oklch, backdrop: Rgb, target: number): Rgb | null {
  for (let step = 0; step <= 1000; step += 1) {
    const candidate = fitChroma({ ...base, l: base.l + (1 - base.l) * (step / 1000) });
    if (contrastRatio(candidate, backdrop) >= target) return candidate;
  }
  return null;
}

export type TeamColorSource = 'accent' | 'lightened' | 'secondary' | 'achromatic';

export type ResolvedTeamColor = { color: string; source: TeamColorSource };

/**
 * Pure resolver. `backdrop` is the hex of the surface the colour sits on and
 * `target` the contrast ratio it must clear against it; both are parameters
 * because a colour that clears --background can still fail on --muted.
 */
export function resolveTeamColor({
  accent,
  accentSecondary,
  backdrop,
  target = CONTRAST_TARGET,
}: {
  accent: string;
  accentSecondary: string;
  backdrop: string;
  target?: number;
}): ResolvedTeamColor {
  const backdropRgb = hexToRgb(backdrop);
  const accentRgb = hexToRgb(accent);
  if (contrastRatio(accentRgb, backdropRgb) >= target) {
    return { color: rgbToHex(accentRgb), source: 'accent' };
  }

  const accentOklch = rgbToOklch(accentRgb);
  if (accentOklch.c >= ACHROMATIC_CHROMA) {
    const lifted = liftToTarget(accentOklch, backdropRgb, target);
    if (lifted) return { color: rgbToHex(lifted), source: 'lightened' };
  }

  const secondaryRgb = hexToRgb(accentSecondary);
  const secondaryOklch = rgbToOklch(secondaryRgb);
  if (secondaryOklch.c >= ACHROMATIC_CHROMA) {
    const usable = contrastRatio(secondaryRgb, backdropRgb) >= target
      ? secondaryRgb
      : liftToTarget(secondaryOklch, backdropRgb, target);
    if (usable) return { color: rgbToHex(usable), source: 'secondary' };
  }

  // Ospreys and Sharks are #000000 on #FFFFFF: no chromatic identity exists in
  // their config, and a mid-grey mark read as disabled rather than deliberate.
  // White is their actual second colour and clears the target on every surface.
  return { color: '#ffffff', source: 'achromatic' };
}

export type TeamColorSet = {
  /** Safe on every dashboard surface; use for any mark or fill. Same as `mark`. */
  primary: string;
  /** The dashboard <h1>, which sits on --background as large bold text. */
  text: string;
  /** Chart marks and bar fills, which sit on --card or the --muted bar track. */
  mark: string;
  /**
   * How the colour was reached. `achromatic` means the club has no chromatic
   * accent at all: the grey still separates their mark from the cyan field, but
   * tinting body copy or a heading with it only makes that text look disabled,
   * so call sites that colour text should leave those clubs on --foreground.
   */
  source: TeamColorSource;
};

/**
 * `mark` is resolved against --muted, the lightest of the three surfaces, so it
 * also clears the target on --card and --background.
 */
export function resolveTeamPalette(team: { accent: string; accentSecondary: string }): TeamColorSet {
  const { color: mark, source } = resolveTeamColor({ ...team, backdrop: surfaceHex('muted') });
  return {
    primary: mark,
    text: resolveTeamColor({ ...team, backdrop: surfaceHex('background') }).color,
    mark,
    source,
  };
}
