'use client';

import { useId, useState, type KeyboardEvent } from 'react';
import type { InjuryProfileRow } from '@/lib/reporting-types';

export type LocationMetric = 'time_loss_injuries' | 'incidence_per_1000h' | 'burden_per_1000h';

const REGIONS = [
  'head',
  'neck',
  'shoulder',
  'upper_arm',
  'elbow',
  'forearm',
  'wrist',
  'hand',
  'chest',
  'thoracic_spine',
  'abdomen',
  'lumbosacral',
  'hip_groin',
  'thigh',
  'knee',
  'lower_leg',
  'ankle',
  'foot',
] as const;

const METRIC_LABELS: Record<LocationMetric, { label: string; unit: string }> = {
  time_loss_injuries: { label: 'Injuries', unit: '' },
  incidence_per_1000h: { label: 'Incidence', unit: ' injuries per 1,000 player-hours' },
  burden_per_1000h: { label: 'Burden', unit: ' days per 1,000 player-hours' },
};

/** Fallback name for a region the payload carries no row for, cased like the payload labels. */
function regionLabel(code: string) {
  const words = code.replaceAll('_', ' ');
  return `${words.charAt(0).toUpperCase()}${words.slice(1)}`;
}

function valueFor(row: InjuryProfileRow | undefined, metric: LocationMetric) {
  const value = row?.[metric];
  return typeof value === 'number' && Number.isFinite(value) ? value : 0;
}

/** A true zero carries no heat, so "few" can never look like "none". */
const UNTINTED_FILL = 'hsl(205 30% 22% / 0.35)';

// The ramp is drawn over a dark navy backdrop, so its low end has to keep a
// lightness and opacity floor: at 0.22 alpha the smallest regions rendered as
// near-black brown and were unreadable. That floor lifts non-zero values only.
export function locationHeatColor(value: number, max: number) {
  if (!(value > 0)) return UNTINTED_FILL;
  const ratio = max > 0 ? Math.min(Math.max(value / max, 0), 1) : 0;
  return `hsla(${48 - ratio * 48}, 92%, ${62 - ratio * 8}%, ${0.55 + ratio * 0.45})`;
}

export function BodyMap({
  rows,
  metric,
  activeCode,
  onHover,
  onSelect,
}: {
  rows: InjuryProfileRow[];
  metric: LocationMetric;
  activeCode?: string;
  onHover: (code?: string) => void;
  onSelect: (code: string) => void;
}) {
  const byCode = new Map(rows.map((row) => [row.code, row]));
  // The plotted maximum stays driven by the regions that carry data, so making
  // the empty regions hoverable never changes another region's colour.
  const max = Math.max(...rows.map((row) => valueFor(row, metric)), 0);
  const tooltipId = useId();
  // Regions with no payload row are hoverable too, and the shared location view
  // only resolves codes that carry data, so the map keeps its own hover state and
  // still reports every hover upward for the panels that can use it.
  const [hoveredRegion, setHoveredRegion] = useState<string>();
  const handleHover = (code?: string) => {
    setHoveredRegion(code);
    onHover(code);
  };
  const effectiveCode = hoveredRegion ?? activeCode;
  const activeRow = effectiveCode ? byCode.get(effectiveCode) : undefined;
  const activeValue = valueFor(activeRow, metric);
  const metricMeta = METRIC_LABELS[metric];

  return (
    <div className="relative">
      <div id={tooltipId} aria-live="polite" className="sr-only">
        {effectiveCode ? (
          <>
            <span className="font-semibold text-foreground">{activeRow?.label ?? regionLabel(effectiveCode)}</span>
            <span className="mx-1 text-muted-foreground">:</span>
            <span className="font-medium tabular-nums text-foreground">{activeValue.toLocaleString(undefined, { maximumFractionDigits: 1 })} {metricMeta.label}{metricMeta.unit}</span>
            <span className="block mt-0.5 text-muted-foreground">
              {activeRow
                ? `n = ${activeRow.time_loss_injuries} injuries.`
                : '0 means no cases were recorded in this bucket.'}
            </span>
          </>
        ) : 'No body location selected.'}
      </div>
      <svg
        viewBox="0 0 360 420"
        className="mx-auto h-auto w-full max-w-[390px] lg:max-w-[280px] xl:max-w-[320px]"
        aria-label="Interactive front and back body map"
        aria-describedby={tooltipId}
      >
        <text x="90" y="18" textAnchor="middle" fill="hsl(0 0% 75%)" fontSize="12">Front</text>
        <text x="270" y="18" textAnchor="middle" fill="hsl(0 0% 75%)" fontSize="12">Back</text>
        <BodyFigure
          view="front"
          x={30}
          byCode={byCode}
          metric={metric}
          max={max}
          activeCode={effectiveCode}
          onHover={handleHover}
          onSelect={onSelect}
          tooltipId={tooltipId}
        />
        <BodyFigure
          view="back"
          x={210}
          byCode={byCode}
          metric={metric}
          max={max}
          activeCode={effectiveCode}
          onHover={handleHover}
          onSelect={onSelect}
          tooltipId={tooltipId}
        />
      </svg>
      <div className="mt-2 flex items-center justify-center gap-2 text-[11px] text-muted-foreground">
        <span>Lower</span>
        <span className="h-2.5 w-28 rounded-full bg-gradient-to-r from-yellow-300 via-orange-500 to-red-600" aria-hidden="true" />
        <span>Higher</span>
      </div>
    </div>
  );
}

function BodyFigure({
  view,
  x,
  byCode,
  metric,
  max,
  activeCode,
  onHover,
  onSelect,
  tooltipId,
}: {
  view: 'front' | 'back';
  x: number;
  byCode: Map<string, InjuryProfileRow>;
  metric: LocationMetric;
  max: number;
  activeCode?: string;
  onHover: (code?: string) => void;
  onSelect: (code: string) => void;
  tooltipId: string;
}) {
  return (
    <g transform={`translate(${x} 30)`}>
      {REGIONS.map((code) => {
        if ((code === 'chest' || code === 'abdomen') && view === 'back') return null;
        if ((code === 'thoracic_spine' || code === 'lumbosacral') && view === 'front') return null;
        // Every controlled IOC bucket is drawn and hoverable, whether or not the
        // payload carries a row for it: an absent row reads as a recorded 0.
        const row = byCode.get(code);
        const value = valueFor(row, metric);
        return (
          <Region
            key={code}
            code={code}
            view={view}
            label={row?.label ?? regionLabel(code)}
            value={value}
            metric={metric}
            fill={locationHeatColor(value, max)}
            active={activeCode === code}
            dimmed={Boolean(activeCode && activeCode !== code)}
            onHover={onHover}
            onSelect={onSelect}
            tooltipId={tooltipId}
          />
        );
      })}
    </g>
  );
}

function Region({
  code,
  view,
  label,
  value,
  metric,
  fill,
  active,
  dimmed,
  onHover,
  onSelect,
  tooltipId,
}: {
  code: (typeof REGIONS)[number];
  view: 'front' | 'back';
  label: string;
  value: number;
  metric: LocationMetric;
  fill: string;
  active: boolean;
  dimmed: boolean;
  onHover: (code?: string) => void;
  onSelect: (code: string) => void;
  tooltipId: string;
}) {
  const common = {
    fill,
    stroke: active ? 'hsl(0 0% 96%)' : 'hsl(34 95% 63% / 0.55)',
    strokeWidth: active ? 2.5 : 1,
    opacity: dimmed ? 0.25 : 1,
    pointerEvents: 'bounding-box' as const,
    className: 'cursor-pointer outline-none transition-[opacity,stroke] duration-150 focus-visible:stroke-white',
    role: 'button',
    tabIndex: 0,
    'aria-label': `${label}, ${view} view: ${value.toLocaleString(undefined, { maximumFractionDigits: 1 })} ${METRIC_LABELS[metric].label}${METRIC_LABELS[metric].unit}`,
    'aria-describedby': tooltipId,
    onMouseEnter: () => onHover(code),
    onMouseLeave: () => onHover(),
    onFocus: () => onHover(code),
    onBlur: () => onHover(),
    onClick: () => onSelect(code),
    onKeyDown: (event: KeyboardEvent<SVGElement>) => {
      if (event.key === 'Enter' || event.key === ' ') {
        event.preventDefault();
        onSelect(code);
      }
    },
  };

  switch (code) {
    case 'head':
      return <circle cx="60" cy="25" r="20" {...common} />;
    case 'neck':
      return <rect x="51" y="45" width="18" height="17" rx="6" {...common} />;
    case 'shoulder':
      return <path d="M24 70 Q42 57 60 58 Q78 57 96 70 L91 88 Q75 78 60 79 Q45 78 29 88 Z" {...common} />;
    case 'upper_arm':
      return <path d="M25 74 Q17 80 15 111 L24 145 L38 141 L36 91 Z M95 74 Q103 80 105 111 L96 145 L82 141 L84 91 Z" {...common} />;
    case 'elbow':
      return <path d="M17 143 Q26 136 35 143 L34 158 Q26 164 18 157 Z M85 143 Q94 136 103 143 L102 158 Q94 164 86 157 Z" {...common} />;
    case 'forearm':
      return <path d="M18 157 L34 157 L31 205 L19 205 Z M86 157 L102 157 L101 205 L89 205 Z" {...common} />;
    case 'wrist':
      return <path d="M19 204 H31 V214 H19 Z M89 204 H101 V214 H89 Z" {...common} />;
    case 'hand':
      return <path d="M17 213 Q25 208 33 214 L30 239 Q25 248 20 239 Z M87 214 Q95 208 103 213 L100 239 Q95 248 90 239 Z" {...common} />;
    case 'chest':
      return <path d="M36 76 Q60 69 84 76 L82 124 Q60 133 38 124 Z" {...common} />;
    case 'thoracic_spine':
      return <path d="M38 76 Q60 69 82 76 L80 130 Q60 139 40 130 Z M56 78 H64 V132 H56 Z" {...common} />;
    case 'abdomen':
      return <path d="M39 125 Q60 133 81 125 L78 175 Q60 184 42 175 Z" {...common} />;
    case 'lumbosacral':
      return <path d="M40 131 Q60 139 80 131 L77 176 Q60 186 43 176 Z M54 145 H66 V178 H54 Z" {...common} />;
    case 'hip_groin':
      return <path d="M42 175 Q60 183 78 175 L84 201 L66 214 L60 200 L54 214 L36 201 Z" {...common} />;
    case 'thigh':
      return <path d="M37 199 L57 207 L54 280 L33 280 Z M63 207 L83 199 L87 280 L66 280 Z" {...common} />;
    case 'knee':
      return <path d="M33 278 H55 L56 300 H34 Z M65 300 L66 278 H87 L86 300 Z" {...common} />;
    case 'lower_leg':
      return <path d="M34 299 H56 L52 365 H37 Z M64 299 H86 L83 365 H68 Z" {...common} />;
    case 'ankle':
      return <path d="M37 362 H52 L51 376 H37 Z M68 362 H83 V376 H69 Z" {...common} />;
    case 'foot':
      return <path d="M37 374 H51 L48 389 H25 Q22 383 30 379 Z M69 374 H83 L90 379 Q98 383 95 389 H72 Z" {...common} />;
  }
}
