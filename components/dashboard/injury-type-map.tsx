'use client';

import { useId, type KeyboardEvent, type ReactNode } from 'react';
import type { InjuryTypeFamilyRow } from '@/lib/reporting-types';

export type InjuryTypeMetric =
  | 'time_loss_injuries'
  | 'incidence_per_1000h'
  | 'burden_per_1000h';

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
};

const METRIC_LABELS: Record<InjuryTypeMetric, string> = {
  time_loss_injuries: 'time-loss injuries',
  incidence_per_1000h: 'injuries per 1,000 player-hours',
  burden_per_1000h: 'days per 1,000 player-hours',
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
  ];

  return (
    <div className="relative">
      <div id={tooltipId} aria-live="polite" className="sr-only">
        {activeRow
          ? `${activeRow.label}: ${metricValue(activeRow, metric).toLocaleString(undefined, { maximumFractionDigits: 1 })} ${METRIC_LABELS[metric]}.`
          : 'No injury type family selected.'}
      </div>
      <svg
        viewBox="0 0 300 460"
        className="mx-auto h-auto w-full max-w-[330px] sm:max-w-[360px] lg:max-w-[300px] xl:max-w-[350px]"
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
    </div>
  );
}

function Silhouette() {
  return (
    <g aria-hidden="true" pointerEvents="none">
      <g fill="hsl(201 30% 38% / 0.11)" stroke="hsl(190 48% 66% / 0.34)" strokeWidth="1.15" strokeLinejoin="round">
        <path d="M150 9 C133 9 123 21 123 38 C123 51 129 61 139 67 L138 76 C121 78 107 84 98 94 C92 101 87 113 83 126 L72 174 C69 185 72 195 79 198 C85 200 91 195 94 186 L109 132 L118 195 C119 206 122 214 127 220 L117 272 L124 421 C125 439 132 449 142 449 L150 286 L158 449 C168 449 175 439 176 421 L183 272 L173 220 C178 214 181 206 182 195 L191 132 L206 186 C209 195 215 200 221 198 C228 195 231 185 228 174 L217 126 C213 113 208 101 202 94 C193 84 179 78 162 76 L161 67 C171 61 177 51 177 38 C177 21 167 9 150 9 Z" />
        <path d="M80 197 C75 207 77 219 81 234 L86 258 C88 268 94 273 100 270 C105 267 106 260 104 251 L97 217 C95 206 90 198 84 196 Z M220 197 C225 207 223 219 219 234 L214 258 C212 268 206 273 200 270 C195 267 194 260 196 251 L203 217 C205 206 210 198 216 196 Z" />
        <path d="M86 258 C82 267 83 278 89 283 C94 287 99 284 101 277 L102 269 Z M214 258 C218 267 217 278 211 283 C206 287 201 284 199 277 L198 269 Z" />
        <path d="M124 421 C121 435 116 444 108 449 L106 454 L140 454 L142 448 Z M176 421 C179 435 184 444 192 449 L194 454 L160 454 L158 448 Z" />
      </g>
      <g fill="none" stroke="hsl(190 38% 68% / 0.17)" strokeWidth="0.8" strokeLinecap="round">
        <path d="M140 70 Q150 75 160 70 M116 104 Q150 118 184 104 M127 220 Q150 230 173 220 M119 272 Q150 281 181 272" />
        <path d="M150 78 L150 215 M136 228 Q150 238 164 228 M128 300 Q137 307 145 300 M155 300 Q163 307 172 300" />
      </g>
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
  const color = INJURY_FAMILY_COLORS[code] ?? 'hsl(190 48% 54%)';
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
  };
  const [cx, cy] = points[code] ?? [150, 230];

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
          <path fill="none" strokeWidth="4" d="M136 77 C115 79 101 87 94 103 L74 178 M164 77 C185 79 199 87 206 103 L226 178 M127 220 L118 273 L125 421 M173 220 L182 273 L175 421" />
          <path d="M78 181 C84 176 91 179 94 186 L97 216 C91 222 84 221 80 215 Z" />
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
        <g fill="none" strokeLinecap="round" strokeLinejoin="round">
          <path strokeWidth="5.5" d="M136 34 C136 22 143 17 150 17 C157 17 164 22 164 34 C164 47 158 57 150 57 C142 57 136 47 136 34 Z" />
          <path strokeWidth="4" d="M150 58 L150 213 M150 83 C140 82 131 85 123 91 M150 83 C160 82 169 85 177 91" />
          <path strokeWidth="5.5" d="M122 93 L94 139 L84 188 M178 93 L206 139 L216 188" />
          <path strokeWidth="4" d="M132 112 Q150 124 168 112 M131 130 Q150 142 169 130 M132 149 Q150 160 168 149 M134 168 Q150 178 166 168" />
          <path strokeWidth="6" d="M136 222 L132 298 L134 420 M164 222 L168 298 L166 420" />
          <path strokeWidth="4.5" d="M128 211 Q150 229 172 211 L166 239 Q150 249 134 239 Z" />
        </g>
      );
    case 'muscle':
      return (
        <>
          <path d="M128 84 C115 85 105 91 101 101 C107 108 116 112 124 109 C132 105 135 95 128 84 Z M172 84 C185 85 195 91 199 101 C193 108 184 112 176 109 C168 105 165 95 172 84 Z" />
          <path d="M128 101 C136 92 145 90 148 96 L147 127 C137 134 125 130 118 120 Z M172 101 C164 92 155 90 152 96 L153 127 C163 134 175 130 182 120 Z" />
          <path d="M103 111 C96 118 92 132 91 148 L100 174 C108 172 114 164 114 153 L116 119 Z M197 111 C204 118 208 132 209 148 L200 174 C192 172 186 164 186 153 L184 119 Z" />
          <path d="M126 133 C134 128 143 130 147 136 L145 157 C137 162 129 160 124 155 Z M174 133 C166 128 157 130 153 136 L155 157 C163 162 171 160 176 155 Z" />
          <path d="M127 162 C134 157 142 159 146 165 L144 187 C136 193 129 190 124 184 Z M173 162 C166 157 158 159 154 165 L156 187 C164 193 171 190 176 184 Z" />
          <path d="M121 159 C126 169 127 185 126 202 C132 211 139 216 146 214 L143 191 C135 184 132 169 132 157 Z M179 159 C174 169 173 185 174 202 C168 211 161 216 154 214 L157 191 C165 184 168 169 168 157 Z" />
          <path d="M124 228 C134 218 144 222 147 235 L144 298 C136 305 126 302 121 293 Z M176 228 C166 218 156 222 153 235 L156 298 C164 305 174 302 179 293 Z" />
          <path d="M126 307 C134 300 142 306 143 317 L139 379 C134 386 127 382 124 374 Z M174 307 C166 300 158 306 157 317 L161 379 C166 386 173 382 176 374 Z" />
        </>
      );
    case 'joint_capsule':
      return (
        <g fill="none" strokeWidth="7">
          <circle cx="116" cy="96" r="10" />
          <circle cx="184" cy="96" r="10" />
          <ellipse cx="90" cy="188" rx="9" ry="11" />
          <ellipse cx="210" cy="188" rx="9" ry="11" />
          <ellipse cx="132" cy="302" rx="12" ry="9" />
          <ellipse cx="168" cy="302" rx="12" ry="9" />
        </g>
      );
    case 'cartilage':
      return (
        <g fill="none" strokeLinecap="round" strokeWidth="5">
          <path d="M122 298 Q132 306 142 298" />
          <path d="M158 298 Q168 306 178 298" />
          <path d="M108 95 Q116 86 124 95" />
          <path d="M176 95 Q184 86 192 95" />
          <path d="M127 216 Q150 229 173 216" />
        </g>
      );
    case 'ligament_sprain':
      return (
        <g fill="none" strokeLinecap="round" strokeWidth="4">
          <path d="M125 292 L139 312 M139 292 L125 312 M161 292 L175 312 M175 292 L161 312" />
          <path d="M108 90 L123 102 M192 90 L177 102" />
          <path d="M124 389 L138 399 M176 389 L162 399" />
        </g>
      );
    case 'tendon':
      return (
        <g fill="none" strokeLinecap="round" strokeWidth="4.5">
          <path d="M111 144 L98 181 M189 144 L202 181" />
          <path d="M132 283 L132 295 M168 283 L168 295" />
          <path d="M132 375 L129 423 M168 375 L171 423" />
        </g>
      );
    case 'nervous_system':
      return (
        <g fill="none" strokeLinecap="round" strokeLinejoin="round" strokeWidth="3">
          <path d="M137 30 C140 20 146 18 150 26 C155 18 162 21 164 31 C168 40 161 51 150 55 C139 51 132 41 137 30 Z" />
          <path d="M150 56 L150 220 M147 105 L119 137 L92 203 M153 105 L181 137 L208 203 M147 218 L132 278 L132 411 M153 218 L168 278 L168 411" />
          <path d="M145 132 L132 157 M155 132 L168 157 M137 250 L126 267 M163 250 L174 267" />
        </g>
      );
    case 'vascular':
      return (
        <g fill="none" strokeLinecap="round" strokeLinejoin="round" strokeWidth="2.5">
          <path d="M151 69 L151 219 M151 116 L125 147 L101 194 M151 116 L175 147 L199 194 M151 218 L135 278 L133 403 M151 218 L167 278 L169 403" />
          <path d="M151 128 Q164 121 169 134 Q171 145 151 158 Q131 145 133 134 Q138 121 151 128 Z" />
        </g>
      );
    default:
      return null;
  }
}
