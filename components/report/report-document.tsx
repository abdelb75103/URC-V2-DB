import {
  Circle, Defs, Document, Font, G, Image, Line, LinearGradient, Page, Path, Rect,
  Stop, StyleSheet, Svg, Text, Text as PdfSvgText, View,
} from "@react-pdf/renderer";
import { currentExposureWarnings } from "@/lib/exposure-chart";
import { timelineRate, PRELIMINARY_TIMELINE_NOTE } from "@/lib/season-timeline";
import type { PreliminaryMonthlyRateRow } from "@/lib/reporting-types";
import { cloneElement, type ComponentType, type ReactElement, type ReactNode } from "react";
import {
  orderedReportSectionIds,
  REPORT_SECTION_LABELS,
  type ReportDistributionRow, type ReportInjuryTypeFamily,
  type ReportModel, type ReportPatternRow, type ReportProfileRow,
  type ReportSectionId, type ReportSettingMetric,
} from "@/lib/report-model-types";
import {
  cardFill, commonInjuryColorMap, diagnosisColourMap, heatColour, heatScaleStops,
  illnessColorMap, MATRIX_DOT,
  NO_CASE_FILL, rankedCommonInjuries, rankedIllnesses, readableOn,
  RISK_ZONE_STOPS,
} from "@/lib/report-presentation";

export { DEFAULT_REPORT_SECTION_IDS } from "@/lib/report-model-types";
export type { ReportModel, ReportSectionId } from "@/lib/report-model-types";

// React PDF exposes the SVG text mark through the same runtime component as
// document text, while its bundled type currently omits the SVG font props.
const SvgText = PdfSvgText as unknown as ComponentType<Record<string, unknown>>;

// Clinical labels are long. Breaking them mid-word ("compres-sion") reads as a
// defect in a printed report, so words are kept whole and wrapped instead.
Font.registerHyphenationCallback((word) => [word]);

const C = {
  navy: "#071C3B", navy2: "#102C55", ink: "#14233B", muted: "#5A6B84",
  line: "#D3DFE9", paper: "#F3F7FA", white: "#FFFFFF", cyan: "#02D5F0",
  mint: "#42D8B4", blue: "#72A7FF", amber: "#FFC45C", coral: "#EF7189",
  purple: "#A78BFA", lime: "#8BD450", orange: "#FB923C", red: "#D95656",
  green: "#2F8F62", grey: "#94A3B8", rule: "#E2EAF1", track: "#E4EBF1",
  hsr: "#F59E0B",
} as const;
const PALETTE = [C.cyan, C.mint, C.blue, C.amber, C.coral, C.purple, C.lime, C.orange];
const SEVERITY_COLOURS: Record<string, string> = {
  zero_days_medical_attention_only: C.grey, one_day: C.cyan, two_to_three_days: C.cyan,
  four_to_seven_days: C.mint, eight_to_twenty_eight_days: C.amber,
  greater_than_twenty_eight_days: C.coral, unknown_or_censored: C.purple,
};
const CONTACT_COLOURS: Record<string, string> = { contact: C.purple, non_contact: C.orange, unknown: C.grey };
type ReportMetadata = { version: string; sourceGeneratedAt: string; exportedAt: string };
type SeasonComparisonVisuals = NonNullable<ReportModel["seasonComparisonVisuals"]>;

const styles = StyleSheet.create({
  page: { backgroundColor: C.paper, color: C.ink, fontFamily: "Helvetica", fontSize: 8, paddingHorizontal: 30, paddingBottom: 34 },
  cover: { backgroundColor: C.navy, color: C.white, fontFamily: "Helvetica" },
  header: { height: 40, paddingTop: 18, flexDirection: "row", justifyContent: "space-between", alignItems: "center", borderBottomWidth: 1, borderBottomColor: C.line, marginBottom: 12 },
  headerBrand: { flexDirection: "row", alignItems: "center" }, headerCrest: { width: 20, height: 20, objectFit: "contain", marginRight: 7 },
  eyebrow: { color: C.cyan, fontFamily: "Helvetica-Bold", fontSize: 7, letterSpacing: 1.4, textTransform: "uppercase" },
  headerLabel: { color: C.muted, fontFamily: "Helvetica-Bold", fontSize: 7, letterSpacing: 0.8, textTransform: "uppercase" },
  title: { color: C.navy, fontFamily: "Helvetica-Bold", fontSize: 18, lineHeight: 1.05 },
  standfirst: { color: C.muted, fontSize: 8, lineHeight: 1.35, marginTop: 3, marginBottom: 9 },
  panel: { backgroundColor: C.white, borderRadius: 5, padding: 9, borderWidth: 1, borderColor: C.line },
  darkPanel: { backgroundColor: C.navy, borderRadius: 5, padding: 10, color: C.white },
  panelTitle: { color: C.navy, fontFamily: "Helvetica-Bold", fontSize: 9.5, letterSpacing: 0.2, marginBottom: 3 },
  panelNote: { color: C.muted, fontSize: 6.8, lineHeight: 1.35, marginBottom: 7 },
  caption: { color: C.muted, fontSize: 6.5, lineHeight: 1.35, marginTop: 5 },
  columnHead: { color: C.muted, fontFamily: "Helvetica-Bold", fontSize: 6.5, letterSpacing: 0.4, textTransform: "uppercase" },
  headRow: { flexDirection: "row", alignItems: "flex-end", borderBottomWidth: 1, borderBottomColor: C.line, paddingBottom: 3, marginBottom: 5 },
  split: { flexDirection: "row", marginHorizontal: -4 }, half: { width: "50%", paddingHorizontal: 4 }, third: { width: "33.333%", paddingHorizontal: 4 },
  footer: { position: "absolute", bottom: 13, left: 30, right: 30, flexDirection: "row", justifyContent: "space-between", borderTopWidth: 1, borderTopColor: C.line, paddingTop: 5, color: C.muted, fontSize: 6.5 },
  metricGrid: { flexDirection: "row", flexWrap: "wrap", marginHorizontal: -3 }, metricCell: { padding: 3 },
  metricCard: { backgroundColor: C.white, borderRadius: 4, padding: 9, borderWidth: 1, borderColor: C.line, overflow: "hidden" },
  metricLabel: { color: C.ink, fontFamily: "Helvetica-Bold", fontSize: 7.2, letterSpacing: 0.2 },
  metricValue: { color: C.navy, fontFamily: "Helvetica-Bold", fontSize: 16, marginTop: 4 },
  metricUnit: { color: C.muted, fontSize: 6.5, marginTop: 1 },
  legend: { flexDirection: "row", flexWrap: "wrap", marginTop: 6 }, legendItem: { flexDirection: "row", alignItems: "center", marginRight: 11, marginBottom: 3 },
  legendDot: { width: 6, height: 6, borderRadius: 3, marginRight: 4 }, legendText: { color: C.muted, fontSize: 6.5 },
  compactTableRow: { flexDirection: "row", alignItems: "center", minHeight: 18, borderBottomWidth: 1, borderBottomColor: C.rule },
  compactLabel: { flex: 1, fontSize: 7 }, compactNumber: { width: 58, textAlign: "right", color: C.ink, fontSize: 6.8 },
  note: { backgroundColor: "#EAF2F8", borderLeftWidth: 3, borderLeftColor: C.cyan, padding: 7, color: C.muted, fontSize: 6.8, lineHeight: 1.4 },
  heatRow: { flexDirection: "row", minHeight: 16, borderBottomWidth: 1, borderBottomColor: C.rule, alignItems: "center" },
  heatName: { width: 84, fontSize: 6.5, paddingLeft: 3 }, heatCell: { flex: 1, textAlign: "center", paddingVertical: 3, fontSize: 6.8 },
  listItem: { flexDirection: "row", marginBottom: 6 }, bullet: { width: 3, height: 3, borderRadius: 1.5, backgroundColor: C.cyan, marginTop: 3.5, marginRight: 6 },
});

function fmt(value: number | null | undefined, unit = "", digits = 1): string {
  if (value === null || value === undefined || !Number.isFinite(value)) return "Not available";
  const rendered = new Intl.NumberFormat("en-IE", { maximumFractionDigits: Number.isInteger(value) ? 0 : digits }).format(value);
  return `${rendered}${unit ? ` ${unit}` : ""}`;
}
function tickText(value: number): string { return new Intl.NumberFormat("en-IE", { maximumFractionDigits: Number.isInteger(value) ? 0 : 1 }).format(value); }
/** en-IE renders September as "Sept"; the report uses three letters everywhere. */
function formatDate(value: string): string { const date = new Date(value.length === 10 ? `${value}T00:00:00Z` : value); if (Number.isNaN(date.valueOf())) return value; return new Intl.DateTimeFormat("en-IE", { day: "numeric", month: "short", year: "numeric", timeZone: "UTC" }).format(date).replace("Sept", "Sep"); }
function shortMonth(value: string): string {
  const isoMonth = /^\d{4}-(\d{2})$/.exec(value.trim())?.[1];
  if (isoMonth) return ["JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"][Number(isoMonth) - 1] ?? value;
  return value.trim().slice(0, 3).toUpperCase();
}
function monthRange(rows: ReadonlyArray<{ month: string }>): string { if (!rows.length) return ""; return `${shortMonth(rows[0].month)} to ${shortMonth(rows[rows.length - 1].month)}`; }
function metadata(model: ReportModel): ReportMetadata { return { version: model.reportVersion, sourceGeneratedAt: model.dataGeneratedAt, exportedAt: model.exportedAt }; }

/** Rounded axis domain plus its tick values, so every chart carries a readable numeric scale. */
function niceScale(max: number, count = 4): { top: number; ticks: number[] } {
  if (!(max > 0) || !Number.isFinite(max)) return { top: 1, ticks: [0, 0.5, 1] };
  const raw = max / count, magnitude = 10 ** Math.floor(Math.log10(raw));
  const step = ([1, 2, 2.5, 5, 10].find((factor) => factor * magnitude >= raw) ?? 10) * magnitude;
  const top = Math.ceil(max / step) * step, ticks: number[] = [];
  for (let value = 0; value <= top + step / 2; value += step) ticks.push(Number(value.toFixed(6)));
  return { top, ticks };
}

/**
 * A rounded linear domain for a matrix axis. The bounds come from the plotted
 * values rather than from zero, so clustered points spread across the plot, and
 * a domain that does not reach zero is reported so the axis can be marked broken.
 */
function linearDomain(values: number[], count = 4): { low: number; high: number; ticks: number[]; broken: boolean } {
  const usable = values.filter((value) => Number.isFinite(value));
  if (!usable.length) return { low: 0, high: 1, ticks: [0, 0.5, 1], broken: false };
  const min = Math.min(...usable), max = Math.max(...usable);
  const raw = Math.max((max - min) / count, Math.abs(max) * 0.08, 1e-6);
  const magnitude = 10 ** Math.floor(Math.log10(raw));
  const step = ([1, 2, 2.5, 5, 10].find((factor) => factor * magnitude >= raw) ?? 10) * magnitude;
  let low = Math.max(0, Math.floor(min / step) * step), high = Math.ceil(max / step) * step;
  // A point sitting exactly on the frame would draw a clipped circle, so the
  // domain gains a step whenever the data touches an edge.
  if (min - low < step * 0.4) low = Math.max(0, low - step);
  if (high - max < step * 0.4) high += step;
  const ticks: number[] = [];
  for (let value = low; value <= high + step / 2; value += step) ticks.push(Number(value.toFixed(6)));
  return { low, high, ticks, broken: low > 0 };
}

function Header({ model, section }: { model: ReportModel; section: ReportSectionId }) { return <View style={styles.header}><View style={styles.headerBrand}>{model.brand.crestDataUri && <Image src={model.brand.crestDataUri} style={styles.headerCrest} />}<Text style={styles.eyebrow}>URC injury surveillance</Text></View><Text style={styles.headerLabel}>{REPORT_SECTION_LABELS[section]}</Text></View>; }
function Footer({ model, meta }: { model: ReportModel; meta: ReportMetadata }) { return <View fixed style={styles.footer}><Text>{model.subjectName} | {model.season} | v{meta.version}</Text><Text>Source {formatDate(meta.sourceGeneratedAt)} | Exported {formatDate(meta.exportedAt)}</Text><Text render={({ pageNumber, totalPages }) => `${pageNumber} / ${totalPages}`} /></View>; }
function PageShell({ model, meta, section, children }: { model: ReportModel; meta: ReportMetadata; section: ReportSectionId; children: ReactNode }) { return <Page size="A4" style={styles.page}><Header model={model} section={section} />{children}<Footer model={model} meta={meta} /></Page>; }
function PageTitle({ title, note }: { title: string; note: string }) { return <View><Text style={styles.title}>{title}</Text><Text style={styles.standfirst}>{note}</Text></View>; }
function Panel({ title, note, children, fill = false }: { title?: string; note?: string; children: ReactNode; fill?: boolean }) { return <View style={[styles.panel, fill ? { height: "100%" } : {}]}>{title && <Text style={styles.panelTitle}>{title}</Text>}{note && <Text style={styles.panelNote}>{note}</Text>}{children}</View>; }

type LegendItem = { label: string; colour: string; shape?: "bar" | "line" | "swatch" };
function Legend({ items }: { items: LegendItem[] }) {
  return <View style={styles.legend}>{items.map((item) => <View key={item.label} style={styles.legendItem}>
    {item.shape === "line"
      ? <View style={{ width: 12, height: 2.4, backgroundColor: item.colour, marginRight: 4 }} />
      : <View style={[styles.legendDot, item.shape === "bar" || item.shape === "swatch" ? { width: 8, height: 7, borderRadius: 1 } : {}, { backgroundColor: item.colour }]} />}
    <Text style={styles.legendText}>{item.label}</Text>
  </View>)}</View>;
}
function Caption({ children }: { children: ReactNode }) { return <Text style={styles.caption}>{children}</Text>; }

type StatCard = {
  key: string;
  label: string;
  value: string;
  unit: string;
  companion?: { label: string; value: string };
  series?: Array<number | null>;
  colour: string;
};

function Sparkline({ values, colour }: { values: Array<number | null>; colour: string }) {
  const data = values.map((value, index) => ({ value, index })).filter((p): p is { value: number; index: number } => typeof p.value === "number" && Number.isFinite(p.value));
  if (data.length < 2) return null;
  const min = Math.min(...data.map((p) => p.value)), max = Math.max(...data.map((p) => p.value)), span = max - min || 1;
  const y = (v: number) => 19 - ((v - min) / span) * 15, last = data[data.length - 1];
  const path = data.map((p, i) => `${i ? "L" : "M"} ${(p.index / Math.max(1, values.length - 1)) * 100} ${y(p.value)}`).join(" ");
  return <Svg viewBox="0 0 100 22" style={{ height: 14, marginTop: 4 }}>
    <Line x1={0} x2={100} y1={20.5} y2={20.5} stroke={C.rule} strokeWidth={0.8} />
    <Path d={path} stroke={colour} strokeWidth={2} fill="none" />
    <Circle cx={(last.index / Math.max(1, values.length - 1)) * 100} cy={y(last.value)} r={2.4} fill={colour} />
  </Svg>;
}

function StatCards({ cards }: { cards: StatCard[] }) {
  return <View style={styles.metricGrid}>{cards.map((card) => <View key={card.key} style={[styles.metricCell, { width: `${100 / cards.length}%` }]}>
    <View style={[styles.metricCard, { minHeight: card.series ? 82 : 56 }]}>
      <Text style={styles.metricLabel}>{card.label}</Text>
      <Text style={styles.metricValue}>{card.value}</Text>
      <Text style={styles.metricUnit}>{card.unit}</Text>
      {card.companion && <View style={{ flexDirection: "row", alignItems: "center", marginTop: 4 }}>
        <View style={[styles.legendDot, { width: 5, height: 5, borderRadius: 2.5, backgroundColor: card.colour }]} />
        <Text style={{ color: C.muted, fontSize: 6.2 }}>{card.companion.label} </Text>
        <Text style={{ color: C.ink, fontFamily: "Helvetica-Bold", fontSize: 6.2 }}>{card.companion.value}</Text>
      </View>}
      {card.series && <Sparkline values={card.series} colour={card.colour} />}
    </View>
  </View>)}</View>;
}

function headlineValue(model: ReportModel, key: string): number | null {
  return model.snapshotMetrics.find((metric) => metric.key === key)?.value ?? null;
}

/**
 * The dashboard overview tiles, in the dashboard's order and colours. Incidence
 * and burden borrow the preliminary contributor-aligned series for their trend
 * whenever the release carries more than one such row, exactly as the dashboard
 * does; the headline values themselves stay the approved season figures.
 */
function OverviewCards({ model }: { model: ReportModel }) {
  const pattern = model.monthlyInjuryPattern, preliminary = model.preliminaryMonthlyRates;
  const usesPreliminary = preliminary.length > 1;
  const cards: StatCard[] = [
    {
      key: "injuries", label: "Injuries", value: fmt(headlineValue(model, "time_loss_injuries")), unit: "injuries", colour: C.cyan,
      companion: { label: "Overall Injuries", value: fmt(headlineValue(model, "recorded_injuries")) },
      series: pattern.map((row) => row.timeLossInjuries),
    },
    {
      key: "incidence", label: "Incidence", value: fmt(headlineValue(model, "incidence_per_1000h")), unit: "injuries /1,000 h", colour: C.amber,
      companion: { label: "Overall Incidence", value: fmt(headlineValue(model, "overall_incidence_per_1000h")) },
      series: usesPreliminary ? preliminary.map((row) => row.incidence_per_1000h) : pattern.map((row) => row.incidencePer1000h),
    },
    {
      key: "burden", label: "Burden", value: fmt(headlineValue(model, "burden_per_1000h")), unit: "days /1,000 h", colour: C.coral,
      series: usesPreliminary ? preliminary.map((row) => row.burden_per_1000h) : pattern.map((row) => row.burdenPer1000h),
    },
    {
      key: "exposure", label: model.exposure.totalHoursLabel === "Estimated Total Hours" ? "Estimated Exposure" : "Exposure",
      value: fmt(model.exposure.totalHours, "", 0), unit: "player-hours", colour: C.mint,
      series: model.exposure.monthly.map((row) => row.exposureHours),
    },
  ];
  return <View>
    <StatCards cards={cards} />
    {usesPreliminary && <Text style={[styles.panelNote, { marginTop: 4, marginBottom: 0 }]}>
      The Incidence and Burden trends use preliminary contributor-aligned monthly data. Headline values remain the approved season figures.
    </Text>}
  </View>;
}

function TimelineChart({ rows: sourceRows, preliminary = [], chartHeight = 235 }: { rows: readonly ReportPatternRow[]; preliminary?: readonly PreliminaryMonthlyRateRow[]; chartHeight?: number }) {
  const rows = sourceRows.map((row) => {
    const rate = timelineRate(row.month, row.incidencePer1000h, preliminary);
    return { ...row, incidencePer1000h: rate.incidence, preliminaryRate: rate.preliminary };
  });
  const hasOverallRates = rows.some((row) => row.overallIncidencePer1000h !== null);
  const hasTlRates = rows.some((row) => row.incidencePer1000h !== null);
  const w = 517, h = chartHeight, left = 42, right = 56, top = 24, bottom = 36;
  const plotW = w - left - right, plotH = h - top - bottom;
  const cases = niceScale(Math.max(1, ...rows.flatMap((r) => [r.recordedInjuries ?? 0, r.timeLossInjuries])));
  const rate = niceScale(Math.max(1, ...rows.flatMap((r) => [r.overallIncidencePer1000h ?? 0, r.incidencePer1000h ?? 0])));
  const slot = plotW / Math.max(1, rows.length), x = (i: number) => left + slot * i + slot / 2;
  const caseY = (v: number) => top + plotH - (v / cases.top) * plotH, rateY = (v: number) => top + plotH - (v / rate.top) * plotH;
  // A month with no released rate breaks the line rather than joining across it,
  // so a gap never reads as a value.
  const linePath = (pick: (r: ReportPatternRow) => number | null) => {
    let open = false;
    return rows.map((r, i) => {
      const value = pick(r);
      if (value === null || !Number.isFinite(value)) { open = false; return ""; }
      const command = open ? "L" : "M";
      open = true;
      return `${command} ${x(i)} ${rateY(value)}`;
    }).filter(Boolean).join(" ");
  };
  const barWidth = Math.min(15, slot * 0.34);
  // Some releases carry no monthly rates at all. The rate axis, its lines and its
  // legend entries are then dropped rather than drawn as an empty scale.
  const hasRates = rows.some((r) => finiteNumber(r.overallIncidencePer1000h) || finiteNumber(r.incidencePer1000h));
  return <View>
    <Svg viewBox={`0 0 ${w} ${h}`} style={{ height: h }}>
      <Rect x={left} y={top} width={plotW} height={plotH} fill={C.white} stroke={C.line} strokeWidth={0.8} />
      {cases.ticks.map((tick) => <G key={`case-${tick}`}>
        <Line x1={left} x2={left + plotW} y1={caseY(tick)} y2={caseY(tick)} stroke={C.rule} strokeWidth={0.8} />
        <SvgText x={left - 5} y={caseY(tick) + 2.4} textAnchor="end" fontSize={6.5} fill={C.muted}>{tickText(tick)}</SvgText>
      </G>)}
      {hasRates && rate.ticks.map((tick) => <G key={`rate-${tick}`}>
        <Line x1={left + plotW} x2={left + plotW + 3} y1={rateY(tick)} y2={rateY(tick)} stroke={C.line} strokeWidth={0.8} />
        <SvgText x={left + plotW + 6} y={rateY(tick) + 2.4} fontSize={6.5} fill={C.muted}>{tickText(tick)}</SvgText>
      </G>)}
      {rows.map((r, i) => { const centre = x(i); return <G key={r.month}>
        <Rect x={centre - barWidth - 1} y={caseY(r.recordedInjuries ?? 0)} width={barWidth} height={top + plotH - caseY(r.recordedInjuries ?? 0)} fill={C.cyan} opacity={0.72} />
        <Rect x={centre + 1} y={caseY(r.timeLossInjuries)} width={barWidth} height={top + plotH - caseY(r.timeLossInjuries)} fill={C.amber} />
        <SvgText x={centre} y={top + plotH + 12} textAnchor="middle" fontSize={6.5} fill={C.muted}>{shortMonth(r.month)}</SvgText>
      </G>; })}
      {hasRates && <Path d={linePath((r) => r.overallIncidencePer1000h)} fill="none" stroke={C.cyan} strokeWidth={2.2} />}
      {hasRates && <Path d={linePath((r) => r.incidencePer1000h)} fill="none" stroke={C.amber} strokeWidth={2.2} />}
      {rows.map((r, i) => <G key={`point-${r.month}`}>
        {r.overallIncidencePer1000h !== null && <Circle cx={x(i)} cy={rateY(r.overallIncidencePer1000h)} r={2.4} fill={C.cyan} stroke={C.white} strokeWidth={0.8} />}
        {r.incidencePer1000h !== null && <Circle cx={x(i)} cy={rateY(r.incidencePer1000h)} r={2.4} fill={C.amber} stroke={C.white} strokeWidth={0.8} />}
      </G>)}
      <SvgText x={2} y={top - 9} fontSize={6.8} fill={C.ink}>Injuries (cases)</SvgText>
      {hasRates && <SvgText x={w - 2} y={top - 9} textAnchor="end" fontSize={6.8} fill={C.ink}>Injuries per 1,000 player-hours</SvgText>}
    </Svg>
    <Legend items={[
      { label: "Overall Injuries", colour: C.cyan, shape: "bar" },
      { label: "Time Loss Injuries", colour: C.amber, shape: "bar" },
      ...(hasOverallRates ? [{ label: "Overall Incidence", colour: C.cyan, shape: "line" as const }] : []),
      ...(hasTlRates ? [{ label: "Time Loss Incidence", colour: C.amber, shape: "line" as const }] : []),
    ]} />
    <Caption>{hasRates
      ? "Bars read against the left axis in cases. Lines read against the right axis in injuries per 1,000 player-hours."
      : "Bars read against the left axis in cases. Monthly incidence is not available in this release, so no rate lines are drawn."}</Caption>
    {rows.some((row) => row.preliminaryRate) && <Caption>{PRELIMINARY_TIMELINE_NOTE}</Caption>}
  </View>;
}

function polar(cx: number, cy: number, radius: number, degrees: number) { const radians = degrees * Math.PI / 180; return { x: cx + radius * Math.cos(radians), y: cy + radius * Math.sin(radians) }; }
function arcPath(cx: number, cy: number, outer: number, inner: number, start: number, end: number) { const a = polar(cx, cy, outer, start), b = polar(cx, cy, outer, end), c = polar(cx, cy, inner, end), d = polar(cx, cy, inner, start); return `M ${a.x} ${a.y} A ${outer} ${outer} 0 0 1 ${b.x} ${b.y} L ${c.x} ${c.y} A ${inner} ${inner} 0 0 0 ${d.x} ${d.y} Z`; }
function HalfRing({ rows, colours, value = "recorded", unitHead }: { rows: readonly ReportDistributionRow[]; colours: Record<string, string>; value?: "recorded" | "timeLoss"; unitHead: string }) {
  const scoped = rows.filter((r) => r.setting === "all").map((r) => ({ ...r, value: value === "recorded" ? r.recordedInjuries : r.timeLossInjuries })).filter((r) => r.value > 0);
  const total = scoped.reduce((sum, r) => sum + r.value, 0);
  let cursor = 180;
  return <View>
    <Svg viewBox="0 0 220 108" style={{ height: 74 }}>
      {scoped.map((r, i) => { const span = total ? (r.value / total) * 180 : 0, start = cursor; cursor += span; return <Path key={r.key} d={arcPath(110, 100, 82, 53, start, cursor - 1)} fill={colours[r.key] ?? PALETTE[i % PALETTE.length]} />; })}
      <SvgText x={110} y={82} textAnchor="middle" fontSize={23} fontWeight="bold" fill={C.navy}>{total}</SvgText>
      <SvgText x={110} y={95} textAnchor="middle" fontSize={6.8} fill={C.muted}>TOTAL CASES</SvgText>
    </Svg>
    <View style={[styles.headRow, { marginTop: 7 }]}>
      <View style={{ width: 10 }} />
      <Text style={[styles.columnHead, { flex: 1 }]}>Band</Text>
      <Text style={[styles.columnHead, { width: 62, textAlign: "right" }]}>{unitHead}</Text>
    </View>
    {scoped.map((r, i) => <View key={r.key} style={styles.compactTableRow}>
      <View style={[styles.legendDot, { backgroundColor: colours[r.key] ?? PALETTE[i % PALETTE.length] }]} />
      <Text style={styles.compactLabel}>{r.label}</Text>
      <Text style={[styles.compactNumber, { width: 62 }]}>{r.value} ({total ? Math.round(r.value / total * 100) : 0}%)</Text>
    </View>)}
    <Caption>Arc length is the share each band holds of the {total} cases shown.</Caption>
  </View>;
}

function SettingBench({ rows }: { rows: readonly ReportSettingMetric[] }) {
  const colours: Record<string, string> = { match: C.cyan, training: C.mint };
  return <View style={styles.split}>{rows.map((r) => <View style={styles.half} key={r.setting}>
    <View style={styles.darkPanel}>
      <Text style={{ color: C.white, fontFamily: "Helvetica-Bold", fontSize: 12, letterSpacing: 0.3 }}>{r.label}</Text>
      <Text style={{ color: colours[r.setting] ?? C.blue, fontFamily: "Helvetica-Bold", fontSize: 21, marginTop: 6 }}>{r.timeLossInjuries}</Text>
      <Text style={{ color: "#C0D0E0", fontSize: 6.8, marginTop: 1 }}>injuries</Text>
      {([["Overall Injuries", r.recordedInjuries, "cases"], ["Incidence", r.incidencePer1000h, "/1,000 h"], ["Burden", r.burdenPer1000h, "days/1,000 h"], ["Mean Severity", r.meanSeverityDays, "days"], ["Exposure", r.exposureHours, "hours"]] as const).map(([label, amount, unit]) =>
        <View key={label} style={{ flexDirection: "row", justifyContent: "space-between", alignItems: "baseline", borderTopWidth: 1, borderTopColor: "#294565", paddingTop: 5, marginTop: 5 }}>
          <Text style={{ color: "#C0D0E0", fontSize: 6.8 }}>{label}</Text>
          <Text style={{ color: C.white, fontFamily: "Helvetica-Bold", fontSize: 6.8, paddingLeft: 8 }}>{fmt(amount, unit)}</Text>
        </View>)}
    </View>
  </View>)}</View>;
}
function CompactSettingBench({ rows }: { rows: readonly ReportSettingMetric[] }) {
  const colours: Record<string, string> = { match: C.cyan, training: C.mint };
  return <View>{rows.map((r) => <View key={r.setting} style={{ backgroundColor: C.navy, borderRadius: 4, padding: 9, marginBottom: 7 }}>
    <View style={{ flexDirection: "row", alignItems: "baseline", justifyContent: "space-between" }}>
      <Text style={{ color: C.white, fontFamily: "Helvetica-Bold", fontSize: 10.5 }}>{r.label}</Text>
      <Text style={{ color: colours[r.setting] ?? C.blue, fontFamily: "Helvetica-Bold", fontSize: 16 }}>{r.timeLossInjuries} Injuries</Text>
    </View>
    {([["Incidence", r.incidencePer1000h, "/1,000 h"], ["Burden", r.burdenPer1000h, "days/1,000 h"], ["Mean Severity", r.meanSeverityDays, "days"]] as const).map(([label, value, unit]) =>
      <View key={label} style={{ flexDirection: "row", justifyContent: "space-between", alignItems: "baseline", borderTopWidth: 1, borderTopColor: "#294565", paddingTop: 4, marginTop: 4 }}>
        <Text style={{ color: "#C0D0E0", fontSize: 6.5 }}>{label}</Text>
        <Text style={{ color: C.white, fontFamily: "Helvetica-Bold", fontSize: 6.5, paddingLeft: 6 }}>{fmt(value, unit)}</Text>
      </View>)}
  </View>)}</View>;
}

function profileColour(code: string) { let hash = 0; for (const char of code) hash = (hash * 31 + char.charCodeAt(0)) >>> 0; return PALETTE[hash % PALETTE.length]; }
function overall(rows: readonly ReportProfileRow[]) { return rows.filter((r) => r.setting === "all"); }
type ProfileMetric = "timeLossInjuries" | "incidencePer1000h" | "burdenPer1000h" | "meanSeverityDays";
function profileValue(row: ReportProfileRow, metric: ProfileMetric) { return row[metric] ?? 0; }

function RankedBars({ rows, metric = "timeLossInjuries", limit = 8, heat = false, heading, unit, rowGap = 6 }: { rows: readonly ReportProfileRow[]; metric?: ProfileMetric; limit?: number; heat?: boolean; heading: string; unit: string; rowGap?: number }) {
  const ranked = [...rows].filter((r) => profileValue(r, metric) > 0).sort((a, b) => profileValue(b, metric) - profileValue(a, metric)).slice(0, limit);
  const max = Math.max(1, ...ranked.map((r) => profileValue(r, metric)));
  return <View>
    <View style={styles.headRow}>
      <Text style={[styles.columnHead, { width: 18 }]}>#</Text>
      <Text style={[styles.columnHead, { width: 112 }]}>{heading}</Text>
      <Text style={[styles.columnHead, { flex: 1, paddingRight: 4 }]}>0 to {tickText(max)}</Text>
      <Text style={[styles.columnHead, { width: 46, textAlign: "right" }]}>{unit}</Text>
    </View>
    {ranked.map((r, i) => <View key={r.code} style={{ flexDirection: "row", alignItems: "center", marginBottom: rowGap }}>
      <Text style={{ width: 18, color: C.muted, fontSize: 6.5 }}>{String(i + 1).padStart(2, "0")}</Text>
      <Text style={{ width: 112, fontSize: 7, paddingRight: 4 }}>{r.label}</Text>
      <View style={{ flex: 1, height: 8, backgroundColor: C.track, borderRadius: 2, overflow: "hidden", marginRight: 6 }}>
        <View style={{ height: 8, width: `${profileValue(r, metric) / max * 100}%`, backgroundColor: heat ? heatColour(profileValue(r, metric), max) : C.cyan }} />
      </View>
      <Text style={{ width: 46, textAlign: "right", color: C.ink, fontFamily: "Helvetica-Bold", fontSize: 6.8 }}>{fmt(profileValue(r, metric))}</Text>
    </View>)}
  </View>;
}

const BODY_PATHS: Array<{ code: string; d?: string; circle?: [number, number, number]; rect?: [number, number, number, number, number] }> = [
  { code: "head", circle: [60,25,20] }, { code: "neck", rect: [51,45,18,17,6] }, { code: "shoulder", d: "M24 70 Q42 57 60 58 Q78 57 96 70 L91 88 Q75 78 60 79 Q45 78 29 88 Z" }, { code: "upper_arm", d: "M25 74 Q17 80 15 111 L24 145 L38 141 L36 91 Z M95 74 Q103 80 105 111 L96 145 L82 141 L84 91 Z" }, { code: "elbow", d: "M17 143 Q26 136 35 143 L34 158 Q26 164 18 157 Z M85 143 Q94 136 103 143 L102 158 Q94 164 86 157 Z" }, { code: "forearm", d: "M18 157 L34 157 L31 205 L19 205 Z M86 157 L102 157 L101 205 L89 205 Z" }, { code: "wrist", d: "M19 204 H31 V214 H19 Z M89 204 H101 V214 H89 Z" }, { code: "hand", d: "M17 213 Q25 208 33 214 L30 239 Q25 248 20 239 Z M87 214 Q95 208 103 213 L100 239 Q95 248 90 239 Z" }, { code: "chest", d: "M36 76 Q60 69 84 76 L82 124 Q60 133 38 124 Z" }, { code: "abdomen", d: "M39 125 Q60 133 81 125 L78 175 Q60 184 42 175 Z" }, { code: "hip_groin", d: "M42 175 Q60 183 78 175 L84 201 L66 214 L60 200 L54 214 L36 201 Z" }, { code: "thigh", d: "M37 199 L57 207 L54 280 L33 280 Z M63 207 L83 199 L87 280 L66 280 Z" }, { code: "knee", d: "M33 278 H55 L56 300 H34 Z M65 300 L66 278 H87 L86 300 Z" }, { code: "lower_leg", d: "M34 299 H56 L52 365 H37 Z M64 299 H86 L83 365 H68 Z" }, { code: "ankle", d: "M37 362 H52 L51 376 H37 Z M68 362 H83 V376 H69 Z" }, { code: "foot", d: "M37 374 H51 L48 389 H25 Q22 383 30 379 Z M69 374 H83 L90 379 Q98 383 95 389 H72 Z" },
];
const BACK_PATHS = BODY_PATHS.filter((shape) => shape.code !== "chest" && shape.code !== "abdomen").concat([
  { code: "thoracic_spine", d: "M38 76 Q60 69 82 76 L80 130 Q60 139 40 130 Z M56 78 H64 V132 H56 Z" },
  { code: "lumbosacral", d: "M40 131 Q60 139 80 131 L77 176 Q60 186 43 176 Z M54 145 H66 V178 H54 Z" },
]);
/** The continuous ramp sampled at five stops, so the printed key stays short. */
function heatLegend(max: number): LegendItem[] {
  return [
    { label: "No Injuries", colour: NO_CASE_FILL, shape: "swatch" as const },
    ...heatScaleStops(max).map((stop) => ({ label: `${stop.value} case${stop.value === 1 ? "" : "s"}`, colour: stop.colour, shape: "swatch" as const })),
  ];
}
function BodyMapPdf({ rows, chartHeight = 300 }: { rows: readonly ReportProfileRow[]; chartHeight?: number }) {
  const byCode = new Map(rows.map((r) => [r.code, r])), max = Math.max(1, ...rows.map((r) => r.timeLossInjuries));
  const figure = (shapes: typeof BODY_PATHS, offset: number, label: string) => <G transform={`translate(${offset} 14)`}>
    <SvgText x={60} y={-3} textAnchor="middle" fontSize={10} fill={C.ink}>{label}</SvgText>
    {shapes.map((shape) => {
      const props = { fill: heatColour(byCode.get(shape.code)?.timeLossInjuries ?? 0, max), stroke: C.white, strokeWidth: 1 };
      if (shape.circle) return <Circle key={`${label}-${shape.code}`} cx={shape.circle[0]} cy={shape.circle[1]} r={shape.circle[2]} {...props} />;
      if (shape.rect) return <Rect key={`${label}-${shape.code}`} x={shape.rect[0]} y={shape.rect[1]} width={shape.rect[2]} height={shape.rect[3]} rx={shape.rect[4]} {...props} />;
      return <Path key={`${label}-${shape.code}`} d={shape.d ?? ""} {...props} />;
    })}
  </G>;
  return <View>
    <Svg viewBox="0 0 270 422" style={{ height: chartHeight }}>{figure(BODY_PATHS, 5, "Front")}{figure(BACK_PATHS, 140, "Back")}</Svg>
    <Legend items={heatLegend(max)} />
    <Caption>Shading is the injury count for each region, from 0 to {max} cases.</Caption>
  </View>;
}

/** Only the fields the split needs, so injury-type families fit without widening. */
type SplitRow = Pick<ReportProfileRow, "code" | "label" | "setting" | "timeLossInjuries">;
function MirroredBars({ rows, rowGap = 6, heading }: { rows: readonly SplitRow[]; rowGap?: number; heading: string }) {
  // The union of the released match and training rows, as the dashboard split
  // takes it: a category reported by only one setting still appears, with a true
  // zero on the setting that did not report it.
  const match = new Map(rows.filter((r) => r.setting === "match").map((r) => [r.code, r]));
  const training = new Map(rows.filter((r) => r.setting === "training").map((r) => [r.code, r]));
  const paired = [...new Set([...match.keys(), ...training.keys()])]
    .map((code) => {
      const matchRow = match.get(code), trainingRow = training.get(code);
      return {
        code,
        label: matchRow?.label ?? trainingRow?.label ?? code,
        match: matchRow?.timeLossInjuries ?? 0,
        training: trainingRow?.timeLossInjuries ?? 0,
      };
    })
    .filter((r) => r.match > 0 || r.training > 0)
    .sort((a, b) => Math.max(b.match, b.training) - Math.max(a.match, a.training) || a.label.localeCompare(b.label));
  const max = Math.max(1, ...paired.map((r) => Math.max(r.match, r.training)));
  return <View>
    <View style={styles.headRow}>
      <View style={{ width: 22 }} />
      <Text style={[styles.columnHead, { flex: 1, textAlign: "right", paddingRight: 5, color: C.cyan }]}>Match, {tickText(max)} to 0 cases</Text>
      <Text style={[styles.columnHead, { width: 92, textAlign: "center" }]}>{heading}</Text>
      <Text style={[styles.columnHead, { flex: 1, paddingLeft: 5, color: C.mint }]}>Training, 0 to {tickText(max)} cases</Text>
      <View style={{ width: 22 }} />
    </View>
    {paired.map((r) => <View key={r.code} style={{ flexDirection: "row", alignItems: "center", marginBottom: rowGap }}>
      <Text style={{ width: 22, textAlign: "right", paddingRight: 4, color: C.ink, fontSize: 6.8 }}>{r.match}</Text>
      <View style={{ flex: 1, height: 11, alignItems: "flex-end", backgroundColor: C.track, marginRight: 5 }}>
        <View style={{ width: `${r.match / max * 100}%`, height: 11, backgroundColor: C.cyan }} />
      </View>
      <Text style={{ width: 92, textAlign: "center", fontSize: 6.6, lineHeight: 1.15 }}>{r.label}</Text>
      <View style={{ flex: 1, height: 11, backgroundColor: C.track, marginLeft: 5 }}>
        <View style={{ width: `${r.training / max * 100}%`, height: 11, backgroundColor: C.mint }} />
      </View>
      <Text style={{ width: 22, paddingLeft: 4, color: C.ink, fontSize: 6.8 }}>{r.training}</Text>
    </View>)}
    <Legend items={[{ label: "Match Injuries", colour: C.cyan, shape: "bar" }, { label: "Training Injuries", colour: C.mint, shape: "bar" }]} />
    <Caption>Both sides use one shared scale of 0 to {tickText(max)} injuries. Match reads right to left, training reads left to right.</Caption>
  </View>;
}

/** ReportProfileRow reshaped to the released row field names the shared dashboard resolver reads. */
function colourInput(rows: readonly ReportProfileRow[]) {
  return rows.map((row) => ({
    code: row.code,
    label: row.label,
    setting: row.setting,
    time_loss_injuries: row.timeLossInjuries,
    incidence_per_1000h: row.incidencePer1000h,
    burden_per_1000h: row.burdenPer1000h,
    mean_severity_days: row.meanSeverityDays,
  }));
}
type ColourRow = ReturnType<typeof colourInput>[number];
const LANE_METRICS: Array<{ metric: keyof ColourRow & string; label: string; unit: string }> = [
  { metric: "time_loss_injuries", label: "Count", unit: "cases" },
  { metric: "incidence_per_1000h", label: "Incidence", unit: "per 1,000 h" },
  { metric: "burden_per_1000h", label: "Burden", unit: "days per 1,000 h" },
  { metric: "mean_severity_days", label: "Severity", unit: "mean days" },
];

/**
 * The four ranked lanes. Colours are resolved from every released setting, not
 * only the overall rows shown here, so a diagnosis carries the same colour in
 * the PDF as it does on the dashboard.
 */
function CommonLanes({ rows }: { rows: readonly ReportProfileRow[] }) {
  const colours = commonInjuryColorMap(colourInput(rows));
  const overallRows = colourInput(rows.filter((row) => row.setting === "all"));
  return <View style={{ flexDirection: "row", marginHorizontal: -3 }}>
    {LANE_METRICS.map((lane) => {
      const ranked = rankedCommonInjuries(overallRows, lane.metric);
      return <View key={lane.metric} style={{ width: "25%", paddingHorizontal: 3 }}>
        <View style={[styles.headRow, { flexDirection: "column", alignItems: "flex-start" }]}>
          <Text style={styles.panelTitle}>{lane.label}</Text>
          <Text style={styles.columnHead}>{lane.unit}</Text>
        </View>
        {ranked.map((row, index) => {
          // The dashboard darkens each palette colour by mixing 10% black, so the
          // PDF composites the same mix rather than filling with the raw palette
          // entry. Only the text colour is re-picked, for legibility.
          const fill = cardFill(colours.get(row.code)?.background ?? C.navy);
          const text = readableOn(fill);
          // Same compact card as the illness lanes: the label grows to as many
          // lines as it needs and the value sits directly under it.
          return <View key={row.code} style={{ backgroundColor: fill, borderRadius: 3, padding: 5, minHeight: 62, marginBottom: 4, flexShrink: 0 }}>
            <Text style={{ color: text, fontFamily: "Helvetica-Bold", fontSize: 6.8, lineHeight: 1.2 }}>{index + 1}. {row.label}</Text>
            <Text style={{ color: text, fontFamily: "Helvetica-Bold", fontSize: 12.5, marginTop: 4 }}>{fmt(row[lane.metric] as number | null)}</Text>
          </View>;
        })}
      </View>;
    })}
  </View>;
}

/**
 * The plotted rows arrive already selected and ordered by the report model,
 * using the dashboard's inclusion threshold and its knee-ligament retention.
 * Only rows without a placeable coordinate are dropped here.
 */
function impactRows(rows: readonly ReportProfileRow[]) {
  return rows.filter((r) => finiteNumber(r.incidencePer1000h) && finiteNumber(r.meanSeverityDays));
}
type LabelSpot = { x: number; y: number; offset: boolean };
/**
 * Data points stay on their exact coordinates. Only the numeral moves when
 * circles overlap, and a leader line ties the moved numeral back to its point.
 * Every numeral is placed inside the plot: candidates run outward in rings, and
 * when no candidate is fully clear the least crowded in-bounds one wins rather
 * than a fallback that could sit outside the axes.
 */
function placeLabels(points: Array<{ x: number; y: number }>, radius: number, bounds: { x0: number; y0: number; x1: number; y1: number }): LabelSpot[] {
  const rings = [radius + 7, radius + 15, radius + 24, radius + 34, radius + 46, radius + 60];
  const angles = [-90, 0, 90, 180, -45, -135, 45, 135, -22.5, 22.5, 157.5, -157.5, 67.5, 112.5, -67.5, -112.5];
  const offsets: Array<[number, number]> = [[0, 0]];
  for (const ring of rings) for (const angle of angles) {
    offsets.push([Math.cos(angle * Math.PI / 180) * ring, Math.sin(angle * Math.PI / 180) * ring]);
  }
  const inset = 6;
  const placed: LabelSpot[] = [];
  return points.map((point, index) => {
    const crowded = points.some((other, j) => j !== index && Math.hypot(other.x - point.x, other.y - point.y) < radius * 2);
    const candidates = crowded ? offsets.slice(1) : offsets;
    let best: [number, number] | null = null, bestScore = -Infinity;
    for (const [dx, dy] of candidates) {
      const x = point.x + dx, y = point.y + dy;
      if (x < bounds.x0 + inset || x > bounds.x1 - inset || y < bounds.y0 + inset || y > bounds.y1 - inset) continue;
      const labelClear = placed.length ? Math.min(...placed.map((spot) => Math.hypot(spot.x - x, spot.y - y))) : Infinity;
      const pointClear = Math.min(Infinity, ...points.filter((_, j) => j !== index).map((other) => Math.hypot(other.x - x, other.y - y)));
      if (labelClear >= 9 && pointClear >= radius + 4) { best = [dx, dy]; break; }
      const score = Math.min(labelClear, pointClear);
      if (score > bestScore) { bestScore = score; best = [dx, dy]; }
    }
    const choice = best ?? [
      Math.min(Math.max(point.x, bounds.x0 + inset), bounds.x1 - inset) - point.x,
      Math.min(Math.max(point.y, bounds.y0 + inset), bounds.y1 - inset) - point.y,
    ];
    const spot: LabelSpot = { x: point.x + choice[0], y: point.y + choice[1], offset: choice[0] !== 0 || choice[1] !== 0 };
    placed.push(spot);
    return spot;
  });
}

/**
 * The dashboard risk matrix on paper: one navy series over the impact-zone
 * gradient, full page width, with the numbered key underneath. Both axes are
 * linear on rounded bounds taken from the plotted rows, so clustered points
 * spread out; an axis that does not reach zero carries an explicit break mark.
 */
function ImpactMatrix({ rows, chartHeight = 250, gradientId }: { rows: readonly ReportProfileRow[]; chartHeight?: number; gradientId: string }) {
  const data = impactRows(rows);
  const w = 517, h = chartHeight, left = 46, top = 22, right = 16, bottom = 34;
  const plotW = w - left - right, plotH = h - top - bottom;
  const xScale = linearDomain(data.map((r) => r.incidencePer1000h ?? 0));
  const yScale = linearDomain(data.map((r) => r.meanSeverityDays ?? 0));
  const px = (v: number) => left + (v - xScale.low) / (xScale.high - xScale.low) * plotW;
  const py = (v: number) => top + plotH - (v - yScale.low) / (yScale.high - yScale.low) * plotH;
  const radius = 6.5;
  const points = data.map((r) => ({ x: px(r.incidencePer1000h ?? 0), y: py(r.meanSeverityDays ?? 0) }));
  const labels = placeLabels(points, radius, { x0: left, y0: top, x1: left + plotW, y1: top + plotH });
  const breaks = [xScale.broken ? "incidence" : "", yScale.broken ? "mean severity" : ""].filter(Boolean);
  const sparse = data.some((r) => r.timeLossInjuries <= 2);
  return <View>
    <Svg viewBox={`0 0 ${w} ${h}`} style={{ height: h }}>
      <Defs>
        <LinearGradient id={gradientId} x1="0" y1="1" x2="1" y2="0">
          {RISK_ZONE_STOPS.map((stop) => <Stop key={stop.offset} offset={stop.offset} stopColor={stop.colour} stopOpacity={0.25} />)}
        </LinearGradient>
      </Defs>
      <Rect x={left} y={top} width={plotW} height={plotH} fill={C.white} stroke={C.line} strokeWidth={0.8} />
      <Rect x={left} y={top} width={plotW} height={plotH} fill={`url(#${gradientId})`} />
      {yScale.ticks.map((tick) => <G key={`y-${tick}`}>
        <Line x1={left} x2={left + plotW} y1={py(tick)} y2={py(tick)} stroke={C.rule} strokeWidth={0.7} />
        <SvgText x={left - 5} y={py(tick) + 2.4} textAnchor="end" fontSize={6.5} fill={C.muted}>{tickText(tick)}</SvgText>
      </G>)}
      {xScale.ticks.map((tick) => <G key={`x-${tick}`}>
        <Line x1={px(tick)} x2={px(tick)} y1={top} y2={top + plotH} stroke={C.rule} strokeWidth={0.7} />
        <SvgText x={px(tick)} y={top + plotH + 11} textAnchor="middle" fontSize={6.5} fill={C.muted}>{tickText(tick)}</SvgText>
      </G>)}
      {/* The conventional double slash: this axis starts above zero. */}
      {xScale.broken && <G>
        <Line x1={left - 9} x2={left - 5} y1={top + plotH + 4} y2={top + plotH - 3} stroke={C.ink} strokeWidth={0.9} />
        <Line x1={left - 6} x2={left - 2} y1={top + plotH + 4} y2={top + plotH - 3} stroke={C.ink} strokeWidth={0.9} />
      </G>}
      {yScale.broken && <G>
        <Line x1={left - 4} x2={left + 3} y1={top + plotH + 9} y2={top + plotH + 5} stroke={C.ink} strokeWidth={0.9} />
        <Line x1={left - 4} x2={left + 3} y1={top + plotH + 6} y2={top + plotH + 2} stroke={C.ink} strokeWidth={0.9} />
      </G>}
      {points.map((point, i) => { const spot = labels[i]; if (!spot.offset) return null; const angle = Math.atan2(spot.y - point.y, spot.x - point.x); return <Line key={`leader-${data[i].code}`} x1={point.x + Math.cos(angle) * radius} y1={point.y + Math.sin(angle) * radius} x2={spot.x - Math.cos(angle) * 4.5} y2={spot.y - Math.sin(angle) * 4.5} stroke={C.ink} strokeWidth={0.5} />; })}
      {data.map((r, i) => <Circle key={r.code} cx={points[i].x} cy={points[i].y} r={radius} fill={MATRIX_DOT} stroke={C.white} strokeWidth={1.2} />)}
      {data.map((r, i) => { const spot = labels[i]; return <SvgText key={`n-${r.code}`} x={spot.x} y={spot.y + 2.3} textAnchor="middle" fontSize={6.5} fontWeight="bold" fill={spot.offset ? C.ink : C.white}>{i + 1}</SvgText>; })}
      <SvgText x={2} y={top - 8} fontSize={6.8} fill={C.ink}>Mean Severity, Days</SvgText>
      <SvgText x={left + plotW / 2} y={h - 3} textAnchor="middle" fontSize={6.8} fill={C.ink}>Incidence, Injuries /1,000 h</SvgText>
    </Svg>
    <Legend items={[
      { label: "Lower Incidence And Severity", colour: "#A9E2C7", shape: "swatch" },
      { label: "One Measure Elevated", colour: "#F1EBBF", shape: "swatch" },
      { label: "Higher Incidence And Severity", colour: "#F4C3C4", shape: "swatch" },
    ]} />
    <Caption>Key numbers run highest injury count first, and each key row ends with the burden for that group in days per 1,000 player-hours.{breaks.length ? ` The ${breaks.join(" and ")} axis does not start at zero, marked by the break on the axis.` : ""}{sparse ? " Interpret groups based on one or two injuries cautiously." : ""}</Caption>
    <View style={{ flexDirection: "row", flexWrap: "wrap", marginTop: 5, borderTopWidth: 1, borderTopColor: C.rule, paddingTop: 5 }}>
      {data.map((r, i) => <View key={`key-${r.code}`} style={{ width: "25%", flexDirection: "row", alignItems: "center", paddingRight: 6, marginBottom: 4, flexShrink: 0 }}>
        <View style={{ width: 11, height: 11, borderRadius: 5.5, backgroundColor: MATRIX_DOT, alignItems: "center", justifyContent: "center", marginRight: 4 }}>
          <Text style={{ color: C.white, fontFamily: "Helvetica-Bold", fontSize: 6 }}>{i + 1}</Text>
        </View>
        <Text style={{ flex: 1, fontSize: 6.2, lineHeight: 1.15 }}>{r.label}</Text>
        <Text style={{ color: C.muted, fontSize: 6.2, paddingLeft: 3 }}>{fmt(r.burdenPer1000h)}</Text>
      </View>)}
    </View>
  </View>;
}

function FamilyRanking({ rows, rowGap = 10 }: { rows: readonly ReportInjuryTypeFamily[]; rowGap?: number }) {
  const ranked = rows.filter((r) => r.setting === "all" && r.timeLossInjuries > 0).sort((a, b) => b.timeLossInjuries - a.timeLossInjuries);
  const max = Math.max(1, ...ranked.map((r) => r.timeLossInjuries));
  return <View>
    <View style={styles.headRow}>
      <Text style={[styles.columnHead, { flex: 1 }]}>Injury family</Text>
      <Text style={styles.columnHead}>Cases | per 1,000 h</Text>
    </View>
    {ranked.map((r, i) => <View key={r.code} style={{ marginBottom: rowGap }}>
      <View style={{ flexDirection: "row", justifyContent: "space-between", alignItems: "baseline" }}>
        <Text style={{ fontSize: 7 }}>{i + 1}. {r.label}</Text>
        <Text style={{ color: C.ink, fontFamily: "Helvetica-Bold", fontSize: 6.8, paddingLeft: 8 }}>{r.timeLossInjuries} | {fmt(r.incidencePer1000h)}</Text>
      </View>
      <View style={{ height: 8, backgroundColor: C.track, marginTop: 3 }}><View style={{ height: 8, width: `${r.timeLossInjuries / max * 100}%`, backgroundColor: profileColour(r.code) }} /></View>
    </View>)}
    <Caption>Bars are injuries on a shared scale of 0 to {tickText(max)}.</Caption>
  </View>;
}
function FamilyDossier({ rows }: { rows: readonly ReportInjuryTypeFamily[] }) {
  const lead = rows.filter((r) => r.setting === "all").sort((a, b) => b.timeLossInjuries - a.timeLossInjuries)[0];
  if (!lead) return <Text style={styles.panelNote}>Not available</Text>;
  return <View>
    <View style={styles.darkPanel}>
      <Text style={{ color: C.cyan, fontSize: 6.8, letterSpacing: 1, fontFamily: "Helvetica-Bold" }}>LEADING FAMILY</Text>
      <Text style={{ color: C.white, fontFamily: "Helvetica-Bold", fontSize: 16, marginTop: 5 }}>{lead.label}</Text>
      <View style={{ flexDirection: "row", marginTop: 10 }}>{([["Injuries", lead.timeLossInjuries, "cases"], ["Incidence", lead.incidencePer1000h, "per 1,000 h"], ["Burden", lead.burdenPer1000h, "days per 1,000 h"], ["Mean Severity", lead.meanSeverityDays, "days"]] as const).map(([label, value, unit]) =>
        <View key={label} style={{ width: "25%", paddingRight: 6 }}>
          <Text style={{ color: C.white, fontFamily: "Helvetica-Bold", fontSize: 12 }}>{fmt(value)}</Text>
          <Text style={{ color: "#C0D0E0", fontSize: 6.5, marginTop: 2, lineHeight: 1.2 }}>{label}</Text>
          <Text style={{ color: "#8FA6BE", fontSize: 6.5, lineHeight: 1.2 }}>{unit}</Text>
        </View>)}</View>
    </View>
    <Text style={[styles.panelTitle, { marginTop: 10 }]}>Subtype detail</Text>
    <View style={styles.headRow}>
      <Text style={[styles.columnHead, { flex: 1 }]}>Subtype</Text>
      <Text style={[styles.columnHead, { width: 58, textAlign: "right" }]}>Cases</Text>
      <Text style={[styles.columnHead, { width: 58, textAlign: "right" }]}>Days lost</Text>
    </View>
    {lead.subtypes.filter((r) => r.timeLossInjuries > 0).map((r) => <View key={r.code} style={styles.compactTableRow}>
      <Text style={styles.compactLabel}>{r.label}</Text>
      <Text style={styles.compactNumber}>{r.timeLossInjuries}</Text>
      <Text style={styles.compactNumber}>{fmt(r.daysLost)}</Text>
    </View>)}
  </View>;
}

type ComparisonKey = "matchIncidencePer1000h" | "matchBurdenPer1000h" | "trainingIncidencePer1000h" | "trainingBurdenPer1000h";
const heatColumns: Array<{ key: ComparisonKey; label: string; unit: string }> = [
  { key: "matchIncidencePer1000h", label: "Match incidence", unit: "per 1,000 h" },
  { key: "matchBurdenPer1000h", label: "Match burden", unit: "days per 1,000 h" },
  { key: "trainingIncidencePer1000h", label: "Training incidence", unit: "per 1,000 h" },
  { key: "trainingBurdenPer1000h", label: "Training burden", unit: "days per 1,000 h" },
];
const HEAT_NEUTRAL = "#E4EBF1", HEAT_AMBER = "#C98A16";
function benchmarkColour(value: number | null, mean: number | null) { if (value === null || mean === null || mean <= 0) return HEAT_NEUTRAL; if (value <= mean * .9) return C.green; if (value >= mean * 1.1) return C.red; return HEAT_AMBER; }
function Heatmap({ model, rowHeight = 16 }: { model: ReportModel; rowHeight?: number }) {
  return <View>
    <View style={[styles.heatRow, { minHeight: 30, borderBottomColor: C.navy, borderLeftWidth: 2.5, borderLeftColor: C.white, alignItems: "flex-end", paddingBottom: 3 }]}>
      <Text style={[styles.heatName, styles.columnHead, { width: 118 }]}>Club</Text>
      {heatColumns.map((c) => <View key={c.key} style={{ flex: 1, paddingHorizontal: 2 }}>
        <Text style={[styles.columnHead, { textAlign: "center" }]}>{c.label}</Text>
        <Text style={[styles.columnHead, { textAlign: "center", color: C.grey }]}>{c.unit}</Text>
      </View>)}
    </View>
    {model.comparisonHeatmap.map((r, i) => <View key={`${r.label}-${i}`} style={[styles.heatRow, { minHeight: rowHeight, borderLeftWidth: 2.5, borderLeftColor: r.isSubject ? model.brand.accentColour : C.white }, r.isSubject ? { backgroundColor: "#EDF3F9" } : {}]}>
      <Text style={[styles.heatName, { width: 118 }, r.isSubject ? { fontFamily: "Helvetica-Bold", color: model.brand.accentColour } : {}]}>{r.label}</Text>
      {heatColumns.map((c) => { const colour = benchmarkColour(r[c.key], model.comparisonBenchmarks[c.key]); return <Text key={c.key} style={[styles.heatCell, { backgroundColor: colour, color: colour === HEAT_NEUTRAL ? C.ink : C.white }]}>{fmt(r[c.key])}</Text>; })}
    </View>)}
    <Legend items={[
      { label: "Below mean", colour: C.green, shape: "swatch" },
      { label: "Within 10%", colour: HEAT_AMBER, shape: "swatch" },
      { label: "Above mean", colour: C.red, shape: "swatch" },
      { label: "Not available", colour: HEAT_NEUTRAL, shape: "swatch" },
    ]} />
    <Caption>Below and above mean the value differs from the released league mean by at least 10%.{model.comparisonHeatmap.some((row) => row.isSubject) ? ` ${model.subjectName} carries the accent rule, and every other club keeps its approved dashboard alias.` : " Every club keeps its approved dashboard alias."}</Caption>
  </View>;
}
function ComparisonScatter({ model, chartHeight = 275 }: { model: ReportModel; chartHeight?: number }) {
  const data = model.comparisonHeatmap.filter((r) => r.matchIncidencePer1000h !== null && r.trainingIncidencePer1000h !== null);
  const w = 517, h = chartHeight, left = 46, top = 24, right = 14, bottom = 40;
  const plotW = w - left - right, plotH = h - top - bottom;
  const xScale = niceScale(Math.max(1, ...data.map((r) => r.matchIncidencePer1000h ?? 0)));
  const yScale = niceScale(Math.max(1, ...data.map((r) => r.trainingIncidencePer1000h ?? 0)));
  const px = (v: number) => left + v / xScale.top * plotW, py = (v: number) => top + plotH - v / yScale.top * plotH;
  const meanX = model.comparisonBenchmarks.matchIncidencePer1000h ?? 0, meanY = model.comparisonBenchmarks.trainingIncidencePer1000h ?? 0;
  const maxExposure = Math.max(1, ...data.map((r) => r.exposureHours ?? 0));
  const subject = data.find((r) => r.isSubject);
  return <View>
    <Svg viewBox={`0 0 ${w} ${h}`} style={{ height: h }}>
      <Rect x={left} y={top} width={plotW} height={plotH} fill={C.white} stroke={C.line} strokeWidth={0.8} />
      {yScale.ticks.map((tick) => <G key={`y-${tick}`}>
        <Line x1={left} x2={left + plotW} y1={py(tick)} y2={py(tick)} stroke={C.rule} strokeWidth={0.8} />
        <SvgText x={left - 5} y={py(tick) + 2.4} textAnchor="end" fontSize={6.5} fill={C.muted}>{tickText(tick)}</SvgText>
      </G>)}
      {xScale.ticks.map((tick) => <G key={`x-${tick}`}>
        <Line x1={px(tick)} x2={px(tick)} y1={top} y2={top + plotH} stroke={C.rule} strokeWidth={0.8} />
        <SvgText x={px(tick)} y={top + plotH + 12} textAnchor="middle" fontSize={6.5} fill={C.muted}>{tickText(tick)}</SvgText>
      </G>)}
      <Line x1={px(meanX)} x2={px(meanX)} y1={top} y2={top + plotH} stroke={C.coral} strokeWidth={1} strokeDasharray="4 3" />
      <Line x1={left} x2={left + plotW} y1={py(meanY)} y2={py(meanY)} stroke={C.coral} strokeWidth={1} strokeDasharray="4 3" />
      {data.map((r, i) => <Circle key={`${r.label}-${i}`} cx={px(r.matchIncidencePer1000h ?? 0)} cy={py(r.trainingIncidencePer1000h ?? 0)} r={4 + Math.sqrt((r.exposureHours ?? 0) / maxExposure) * 8} fill={r.isSubject ? model.brand.accentColour : C.blue} opacity={r.isSubject ? 1 : 0.55} stroke={C.white} strokeWidth={1} />)}
      {subject && (() => {
        // The point stays put; the name is offset with a leader line and flips
        // to the inside of the plot when the club sits near the right edge.
        const sx = px(subject.matchIncidencePer1000h ?? 0), sy = py(subject.trainingIncidencePer1000h ?? 0);
        const flip = sx > left + plotW * 0.62, side = flip ? -1 : 1;
        return <G>
          <Line x1={sx + 8 * side} y1={sy - 6} x2={sx + 17 * side} y2={sy - 14} stroke={model.brand.accentColour} strokeWidth={0.6} />
          <SvgText x={sx + 19 * side} y={sy - 12} textAnchor={flip ? "end" : "start"} fontSize={8} fontWeight="bold" fill={model.brand.accentColour}>{model.subjectName}</SvgText>
        </G>;
      })()}
      <SvgText x={2} y={top - 9} fontSize={6.8} fill={C.ink}>Training Incidence (per 1,000 player-hours)</SvgText>
      <SvgText x={left + plotW / 2} y={h - 5} textAnchor="middle" fontSize={6.8} fill={C.ink}>Match Incidence (injuries per 1,000 player-hours)</SvgText>
    </Svg>
    <Legend items={[
      ...(subject ? [{ label: model.subjectName, colour: model.brand.accentColour }] : []),
      { label: subject ? "Other Teams" : "Teams", colour: C.blue },
      { label: `League mean, match ${fmt(meanX)} and training ${fmt(meanY)}`, colour: C.coral, shape: "line" as const },
    ]} />
    <Caption>Bubble area is exposure hours, from the smallest club to {fmt(maxExposure, "hours", 0)}.</Caption>
  </View>;
}

function ExposureTrend({ model, chartHeight = 218 }: { model: ReportModel; chartHeight?: number }) {
  const rows = model.exposure.monthly;
  const w = 517, h = chartHeight, left = 46, top = 24, right = 54, bottom = 36;
  const plotW = w - left - right, plotH = h - top - bottom;
  const hours = niceScale(Math.max(1, ...rows.map((r) => r.exposureHours ?? 0)));
  const distance = niceScale(Math.max(1, ...rows.map((r) => r.distanceKm ?? 0)));
  const slot = plotW / Math.max(1, rows.length), x = (i: number) => left + slot * i + slot / 2;
  const hoursY = (v: number) => top + plotH - v / hours.top * plotH, distY = (v: number) => top + plotH - v / distance.top * plotH;
  const barWidth = Math.min(26, slot * 0.45);
  return <View>
    <Svg viewBox={`0 0 ${w} ${h}`} style={{ height: h }}>
      <Rect x={left} y={top} width={plotW} height={plotH} fill={C.white} stroke={C.line} strokeWidth={0.8} />
      {hours.ticks.map((tick) => <G key={`h-${tick}`}>
        <Line x1={left} x2={left + plotW} y1={hoursY(tick)} y2={hoursY(tick)} stroke={C.rule} strokeWidth={0.8} />
        <SvgText x={left - 5} y={hoursY(tick) + 2.4} textAnchor="end" fontSize={6.5} fill={C.muted}>{tickText(tick)}</SvgText>
      </G>)}
      {distance.ticks.map((tick) => <G key={`d-${tick}`}>
        <Line x1={left + plotW} x2={left + plotW + 3} y1={distY(tick)} y2={distY(tick)} stroke={C.line} strokeWidth={0.8} />
        <SvgText x={left + plotW + 6} y={distY(tick) + 2.4} fontSize={6.5} fill={C.muted}>{tickText(tick)}</SvgText>
      </G>)}
      {rows.map((r, i) => <G key={r.month}>
        <Rect x={x(i) - barWidth - 1} y={hoursY(r.exposureHours ?? 0)} width={barWidth} height={top + plotH - hoursY(r.exposureHours ?? 0)} fill={C.mint} />
        {r.distanceKm !== null && <Rect x={x(i) + 1} y={distY(r.distanceKm)} width={barWidth} height={top + plotH - distY(r.distanceKm)} fill={C.cyan} />}
        {r.distanceKm !== null && r.hsrDistanceKm !== null && r.distanceKm > 0 && (() => {
          const insetHeight = Math.min(top + plotH - distY(r.distanceKm), Math.max((r.hsrDistanceKm / r.distanceKm) * (top + plotH - distY(r.distanceKm)), r.hsrDistanceKm > 0 ? 2 : 0));
          return <Rect x={x(i) + 1} y={top + plotH - insetHeight} width={barWidth} height={insetHeight} fill={C.hsr} />;
        })()}
        {r.hsrPercentage !== null && r.distanceKm !== null && <SvgText x={x(i) + barWidth / 2 + 1} y={distY(r.distanceKm) - 3} textAnchor="middle" fontSize={5.8} fontWeight="bold" fill={C.muted}>{fmt(r.hsrPercentage, "%")}</SvgText>}
        <SvgText x={x(i)} y={top + plotH + 12} textAnchor="middle" fontSize={6.5} fill={C.muted}>{shortMonth(r.month)}</SvgText>
      </G>)}
      <SvgText x={2} y={top - 9} fontSize={6.8} fill={C.ink}>Player-hours</SvgText>
      <SvgText x={w - 2} y={top - 9} textAnchor="end" fontSize={6.8} fill={C.ink}>Distance (km)</SvgText>
    </Svg>
    <Legend items={[{ label: "Hours (left axis)", colour: C.mint, shape: "bar" }, { label: "Total Distance (right axis)", colour: C.cyan, shape: "bar" }, { label: "HSR Distance", colour: C.hsr, shape: "bar" }]} />
    <Caption>Monthly released exposure across {monthRange(rows)}. Each percentage is HSR as a share of that month's total distance, and the HSR inset is part of total distance rather than additional distance.{rows.some((r) => r.isImputed) ? " Months drawn from a league-mean placeholder are named in the display note above." : ""}</Caption>
  </View>;
}
function ExposureLadder({ model, keyName, label, unit, colour, rowGap = 9 }: { model: ReportModel; keyName: "exposureHours" | "distanceKm"; label: string; unit: string; colour: string; rowGap?: number }) {
  const rows = model.comparisonHeatmap.filter((r) => r[keyName] !== null).sort((a, b) => (b[keyName] ?? 0) - (a[keyName] ?? 0));
  const max = Math.max(1, ...rows.map((r) => r[keyName] ?? 0));
  return <View>
    <View style={styles.headRow}>
      <Text style={[styles.columnHead, { width: 15 }]}>#</Text>
      <Text style={[styles.columnHead, { width: 74 }]}>Club</Text>
      <Text style={[styles.columnHead, { flex: 1 }]}>0 to {fmt(max, "", 0)}</Text>
      <Text style={[styles.columnHead, { width: 36, textAlign: "right" }]}>{unit}</Text>
    </View>
    {rows.map((r, i) => <View key={`${r.label}-${i}`} style={{ flexDirection: "row", alignItems: "center", marginBottom: rowGap }}>
      <Text style={{ width: 15, color: C.muted, fontSize: 6.5 }}>{i + 1}</Text>
      <Text style={{ width: 74, color: r.isSubject ? model.brand.accentColour : C.ink, fontFamily: r.isSubject ? "Helvetica-Bold" : "Helvetica", fontSize: 6.5, paddingRight: 3 }}>{r.label}</Text>
      <View style={{ flex: 1, height: 7, backgroundColor: C.track, marginRight: 5 }}><View style={{ height: 7, width: `${(r[keyName] ?? 0) / max * 100}%`, backgroundColor: r.isSubject ? model.brand.accentColour : colour }} /></View>
      <Text style={{ width: 36, textAlign: "right", fontSize: 6.5 }}>{fmt(r[keyName], "", 0)}</Text>
    </View>)}
    <Caption>{label} for every club in the released cohort, on a shared scale.</Caption>
  </View>;
}
function finiteNumber(value: number | null | undefined): value is number {
  return typeof value === "number" && Number.isFinite(value);
}

function comparisonDomain(values: Array<number | null>, zeroFloor = false): [number, number] {
  const usable = values.filter(finiteNumber);
  if (!usable.length) return [0, 1];
  const low = Math.min(...usable), high = Math.max(...usable);
  const span = Math.max(high - low, Math.abs(high) * 0.12, 0.5);
  return [zeroFloor ? Math.max(0, low - span * 0.5) : low - span * 0.5, high + span * 0.5];
}

const SEASON_COLOURS = [C.blue, C.cyan] as const;
const COMPARISON_KPI_UNITS: Record<string, string> = {
  time_loss_incidence: "/1,000 h",
  mean_severity: "days",
  injury_burden: "days/1,000 h",
  time_loss_injuries: "injuries",
};
const COMPARISON_KPI_LABELS: Record<string, string> = {
  time_loss_incidence: "Injury Incidence",
  mean_severity: "Mean Severity",
  injury_burden: "Injury Burden",
  time_loss_injuries: "Injuries",
};

function ComparisonKpiCards({ comparison }: { comparison: SeasonComparisonVisuals }) {
  return <View style={[styles.metricGrid, { marginTop: -1 }]}>{comparison.kpis.map((metric) => {
    const improvement = metric.outcome_improvement_percent;
    const state = improvement === null ? "Not comparable" : improvement > 0 ? "Decreased" : improvement < 0 ? "Increased" : "No change";
    const stateColour = improvement === null || improvement === 0 ? C.muted : improvement > 0 ? C.green : C.red;
    const digits = metric.key === "time_loss_injuries" || metric.key === "injury_burden" ? 0 : 1;
    return <View key={metric.key} style={[styles.metricCell, { width: "25%" }]}>
      <View style={[styles.metricCard, { minHeight: 100, padding: 8 }]}>
        <Text style={styles.metricLabel}>{COMPARISON_KPI_LABELS[metric.key] ?? metric.label}</Text>
        <Text style={{ color: stateColour, fontFamily: "Helvetica-Bold", fontSize: 15, marginTop: 6 }}>{improvement === null ? "N/A" : `${fmt(Math.abs(improvement), "", 1)}%`}</Text>
        <Text style={{ color: stateColour, fontFamily: "Helvetica-Bold", fontSize: 6.5, marginTop: 1 }}>{state}</Text>
        <View style={{ flexDirection: "row", borderTopWidth: 1, borderTopColor: C.rule, marginTop: 7, paddingTop: 6 }}>
          {([metric.previous, metric.current] as const).map((season, seasonIndex) => <View key={seasonIndex} style={{ width: "50%", paddingRight: seasonIndex === 0 ? 3 : 0, paddingLeft: seasonIndex === 1 ? 4 : 0, borderLeftWidth: seasonIndex === 1 ? 1 : 0, borderLeftColor: C.rule }}>
            <View style={{ flexDirection: "row", alignItems: "center" }}><View style={[styles.legendDot, { width: 5, height: 5, borderRadius: 2.5, marginRight: 3, backgroundColor: SEASON_COLOURS[seasonIndex] }]} /><Text style={{ color: C.muted, fontFamily: "Helvetica-Bold", fontSize: 5.8 }}>{seasonIndex === 0 ? comparison.previous_season : comparison.current_season}</Text></View>
            <Text style={{ color: C.ink, fontFamily: "Helvetica-Bold", fontSize: 8, marginTop: 3 }}>{fmt(season.value, "", digits)}</Text>
            <Text style={{ color: C.muted, fontSize: 5.5, marginTop: 1 }}>{COMPARISON_KPI_UNITS[metric.key] ?? season.unit}</Text>
          </View>)}
        </View>
      </View>
    </View>;
  })}</View>;
}

function SeasonImpactChart({ comparison, setting = "all", chartHeight = 190 }: { comparison: SeasonComparisonVisuals; setting?: "all" | "match" | "training"; chartHeight?: number }) {
  const impact = comparison.impact.find((row) => row.setting === setting);
  if (!impact) return <Text style={styles.panelNote}>No approved injury-impact values are available for this setting.</Text>;
  const points = [
    { season: comparison.previous_season, value: impact.previous, colour: SEASON_COLOURS[0] },
    { season: comparison.current_season, value: impact.current, colour: SEASON_COLOURS[1] },
  ];
  const w = 517, h = chartHeight, left = 56, right = 20, top = 22, bottom = 42;
  const plotW = w - left - right, plotH = h - top - bottom;
  const [xLow, xHigh] = comparisonDomain(points.map((point) => point.value.time_loss_incidence_per_1000h), true);
  const [yLow, yHigh] = comparisonDomain(points.map((point) => point.value.mean_severity_days), true);
  const x = (value: number) => left + (value - xLow) / (xHigh - xLow) * plotW;
  const y = (value: number) => top + plotH - (value - yLow) / (yHigh - yLow) * plotH;
  const maxBurden = Math.max(0, ...points.map((point) => point.value.burden_per_1000h ?? 0));
  const radius = (value: number | null) => finiteNumber(value) && maxBurden > 0 ? 9 + Math.sqrt(Math.max(value, 0) / maxBurden) * 14 : 9;
  const plotted = points.map((point) => ({
    ...point,
    x: finiteNumber(point.value.time_loss_incidence_per_1000h) ? x(point.value.time_loss_incidence_per_1000h) : null,
    y: finiteNumber(point.value.mean_severity_days) ? y(point.value.mean_severity_days) : null,
    r: radius(point.value.burden_per_1000h),
  }));
  const first = plotted[0], second = plotted[1];
  const connects = first.x !== null && first.y !== null && second.x !== null && second.y !== null;
  const angle = connects ? Math.atan2((second.y ?? 0) - (first.y ?? 0), (second.x ?? 0) - (first.x ?? 0)) : 0;
  const arrowX = (second.x ?? 0) - Math.cos(angle) * second.r;
  const arrowY = (second.y ?? 0) - Math.sin(angle) * second.r;
  const arrow = connects
    ? `M ${arrowX} ${arrowY} L ${arrowX - Math.cos(angle - 0.55) * 7} ${arrowY - Math.sin(angle - 0.55) * 7} L ${arrowX - Math.cos(angle + 0.55) * 7} ${arrowY - Math.sin(angle + 0.55) * 7} Z`
    : "";
  return <View>
    <Svg viewBox={`0 0 ${w} ${h}`} style={{ height: h }}>
      <Rect x={left} y={top} width={plotW} height={plotH} fill={C.white} stroke={C.line} strokeWidth={0.8} />
      {[0, 0.25, 0.5, 0.75, 1].map((ratio) => {
        const xPosition = left + ratio * plotW, yPosition = top + plotH - ratio * plotH;
        return <G key={ratio}>
          <Line x1={xPosition} x2={xPosition} y1={top} y2={top + plotH} stroke={C.rule} strokeWidth={0.7} />
          <Line x1={left} x2={left + plotW} y1={yPosition} y2={yPosition} stroke={C.rule} strokeWidth={0.7} />
          <SvgText x={xPosition} y={top + plotH + 12} textAnchor="middle" fontSize={6.2} fill={C.muted}>{tickText(xLow + ratio * (xHigh - xLow))}</SvgText>
          <SvgText x={left - 5} y={yPosition + 2.2} textAnchor="end" fontSize={6.2} fill={C.muted}>{tickText(yLow + ratio * (yHigh - yLow))}</SvgText>
        </G>;
      })}
      {connects && <Line x1={first.x ?? 0} y1={first.y ?? 0} x2={arrowX} y2={arrowY} stroke={C.amber} strokeWidth={1.6} strokeDasharray="5 4" />}
      {connects && <Path d={arrow} fill={C.amber} />}
      {plotted.map((point, index) => point.x !== null && point.y !== null ? <G key={point.season}>
        <Circle cx={point.x} cy={point.y} r={point.r} fill={point.colour} opacity={0.72} stroke={point.colour} strokeWidth={1.5} />
        <SvgText x={point.x} y={index === 0 ? point.y - point.r - 6 : point.y + point.r + 10} textAnchor="middle" fontSize={7} fontWeight="bold" fill={point.colour}>{point.season}</SvgText>
      </G> : null)}
      <SvgText x={left + plotW / 2} y={h - 4} textAnchor="middle" fontSize={6.7} fontWeight="bold" fill={C.ink}>Incidence per 1,000 player-hours</SvgText>
      <SvgText x={12} y={top + plotH / 2} textAnchor="middle" transform={`rotate(-90 12 ${top + plotH / 2})`} fontSize={6.7} fontWeight="bold" fill={C.ink}>Mean Severity in days</SvgText>
    </Svg>
    <Legend items={[
      { label: comparison.previous_season, colour: SEASON_COLOURS[0] },
      { label: comparison.current_season, colour: SEASON_COLOURS[1] },
      { label: "Circle area represents burden", colour: C.grey },
    ]} />
    <Caption>Incidence is on the horizontal axis and mean severity is on the vertical axis. The dashed arrow shows the sequence between approved releases, not causality.</Caption>
  </View>;
}

function SeasonMonthlyBars({ comparison, chartHeight = 205 }: { comparison: SeasonComparisonVisuals; chartHeight?: number }) {
  const rows = comparison.monthly, w = 517, h = chartHeight, left = 38, right = 12, top = 18, bottom = 35;
  const plotW = w - left - right, plotH = h - top - bottom;
  const scale = niceScale(Math.max(1, ...rows.flatMap((row) => [row.previous_time_loss_injuries, row.current_time_loss_injuries])));
  const y = (value: number) => top + plotH - value / scale.top * plotH;
  const slot = plotW / Math.max(rows.length, 1), barWidth = Math.min(15, slot * 0.3);
  return <View>
    <Svg viewBox={`0 0 ${w} ${h}`} style={{ height: h }}>
      <Rect x={left} y={top} width={plotW} height={plotH} fill={C.white} stroke={C.line} strokeWidth={0.8} />
      {scale.ticks.map((tick) => <G key={tick}>
        <Line x1={left} x2={left + plotW} y1={y(tick)} y2={y(tick)} stroke={C.rule} strokeWidth={0.7} />
        <SvgText x={left - 5} y={y(tick) + 2.2} textAnchor="end" fontSize={6.2} fill={C.muted}>{tickText(tick)}</SvgText>
      </G>)}
      {rows.map((row, index) => {
        const centre = left + slot * index + slot / 2;
        return <G key={row.month_key}>
          <Rect x={centre - barWidth - 1} y={y(row.previous_time_loss_injuries)} width={barWidth} height={top + plotH - y(row.previous_time_loss_injuries)} fill={SEASON_COLOURS[0]} />
          <Rect x={centre + 1} y={y(row.current_time_loss_injuries)} width={barWidth} height={top + plotH - y(row.current_time_loss_injuries)} fill={SEASON_COLOURS[1]} />
          <SvgText x={centre} y={top + plotH + 12} textAnchor="middle" fontSize={6.2} fill={C.muted}>{row.label.toUpperCase()}</SvgText>
        </G>;
      })}
      <SvgText x={left + plotW / 2} y={h - 3} textAnchor="middle" fontSize={6.7} fontWeight="bold" fill={C.ink}>Month</SvgText>
      <SvgText x={8} y={top + plotH / 2} textAnchor="middle" transform={`rotate(-90 8 ${top + plotH / 2})`} fontSize={6.7} fontWeight="bold" fill={C.ink}>Injury Count</SvgText>
    </Svg>
    <Legend items={[
      { label: comparison.previous_season, colour: SEASON_COLOURS[0], shape: "bar" },
      { label: comparison.current_season, colour: SEASON_COLOURS[1], shape: "bar" },
    ]} />
    <Caption>Paired bars compare monthly injury counts for the two approved releases.</Caption>
  </View>;
}

function DiagnosisDriversPdf({ comparison }: { comparison: SeasonComparisonVisuals }) {
  const entries = comparison.diagnoses.flatMap((row) => [...row.previous, ...row.current]);
  const max = Math.max(1, ...entries.map((item) => item.time_loss_injuries));
  // One colour per diagnosis, so the same condition reads the same in every
  // setting and both seasons. The season colours stay on the column headings.
  const colours = diagnosisColourMap(entries.map((item) => item.diagnosis));
  const bar = (value: number) => `${value / max * 100}%`;
  const fillFor = (diagnosis?: string | null) => (diagnosis && colours.get(diagnosis)) || C.track;
  return <View>
    <View style={[styles.headRow, { marginBottom: 4, flexShrink: 0 }]}>
      <Text style={[styles.columnHead, { width: 48 }]}>Setting</Text>
      <Text style={[styles.columnHead, { flex: 1, textAlign: "right", color: SEASON_COLOURS[0] }]}>{comparison.previous_season}</Text>
      <Text style={[styles.columnHead, { width: 42, textAlign: "center" }]}>Injuries</Text>
      <Text style={[styles.columnHead, { flex: 1, color: SEASON_COLOURS[1] }]}>{comparison.current_season}</Text>
    </View>
    {comparison.diagnoses.map((row) => <View key={row.setting} style={{ borderWidth: 1, borderColor: C.rule, borderRadius: 4, padding: 4, marginBottom: 4, flexShrink: 0 }}>
      <Text style={{ color: C.navy, fontFamily: "Helvetica-Bold", fontSize: 7.5, textAlign: "center", marginBottom: 2 }}>{row.label}</Text>
      {[0, 1, 2].map((rank) => {
        const previous = row.previous[rank], current = row.current[rank];
        return <View key={rank} style={{ flexDirection: "row", alignItems: "center", flexShrink: 0, borderTopWidth: rank > 0 ? 1 : 0, borderTopColor: C.rule, paddingTop: rank > 0 ? 3 : 0, marginTop: rank > 0 ? 3 : 0 }}>
          <Text style={{ width: 48, color: C.muted, fontFamily: "Helvetica-Bold", fontSize: 6 }}>RANK {rank + 1}</Text>
          <View style={{ flex: 1, alignItems: "flex-end", paddingRight: 4 }}>
            <Text style={{ color: C.ink, fontSize: 6.2, lineHeight: 1.15, textAlign: "right" }}>{previous?.diagnosis ?? "Not available"}</Text>
            <View style={{ height: 6, width: "100%", backgroundColor: C.track, marginTop: 2, alignItems: "flex-end" }}><View style={{ height: 6, width: bar(previous?.time_loss_injuries ?? 0), backgroundColor: fillFor(previous?.diagnosis) }} /></View>
          </View>
          <Text style={{ width: 42, textAlign: "center", fontFamily: "Helvetica-Bold", fontSize: 7 }}>{previous?.time_loss_injuries ?? 0} | {current?.time_loss_injuries ?? 0}</Text>
          <View style={{ flex: 1, paddingLeft: 4 }}>
            <Text style={{ color: C.ink, fontSize: 6.2, lineHeight: 1.15 }}>{current?.diagnosis ?? "Not available"}</Text>
            <View style={{ height: 6, width: "100%", backgroundColor: C.track, marginTop: 2 }}><View style={{ height: 6, width: bar(current?.time_loss_injuries ?? 0), backgroundColor: fillFor(current?.diagnosis) }} /></View>
          </View>
        </View>;
      })}
    </View>)}
    <Caption>Bars share one scale of 0 to {max} injuries, and each diagnosis keeps one colour across both seasons and all three settings.</Caption>
  </View>;
}

function CoverPage({ model, meta }: { model: ReportModel; meta: ReportMetadata }) {
  return <Page size="A4" style={styles.cover}>
    {/* The image is already dark on the left, keeping the text legible without obscuring the player. */}
    {model.brand.heroDataUri && <Image fixed src={model.brand.heroDataUri} style={{ position: "absolute", left: 0, top: 0, width: "100%", height: "100%", objectFit: "cover" }} />}
    <View style={{ position: "absolute", left: 0, top: 0, width: 6, height: "100%", backgroundColor: model.brand.accentColour }} />
    <View style={{ height: 48, flexDirection: "row", alignItems: "center", marginHorizontal: 30, marginTop: 30 }}>
      {model.brand.urcLogoDataUri && <Image src={model.brand.urcLogoDataUri} style={{ width: 31, height: 32, objectFit: "contain", marginRight: 10 }} />}
      {/* The old lockup repeated the cover title. It is the league wordmark now;
          the title block carries the subject, season and SCRIIPT. */}
      <Text style={{ color: C.white, fontFamily: "Helvetica-Bold", fontSize: 9, letterSpacing: 1.3 }}>UNITED RUGBY CHAMPIONSHIP</Text>
      <View style={{ flex: 1 }} />
      <Text style={{ color: "#AFC1D4", fontSize: 5.8, letterSpacing: .7, marginRight: 8 }}>IN PARTNERSHIP WITH</Text>
      {model.brand.partnerLogoDataUri && <Image src={model.brand.partnerLogoDataUri} style={{ width: 23, height: 32, objectFit: "contain" }} />}
    </View>
    {model.scope === "team" && model.brand.crestDataUri && <View style={{ position: "absolute", right: 31, top: 82, width: 84, height: 84, borderRadius: 8, backgroundColor: C.white, padding: 11, alignItems: "center", justifyContent: "center" }}><Image src={model.brand.crestDataUri} style={{ width: 62, height: 62, objectFit: "contain" }} /></View>}
    <View style={{ flex: 1, width: "61%", justifyContent: "center", paddingRight: 18, marginLeft: 30 }}>
      <Text style={{ color: C.cyan, fontFamily: "Helvetica-Bold", fontSize: 8, letterSpacing: 1.5 }}>{model.scope === "league" ? "LEAGUE REPORT" : "TEAM PERFORMANCE REPORT"}</Text>
      <Text style={{ color: C.white, fontFamily: "Helvetica-Bold", fontSize: 36, lineHeight: 1.02, marginTop: 14 }}>{model.subjectName}</Text>
      <Text style={{ color: C.white, fontFamily: "Helvetica-Bold", fontSize: 25, lineHeight: 1.04, marginTop: 3 }}>SCRIIPT</Text>
      <Text style={{ color: "#C6D6E7", fontSize: 8, lineHeight: 1.35, marginTop: 5 }}>Surveillance of Continental Rugby Injury/Illness and Performance Tracking</Text>
      <View style={{ width: 54, height: 3, backgroundColor: model.brand.accentColour, marginTop: 18 }} />
      <Text style={{ color: C.blue, fontFamily: "Helvetica-Bold", fontSize: 16, marginTop: 13 }}>{model.season} season</Text>
    </View>
    <View style={{ width: "61%", borderTopWidth: 1, borderTopColor: "#36516E", paddingTop: 13, marginLeft: 30, marginBottom: 34, flexDirection: "row" }}>
      <View style={{ width: "52%" }}><Text style={{ color: "#93A9C1", fontSize: 6.2, letterSpacing: .9 }}>ANALYSIS WINDOW</Text><Text style={{ color: C.white, fontSize: 8.5, marginTop: 4 }}>{formatDate(model.analysisWindow.start)} to {formatDate(model.analysisWindow.end)}</Text></View>
      <View style={{ width: "21%" }}><Text style={{ color: "#93A9C1", fontSize: 6.2, letterSpacing: .9 }}>VERSION</Text><Text style={{ color: C.white, fontSize: 8.5, marginTop: 4 }}>v{meta.version}</Text></View>
      <View style={{ width: "27%" }}><Text style={{ color: "#93A9C1", fontSize: 6.2, letterSpacing: .9 }}>EXPORTED</Text><Text style={{ color: C.white, fontSize: 8.5, marginTop: 4 }}>{formatDate(meta.exportedAt)}</Text></View>
    </View>
  </Page>;
}

function SeasonPattern({ model, meta }: { model: ReportModel; meta: ReportMetadata }) {
  const comparison = model.seasonComparisonVisuals;
  return <PageShell model={model} meta={meta} section="season-pattern">
    <PageTitle title="Season Overview" note="Headline measures, the setting split and the approved season comparison are brought together on the first analytical page." />
    <OverviewCards model={model} />
    <View style={{ marginTop: 8 }}><Panel title="Match Vs Training" note="Released setting measures shown side by side."><SettingBench rows={model.matchTraining} /></Panel></View>
    <View style={{ marginTop: 8, height: 377 }}><Panel fill title="Injury Impact By Season" note="Overall incidence, mean severity and burden for the two approved releases.">{comparison ? <SeasonImpactChart comparison={comparison} chartHeight={295} /> : <Text style={styles.panelNote}>No approved season comparison is available for this report.</Text>}</Panel></View>
  </PageShell>;
}
function SeverityContact({ model, meta }: { model: ReportModel; meta: ReportMetadata }) {
  return <PageShell model={model} meta={meta} section="severity-contact">
    <PageTitle title="Monthly Pattern, Severity And Mechanism" note="The monthly injury series leads into the released severity and contact profiles." />
    <View style={{ height: 344 }}><Panel fill title="Season Timeline" note="Case counts, and incidence where the release carries monthly rates, for each month of the analysis window."><TimelineChart rows={model.monthlyInjuryPattern} preliminary={model.preliminaryMonthlyRates} chartHeight={244} /></Panel></View>
    <View style={[styles.split, { marginTop: 8, height: 318 }]}>
      <View style={styles.third}><Panel fill title="Severity" note="Injuries by released duration band."><HalfRing rows={model.severityDistribution} colours={SEVERITY_COLOURS} value="timeLoss" unitHead="Cases (share)" /></Panel></View>
      <View style={styles.third}><Panel fill title="Contact Mechanism" note="Injuries by released mechanism."><HalfRing rows={model.contactDistribution} colours={CONTACT_COLOURS} value="timeLoss" unitHead="Cases (share)" /></Panel></View>
      <View style={styles.third}><Panel fill title="Match Vs Training" note="Match and training measures for the same window."><CompactSettingBench rows={model.matchTraining} /></Panel></View>
    </View>
  </PageShell>;
}
function InjuryLocation({ model, meta }: { model: ReportModel; meta: ReportMetadata }) {
  const rows = overall(model.injuryProfile.bodyLocations);
  return <PageShell model={model} meta={meta} section="injury-location">
    <PageTitle title="Injury Location" note="The body map, ranked locations and match-training split use the released body-location rows." />
    <View style={[styles.split, { height: 352 }]}>
      <View style={{ width: "38%", paddingHorizontal: 4 }}><Panel fill title="Body Heat Map" note="Front and back views of the released body-location rows."><BodyMapPdf rows={rows} chartHeight={248} /></Panel></View>
      <View style={{ width: "62%", paddingHorizontal: 4 }}>
        <Panel fill title="Top Locations" note="Injury counts, then the matching rate measures for the leading regions.">
          <RankedBars rows={rows} limit={8} heat heading="Body region" unit="Cases" rowGap={5} />
          <View style={[styles.headRow, { marginTop: 8, alignItems: "flex-end" }]}>
            <Text style={[styles.columnHead, { flex: 1 }]}>Body region</Text>
            <View style={{ width: 174 }}>
              <Text style={[styles.columnHead, { textAlign: "right", marginBottom: 3 }]}>Rate Measures</Text>
              <View style={{ flexDirection: "row" }}>
                <Text style={[styles.columnHead, { width: 58, textAlign: "right", paddingLeft: 3 }]}>Incidence{"\n"}/1,000 h</Text>
                <Text style={[styles.columnHead, { width: 58, textAlign: "right", paddingLeft: 4, borderLeftWidth: 1, borderLeftColor: C.rule }]}>Burden{"\n"}days/1,000 h</Text>
                <Text style={[styles.columnHead, { width: 58, textAlign: "right", paddingLeft: 4, borderLeftWidth: 1, borderLeftColor: C.rule }]}>Mean Severity{"\n"}days</Text>
              </View>
            </View>
          </View>
          {[...rows].sort((a, b) => b.timeLossInjuries - a.timeLossInjuries).slice(0, 8).map((r) => <View key={r.code} style={styles.compactTableRow}>
            <Text style={styles.compactLabel}>{r.label}</Text>
            <Text style={styles.compactNumber}>{fmt(r.incidencePer1000h)}</Text>
            <Text style={styles.compactNumber}>{fmt(r.burdenPer1000h)}</Text>
            <Text style={styles.compactNumber}>{fmt(r.meanSeverityDays)}</Text>
          </View>)}
        </Panel>
      </View>
    </View>
    <View style={{ marginTop: 8, height: 348 }}><Panel fill title="Match Vs Training By Region" note="Injury counts for every region with a released match or training case."><MirroredBars rows={model.injuryProfile.bodyLocations} rowGap={1.5} heading="Body region" /></Panel></View>
  </PageShell>;
}
function CommonInjuries({ model, meta }: { model: ReportModel; meta: ReportMetadata }) {
  return <PageShell model={model} meta={meta} section="common-injuries">
    <PageTitle title="Most Common Injuries" note="Each diagnosis keeps one colour across count, incidence, burden and severity." />
    <Panel note="The top five released diagnoses for each measure. Each diagnosis keeps one colour across the four columns."><CommonLanes rows={model.injuryProfile.diagnoses} /></Panel>
  </PageShell>;
}
const ILLNESS_LANES = [
  { metric: "recorded_illnesses", label: "Count", unit: "illnesses", colour: C.cyan, digits: 0 },
  { metric: "incidence_per_1000h", label: "Incidence", unit: "illnesses per 1,000 player-h", colour: C.amber, digits: 1 },
  { metric: "burden_per_1000h", label: "Burden", unit: "days per 1,000 player-h", colour: C.coral, digits: 1 },
  { metric: "mean_severity_days", label: "Severity", unit: "mean days lost", colour: C.mint, digits: 1 },
] as const;

function Illnesses({ model, meta }: { model: ReportModel; meta: ReportMetadata }) {
  const { summary, profiles } = model.illness;
  const colours = illnessColorMap(profiles);
  const totalIllnesses = summary?.recorded_illnesses ?? profiles.reduce((total, row) => total + row.recorded_illnesses, 0);
  const cards: StatCard[] = ILLNESS_LANES.map((lane) => ({
    key: lane.metric,
    label: lane.metric === "recorded_illnesses" ? "Illnesses" : lane.label,
    value: fmt(summary?.[lane.metric] ?? null, "", lane.digits),
    unit: lane.unit,
    colour: lane.colour,
    series: rankedIllnesses(profiles, lane.metric).map((row) => row[lane.metric]),
  }));
  return <PageShell model={model} meta={meta} section="illnesses">
    <PageTitle title="Most Common Illnesses" note="Overall illness reporting only. Illnesses are not attributed to Match or Training." />
    <StatCards cards={cards} />
    {summary?.qualification && <View style={[styles.note, { marginTop: 7 }]}><Text>{summary.qualification}</Text></View>}
    <View style={{ marginTop: 8, height: 470 }}>
      <Panel fill note="The top five released illnesses for each measure. Each illness keeps one colour across the four columns.">
        {profiles.length ? <View style={{ flexDirection: "row", marginHorizontal: -3 }}>
          {ILLNESS_LANES.map((lane) => <View key={lane.metric} style={{ width: "25%", paddingHorizontal: 3 }}>
            <View style={[styles.headRow, { flexDirection: "column", alignItems: "flex-start" }]}>
              <Text style={styles.panelTitle}>{lane.label}</Text>
              <Text style={styles.columnHead}>{lane.unit}</Text>
            </View>
            {rankedIllnesses(profiles, lane.metric).map((row, index) => {
              const fill = cardFill(colours.get(row.code)?.background ?? C.navy);
              const text = readableOn(fill);
              return <View key={row.code} style={{ backgroundColor: fill, borderRadius: 3, padding: 5, minHeight: 62, marginBottom: 4 }}>
                <Text style={{ color: text, fontFamily: "Helvetica-Bold", fontSize: 6.8, lineHeight: 1.2 }}>{index + 1}. {row.label}</Text>
                {lane.metric === "recorded_illnesses" && <Text style={{ color: text, fontSize: 6, marginTop: 2 }}>{totalIllnesses > 0 ? Math.round(row.recorded_illnesses / totalIllnesses * 100) : 0}% of illnesses</Text>}
                <Text style={{ color: text, fontFamily: "Helvetica-Bold", fontSize: 12.5, marginTop: 4 }}>{fmt(row[lane.metric], "", lane.digits)}</Text>
              </View>;
            })}
          </View>)}
        </View> : <Text style={styles.panelNote}>No released illness profiles are available.</Text>}
      </Panel>
    </View>
  </PageShell>;
}

function DiagnosisMatrix({ model, meta }: { model: ReportModel; meta: ReportMetadata }) {
  const rowCount = model.injuryImpact.diagnoses.length;
  // The key wraps into four columns beneath the plot, so the plot gives back
  // whatever those rows need and never shrinks past a readable chart.
  const chartHeight = Math.max(360, 590 - Math.ceil(rowCount / 4) * 19);
  return <PageShell model={model} meta={meta} section="diagnosis-matrix">
    <PageTitle title="Risk Matrix" note="Grouped By Diagnosis. Horizontal position is incidence and vertical position is mean severity." />
    <View style={{ height: 684 }}>
      <Panel fill><ImpactMatrix rows={model.injuryImpact.diagnoses} chartHeight={chartHeight} gradientId="risk-diagnosis" /></Panel>
    </View>
  </PageShell>;
}

function ImpactMatrices({ model, meta }: { model: ReportModel; meta: ReportMetadata }) {
  return <PageShell model={model} meta={meta} section="impact-matrices">
    <PageTitle title="Injury Impact Matrix" note="The Location and Type groupings of the Risk Matrix, on the same axes as the Diagnosis grouping." />
    <View style={{ height: 336 }}><Panel fill title="Risk Matrix" note="Grouped by Location. Incidence against mean severity."><ImpactMatrix rows={model.injuryImpact.bodyLocations} chartHeight={214} gradientId="risk-location" /></Panel></View>
    <View style={{ marginTop: 8, height: 336 }}><Panel fill title="Risk Matrix" note="Grouped by Type. Incidence against mean severity."><ImpactMatrix rows={model.injuryImpact.injuryTypes} chartHeight={214} gradientId="risk-injury-type" /></Panel></View>
  </PageShell>;
}
function InjuryTypes({ model, meta }: { model: ReportModel; meta: ReportMetadata }) {
  return <PageShell model={model} meta={meta} section="injury-types">
    <PageTitle title="Injury Types" note="Injury families, subtype detail and the match against training split share one analytical page." />
    <View style={[styles.split, { height: 300 }]}>
      <View style={styles.half}><Panel fill title="Injury-Family Ranking" note="Overall injuries and incidence."><FamilyRanking rows={model.injuryProfile.injuryTypeFamilies} rowGap={6} /></Panel></View>
      <View style={styles.half}><Panel fill title="Leading-Family Dossier" note="Released family and subtype measures."><FamilyDossier rows={model.injuryProfile.injuryTypeFamilies} /></Panel></View>
    </View>
    <View style={{ marginTop: 8, height: 350 }}><Panel fill title="Match Vs Training By Injury Type" note="Injury counts for every family with a released match or training case."><MirroredBars rows={model.injuryProfile.injuryTypeFamilies} rowGap={8} heading="Injury family" /></Panel></View>
  </PageShell>;
}
function Exposure({ model, meta }: { model: ReportModel; meta: ReportMetadata }) {
  const exposure = model.exposure;
  const hsrStatus = exposure.hsrIsImputed
    ? "League-mean placeholder"
    : exposure.totalHsrDistanceKm === null ? "HSR not available" : "Actual source data";
  const cards: StatCard[] = [
    { key: "hours", label: exposure.totalHoursLabel, value: fmt(exposure.totalHours, "", 0), unit: "player-hours", colour: C.mint },
    { key: "distance", label: exposure.totalDistanceLabel, value: fmt(exposure.totalDistanceKm, "", 0), unit: "km", colour: C.cyan },
    { key: "hsr", label: "HSR Distance", value: fmt(exposure.totalHsrDistanceKm, "", 0), unit: "km", colour: C.hsr },
  ];
  const hsrNote = [`HSR Status: ${hsrStatus}.`, exposure.totalHsrPercentage === null ? "" : `HSR is ${fmt(exposure.totalHsrPercentage, "%")} of total distance.`, exposure.hsrDisplayNote ?? ""].filter(Boolean).join(" ");
  return <PageShell model={model} meta={meta} section="exposure">
    <PageTitle title="Exposure" note="The released denominator is shown over time and against the league cohort." />
    <StatCards cards={cards} />
    {currentExposureWarnings(exposure.dataQualityWarnings).map((warning) => <View key={warning} style={[styles.note, { marginTop: 7 }]}>
      <Text><Text style={{ fontFamily: "Helvetica-Bold" }}>Data Quality Warning. </Text>{warning}</Text>
    </View>)}
    <Text style={[styles.panelNote, { marginTop: 6, marginBottom: 0 }]}>{hsrNote}</Text>
    <View style={{ marginTop: 8, height: 272 }}><Panel fill title="Monthly Exposure" note="Player-hours use the left axis. Total distance uses the right axis, with HSR drawn as an inset inside it."><ExposureTrend model={model} chartHeight={205} /></Panel></View>
    <View style={[styles.split, { marginTop: 8, height: 300 }]}>
      <View style={styles.half}><Panel fill title="Team Comparison" note="Hours. Released player-hours for every club in the cohort."><ExposureLadder model={model} keyName="exposureHours" label="Player-hours" unit="Hours" colour={C.mint} rowGap={8} /></Panel></View>
      <View style={styles.half}><Panel fill title="Team Comparison" note="Distance. Released distance for every club in the cohort."><ExposureLadder model={model} keyName="distanceKm" label="Kilometres" unit="km" colour={C.cyan} rowGap={8} /></Panel></View>
    </View>
  </PageShell>;
}
function TeamComparison({ model, meta }: { model: ReportModel; meta: ReportMetadata }) {
  return <PageShell model={model} meta={meta} section="team-comparison">
    <PageTitle title="Team Comparison" note={model.comparisonHeatmap.some((row) => row.isSubject)
      ? `Other clubs carry their approved dashboard alias. ${model.subjectName} is highlighted against released league benchmarks.`
      : "Every club carries its approved dashboard alias, compared against released league benchmarks."} />
    <View style={{ height: 322 }}>
      <Panel fill title="Match And Training Incidence" note="One bubble for each club in the released cohort. Dashed lines are the league means.">
        <ComparisonScatter model={model} chartHeight={238} />
      </Panel>
    </View>
    <View style={{ marginTop: 8, height: 350 }}>
      <Panel fill title="Match And Training Values Vs League Average" note="Each cell is compared with the released league mean for that metric."><Heatmap model={model} rowHeight={16} /></Panel>
    </View>
  </PageShell>;
}
function SeasonMethodology({ model, meta }: { model: ReportModel; meta: ReportMetadata }) {
  const comparison = model.seasonComparisonVisuals;
  return <PageShell model={model} meta={meta} section="season-methodology">
    <PageTitle title="Season Comparison" note={comparison ? `Approved ${comparison.previous_season} and ${comparison.current_season} values are shown using the same measures as the dashboard.` : "No approved season comparison is available for this report."} />
    {comparison ? <>
      <View style={{ height: 111 }}><ComparisonKpiCards comparison={comparison} /></View>
      <View style={{ marginTop: 8, height: 225 }}><Panel fill title="Injuries By Month" note="Paired monthly counts for the two approved releases."><SeasonMonthlyBars comparison={comparison} chartHeight={148} /></Panel></View>
      <View style={{ marginTop: 8 }}><Panel title="Diagnosis Drivers" note="The three leading diagnosis families by injury count for Overall, Match and Training settings. Bars share one scale across the three settings."><DiagnosisDriversPdf comparison={comparison} /></Panel></View>
    </> : <View style={[styles.panel, { height: 180, justifyContent: "center", alignItems: "center" }]}><Text style={styles.panelNote}>No approved season comparison is available.</Text></View>}
  </PageShell>;
}

function ClosingPage({ model }: { model: ReportModel }) {
  return <Page size="A4" style={styles.cover}>
    {model.brand.heroDataUri && <Image fixed src={model.brand.heroDataUri} style={{ position: "absolute", left: -28, top: -24, width: "112%", height: "112%", objectFit: "cover" }} />}
    {/* Centred type sits over the whole frame here, so this cover keeps a flat
        scrim; it is light enough to leave the athlete readable. */}
    <View style={{ position: "absolute", left: 0, right: 0, top: 0, bottom: 0, backgroundColor: C.navy, opacity: model.brand.heroDataUri ? .5 : 1 }} />
    <View style={{ position: "absolute", left: 0, bottom: 0, width: "100%", height: 7, backgroundColor: model.brand.accentColour }} />
    <View style={{ flex: 1, alignItems: "center", justifyContent: "center", paddingHorizontal: 72 }}>
      <View style={{ flexDirection: "row", alignItems: "center", marginBottom: 30 }}>
        {model.brand.urcLogoDataUri && <Image src={model.brand.urcLogoDataUri} style={{ width: 46, height: 47, objectFit: "contain" }} />}
        <View style={{ width: 1, height: 42, backgroundColor: "#49627C", marginHorizontal: 17 }} />
        <View style={{ alignItems: "center" }}><Text style={{ color: "#AFC1D4", fontSize: 5.8, letterSpacing: .8, marginBottom: 5 }}>IN PARTNERSHIP WITH</Text>{model.brand.partnerLogoDataUri && <Image src={model.brand.partnerLogoDataUri} style={{ width: 29, height: 42, objectFit: "contain" }} />}</View>
      </View>
      <Text style={{ color: C.cyan, fontFamily: "Helvetica-Bold", fontSize: 8, letterSpacing: 1.7 }}>END OF REPORT</Text>
      <Text style={{ color: C.white, fontFamily: "Helvetica-Bold", fontSize: 31, textAlign: "center", lineHeight: 1.03, marginTop: 14 }}>SCRIIPT</Text>
      <Text style={{ color: "#C6D6E7", fontSize: 8, textAlign: "center", lineHeight: 1.35, marginTop: 6 }}>Surveillance of Continental Rugby Injury/Illness and Performance Tracking</Text>
      <Text style={{ color: C.blue, fontFamily: "Helvetica-Bold", fontSize: 16, textAlign: "center", marginTop: 14 }}>{model.subjectName} · {model.season}</Text>
      <View style={{ width: 56, height: 3, backgroundColor: model.brand.accentColour, marginVertical: 23 }} />
      {model.scope === "team" && model.brand.crestDataUri && <View style={{ width: 78, height: 78, borderRadius: 8, backgroundColor: C.white, padding: 11, alignItems: "center", justifyContent: "center" }}><Image src={model.brand.crestDataUri} style={{ width: 56, height: 56, objectFit: "contain" }} /></View>}
    </View>
  </Page>;
}

const sectionPages: Record<ReportSectionId, (model: ReportModel, meta: ReportMetadata) => ReactElement> = {
  cover: (m, x) => <CoverPage model={m} meta={x} />, "season-pattern": (m, x) => <SeasonPattern model={m} meta={x} />,
  "severity-contact": (m, x) => <SeverityContact model={m} meta={x} />, "injury-location": (m, x) => <InjuryLocation model={m} meta={x} />,
  "common-injuries": (m, x) => <CommonInjuries model={m} meta={x} />,
  "diagnosis-matrix": (m, x) => <DiagnosisMatrix model={m} meta={x} />, illnesses: (m, x) => <Illnesses model={m} meta={x} />, "impact-matrices": (m, x) => <ImpactMatrices model={m} meta={x} />,
  "injury-types": (m, x) => <InjuryTypes model={m} meta={x} />, exposure: (m, x) => <Exposure model={m} meta={x} />,
  "team-comparison": (m, x) => <TeamComparison model={m} meta={x} />, "season-methodology": (m, x) => <SeasonMethodology model={m} meta={x} />,
  closing: (m) => <ClosingPage model={m} />,
};
export function enabledReportSections(sectionIds?: readonly ReportSectionId[]) { return orderedReportSectionIds(sectionIds); }
export function ReportDocument({ model, enabledSectionIds }: { model: ReportModel; enabledSectionIds?: readonly ReportSectionId[] }) { if (model.schemaVersion !== "urc-report-v1") throw new Error("Unsupported report model schema"); const meta = metadata(model); return <Document title={`${model.subjectName} injury surveillance report ${model.season}`} author="United Rugby Championship" subject={`Released aggregate injury surveillance metrics | ${meta.version}`} creator="URC injury surveillance" language="en-IE" creationDate={new Date(meta.exportedAt)}>{enabledReportSections(enabledSectionIds).map((section) => cloneElement(sectionPages[section](model, meta), { key: section }))}</Document>; }
