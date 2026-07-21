'use client';

import { useId, type KeyboardEvent, type ReactNode } from 'react';
import type { InjuryTypeFamilyRow } from '@/lib/reporting-types';

export type InjuryTypeMetric =
  | 'time_loss_injuries'
  | 'incidence_per_1000h'
  | 'burden_per_1000h'
  | 'mean_severity_days';

export const INJURY_FAMILY_COLORS: Record<string, string> = {
  muscle: 'hsl(2 58% 53%)',
  tendon: 'hsl(43 42% 82%)',
  ligament_sprain: 'hsl(47 64% 70%)',
  joint_capsule: 'hsl(187 48% 54%)',
  bone: 'hsl(38 24% 83%)',
  cartilage: 'hsl(188 74% 52%)',
  nervous_system: 'hsl(43 82% 59%)',
  skin_superficial: 'hsl(18 54% 67%)',
  internal_organ: 'hsl(346 45% 57%)',
  vascular: 'hsl(351 70% 58%)',
  other_unclassified: 'hsl(210 12% 62%)',
  unmapped_review: 'hsl(210 12% 62%)',
};

const METRIC_LABELS: Record<InjuryTypeMetric, string> = {
  time_loss_injuries: 'time-loss injuries',
  incidence_per_1000h: 'injuries per 1,000 player-hours',
  burden_per_1000h: 'days per 1,000 player-hours',
  mean_severity_days: 'mean severity days',
};

function metricValue(row: InjuryTypeFamilyRow | undefined, metric: InjuryTypeMetric) {
  const value = row?.[metric];
  return typeof value === 'number' && Number.isFinite(value) ? value : 0;
}

export function InjuryTypeMap({
  rows,
  metric,
  activeCode,
  selectedCode,
  onHover,
  onSelect,
}: {
  rows: InjuryTypeFamilyRow[];
  metric: InjuryTypeMetric;
  activeCode?: string;
  selectedCode?: string;
  onHover: (code?: string) => void;
  onSelect: (code: string) => void;
}) {
  const tooltipId = useId();
  const byCode = new Map(rows.map((row) => [row.code, row]));
  const activeRow = activeCode ? byCode.get(activeCode) : undefined;
  const anatomyCodes = [
    'skin_superficial',
    'internal_organ',
    'bone',
    'muscle',
    'joint_capsule',
    'cartilage',
    'ligament_sprain',
    'tendon',
    'nervous_system',
    'vascular',
    ...(byCode.has('other_unclassified') ? ['other_unclassified'] : []),
    ...(byCode.has('unmapped_review') ? ['unmapped_review'] : []),
  ];

  return (
    <div className="relative">
      <div id={tooltipId} aria-live="polite" className="sr-only">
        {activeRow
          ? `${activeRow.label}: ${metricValue(activeRow, metric).toLocaleString(undefined, { maximumFractionDigits: 1 })} ${METRIC_LABELS[metric]}. ${activeRow.subtypes.length} contributing ${activeRow.subtypes.length === 1 ? 'subtype' : 'subtypes'}.`
          : 'No injury type family selected.'}
      </div>
      <svg
        viewBox="0 0 300 460"
        className="mx-auto h-auto w-full max-w-[330px] lg:max-w-[300px] xl:max-w-[340px]"
        aria-label="Interactive injury type anatomy"
        aria-describedby={tooltipId}
      >
        <title>Interactive injury type anatomy</title>
        <Silhouette />
        {anatomyCodes.map((code) => {
          const row = byCode.get(code);
          return (
            <AnatomyLayer
              key={code}
              code={code}
              label={row?.label ?? code.replaceAll('_', ' ')}
              value={metricValue(row, metric)}
              metric={metric}
              enabled={Boolean(row)}
              active={activeCode === code}
              selected={selectedCode === code}
              dimmed={Boolean(activeCode && activeCode !== code)}
              onHover={onHover}
              onSelect={onSelect}
              tooltipId={tooltipId}
            />
          );
        })}
      </svg>
      <p className="mt-1 text-center text-[11px] leading-relaxed text-muted-foreground">
        Tissue colour identifies the family. Bar length shows the selected metric.
      </p>
    </div>
  );
}

function Silhouette() {
  return (
    <g aria-hidden="true" fill="hsl(202 28% 36% / 0.13)" stroke="hsl(190 55% 63% / 0.3)" strokeWidth="1.2">
      <circle cx="150" cy="38" r="28" />
      <path d="M137 63 L163 63 L169 78 Q190 81 205 98 L226 174 L212 180 L188 119 L197 202 Q185 219 174 221 L183 275 L176 431 L155 431 L150 283 L145 431 L124 431 L117 275 L126 221 Q115 219 103 202 L112 119 L88 180 L74 174 L95 98 Q110 81 131 78 Z" />
      <path d="M75 173 Q68 182 74 198 L83 247 L96 245 L89 189 Z M225 173 Q232 182 226 198 L217 247 L204 245 L211 189 Z" />
      <path d="M82 244 Q76 254 80 273 L91 273 L97 244 Z M218 244 Q224 254 220 273 L209 273 L203 244 Z" />
    </g>
  );
}

function AnatomyLayer({
  code,
  label,
  value,
  metric,
  enabled,
  active,
  selected,
  dimmed,
  onHover,
  onSelect,
  tooltipId,
}: {
  code: string;
  label: string;
  value: number;
  metric: InjuryTypeMetric;
  enabled: boolean;
  active: boolean;
  selected: boolean;
  dimmed: boolean;
  onHover: (code?: string) => void;
  onSelect: (code: string) => void;
  tooltipId: string;
}) {
  const interactionProps = enabled
    ? {
        role: 'button',
        tabIndex: 0,
        'aria-label': `${label}: ${value.toLocaleString(undefined, { maximumFractionDigits: 1 })} ${METRIC_LABELS[metric]}`,
        'aria-describedby': tooltipId,
        'aria-pressed': selected,
        onMouseEnter: () => onHover(code),
        onMouseLeave: () => onHover(),
        onFocus: () => onHover(code),
        onBlur: () => onHover(),
        onClick: () => onSelect(code),
        onKeyDown: (event: KeyboardEvent<SVGGElement>) => {
          if (event.key === 'Enter' || event.key === ' ') {
            event.preventDefault();
            onSelect(code);
          }
        },
      }
    : { 'aria-hidden': true as const };
  const color = INJURY_FAMILY_COLORS[code] ?? INJURY_FAMILY_COLORS.other_unclassified;
  const opacity = enabled ? (active ? 1 : dimmed ? 0.36 : 0.68) : 0.08;

  return (
    <g
      {...interactionProps}
      fill={color}
      stroke={active ? 'hsl(0 0% 98%)' : color}
      strokeWidth={active ? 2.4 : 1.1}
      opacity={opacity}
      className={enabled ? 'cursor-pointer outline-none transition-[opacity,stroke] duration-150 focus-visible:stroke-white' : 'outline-none'}
    >
      <g pointerEvents={enabled ? 'visiblePainted' : 'none'}>
        <LayerShapes code={code} />
      </g>
      <InteractionTarget code={code} enabled={enabled} />
    </g>
  );
}

function InteractionTarget({ code, enabled }: { code: string; enabled: boolean }) {
  const points: Record<string, [number, number]> = {
    muscle: [134, 248],
    tendon: [128, 400],
    ligament_sprain: [132, 302],
    joint_capsule: [116, 96],
    bone: [170, 350],
    cartilage: [184, 96],
    nervous_system: [150, 38],
    skin_superficial: [86, 205],
    internal_organ: [150, 142],
    vascular: [151, 189],
    other_unclassified: [266, 418],
    unmapped_review: [266, 372],
  };
  const [cx, cy] = points[code] ?? points.other_unclassified;

  return (
    <circle
      cx={cx}
      cy={cy}
      r="23"
      fill="transparent"
      stroke="none"
      pointerEvents={enabled ? 'all' : 'none'}
    />
  );
}

function LayerShapes({ code }: { code: string }): ReactNode {
  switch (code) {
    case 'skin_superficial':
      return (
        <>
          <path fill="none" strokeWidth="5" d="M129 78 Q106 83 96 105 L76 176 M171 78 Q194 83 204 105 L224 176 M123 218 L116 278 L124 430 M177 218 L184 278 L176 430" />
          <path d="M79 183 Q85 176 92 183 L96 219 Q88 225 82 218 Z" />
        </>
      );
    case 'internal_organ':
      return (
        <>
          <path d="M141 101 Q121 102 119 132 Q120 158 142 160 Z" />
          <path d="M159 101 Q179 102 181 132 Q180 158 158 160 Z" />
          <path d="M147 126 Q154 116 162 126 Q168 137 151 150 Q134 137 140 126 Q143 121 147 126 Z" />
          <path d="M151 160 Q174 156 181 171 Q168 184 144 179 Z" />
        </>
      );
    case 'bone':
      return (
        <g fill="none" strokeLinecap="round" strokeLinejoin="round" strokeWidth="7">
          <circle cx="150" cy="38" r="19" />
          <path d="M132 86 L168 86 M150 67 L150 213 M126 103 L91 179 M174 103 L209 179 M136 219 L131 304 L133 422 M164 219 L169 304 L167 422" />
          <path d="M128 213 Q150 229 172 213" />
        </g>
      );
    case 'muscle':
      return (
        <>
          <path d="M126 89 Q139 83 148 91 L146 129 Q130 132 119 119 Z M174 89 Q161 83 152 91 L154 129 Q170 132 181 119 Z" />
          <path d="M111 96 Q97 103 98 128 L108 158 L119 151 L121 111 Z M189 96 Q203 103 202 128 L192 158 L181 151 L179 111 Z" />
          <path d="M128 136 Q141 130 147 138 L144 191 Q131 196 123 185 Z M172 136 Q159 130 153 138 L156 191 Q169 196 177 185 Z" />
          <path d="M124 229 Q139 219 146 234 L143 300 L124 296 Z M176 229 Q161 219 154 234 L157 300 L176 296 Z" />
          <path d="M125 308 Q136 301 142 313 L139 380 L126 378 Z M175 308 Q164 301 158 313 L161 380 L174 378 Z" />
        </>
      );
    case 'joint_capsule':
      return (
        <g fill="none" strokeWidth="8">
          <circle cx="116" cy="96" r="10" />
          <circle cx="184" cy="96" r="10" />
          <ellipse cx="132" cy="302" rx="12" ry="9" />
          <ellipse cx="168" cy="302" rx="12" ry="9" />
        </g>
      );
    case 'cartilage':
      return (
        <g fill="none" strokeLinecap="round" strokeWidth="5">
          <path d="M122 298 Q132 306 142 298" />
          <path d="M158 298 Q168 306 178 298" />
          <path d="M110 94 Q116 86 122 94" />
          <path d="M178 94 Q184 86 190 94" />
        </g>
      );
    case 'ligament_sprain':
      return (
        <g fill="none" strokeLinecap="round" strokeWidth="4">
          <path d="M125 292 L139 312 M139 292 L125 312 M161 292 L175 312 M175 292 L161 312" />
          <path d="M124 389 L138 399 M176 389 L162 399" />
        </g>
      );
    case 'tendon':
      return (
        <g fill="none" strokeLinecap="round" strokeWidth="5">
          <path d="M112 145 L99 181 M188 145 L201 181" />
          <path d="M132 283 L132 295 M168 283 L168 295" />
          <path d="M132 375 L129 420 M168 375 L171 420" />
        </g>
      );
    case 'nervous_system':
      return (
        <g fill="none" strokeLinecap="round" strokeLinejoin="round" strokeWidth="3">
          <path d="M137 31 Q144 20 150 31 Q157 20 164 32 Q168 43 158 51 Q150 57 142 51 Q132 44 137 31 Z" />
          <path d="M150 57 L150 221 M147 106 L118 137 L92 202 M153 106 L182 137 L208 202 M147 220 L132 278 L132 410 M153 220 L168 278 L168 410" />
        </g>
      );
    case 'vascular':
      return (
        <g fill="none" strokeLinecap="round" strokeLinejoin="round" strokeWidth="2.5">
          <path d="M151 71 L151 219 M151 116 L125 147 L103 194 M151 116 L175 147 L197 194 M151 218 L135 278 L133 402 M151 218 L167 278 L169 402" />
          <path d="M151 128 Q164 121 169 134 Q171 145 151 158 Q131 145 133 134 Q138 121 151 128 Z" />
        </g>
      );
    case 'other_unclassified':
      return (
        <g>
          <circle cx="266" cy="418" r="16" fill="none" strokeDasharray="3 3" strokeWidth="2" />
          <text x="266" y="424" textAnchor="middle" fontSize="17" fontWeight="700" stroke="none">?</text>
        </g>
      );
    case 'unmapped_review':
      return (
        <g>
          <circle cx="266" cy="372" r="16" fill="none" strokeDasharray="3 3" strokeWidth="2" />
          <text x="266" y="378" textAnchor="middle" fontSize="17" fontWeight="700" stroke="none">!</text>
        </g>
      );
    default:
      return null;
  }
}
