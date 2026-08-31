import {
  Circle, Document, Font, G, Image, Line, Page, Path, Rect, StyleSheet, Svg,
  Text, Text as PdfSvgText, View,
} from "@react-pdf/renderer";
import { cloneElement, type ComponentType, type ReactElement, type ReactNode } from "react";
import {
  DEFAULT_REPORT_SECTION_IDS,
  type ReportDistributionRow, type ReportInjuryTypeFamily, type ReportMetric,
  type ReportModel, type ReportPatternRow, type ReportProfileRow,
  type ReportSectionId, type ReportSettingMetric, type SeasonComparisonMetric,
} from "@/lib/report-model-types";

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
} as const;
const PALETTE = [C.cyan, C.mint, C.blue, C.amber, C.coral, C.purple, C.lime, C.orange];
const SEVERITY_COLOURS: Record<string, string> = {
  zero_days_medical_attention_only: C.grey, one_day: C.cyan, two_to_three_days: C.cyan,
  four_to_seven_days: C.mint, eight_to_twenty_eight_days: C.amber,
  greater_than_twenty_eight_days: C.coral, unknown_or_censored: C.purple,
};
const CONTACT_COLOURS: Record<string, string> = { contact: C.purple, non_contact: C.orange, unknown: C.grey };
const SECTION_HEADS: Record<ReportSectionId, string> = {
  cover: "Cover", "season-pattern": "Season overview", "severity-contact": "Severity and mechanism",
  "injury-location": "Injury location", "common-injuries": "Common injuries",
  "impact-matrices": "Injury impact matrices", "injury-types": "Injury type", exposure: "Exposure",
  "team-comparison": "Team comparison", "season-methodology": "Season comparison and method",
};
type ReportMetadata = { version: string; sourceGeneratedAt: string; exportedAt: string };

const styles = StyleSheet.create({
  page: { backgroundColor: C.paper, color: C.ink, fontFamily: "Helvetica", fontSize: 8, paddingHorizontal: 30, paddingBottom: 34 },
  cover: { backgroundColor: C.navy, color: C.white, fontFamily: "Helvetica", padding: 30 },
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
  coverFooter: { borderTopColor: "#294565", color: "#C6D6E7" },
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
function shortMonth(value: string): string { return value.trim().slice(0, 3).toUpperCase(); }
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
function logTicks(top: number): number[] { return [1, 2, 5, 10, 20, 50, 100, 200, 500, 1000].filter((tick) => tick <= top); }
/** Chooses ink or white body text so labels stay legible on a category colour. */
function readableOn(hex: string): string {
  const value = Number.parseInt(hex.slice(1), 16);
  const [r, g, b] = [(value >> 16) & 255, (value >> 8) & 255, value & 255].map((channel) => { const s = channel / 255; return s <= 0.03928 ? s / 12.92 : ((s + 0.055) / 1.055) ** 2.4; });
  return 0.2126 * r + 0.7152 * g + 0.0722 * b > 0.4 ? C.ink : C.white;
}

function Header({ model, section }: { model: ReportModel; section: ReportSectionId }) { return <View style={styles.header}><View style={styles.headerBrand}>{model.brand.crestDataUri && <Image src={model.brand.crestDataUri} style={styles.headerCrest} />}<Text style={styles.eyebrow}>URC injury surveillance</Text></View><Text style={styles.headerLabel}>{SECTION_HEADS[section]}</Text></View>; }
function Footer({ model, meta, cover = false }: { model: ReportModel; meta: ReportMetadata; cover?: boolean }) { return <View fixed style={[styles.footer, cover ? styles.coverFooter : {}]}><Text>{model.subjectName} | {model.season} | v{meta.version}</Text><Text>Source {formatDate(meta.sourceGeneratedAt)} | Exported {formatDate(meta.exportedAt)}</Text><Text render={({ pageNumber, totalPages }) => `${pageNumber} / ${totalPages}`} /></View>; }
function PageShell({ model, meta, section, children }: { model: ReportModel; meta: ReportMetadata; section: ReportSectionId; children: ReactNode }) { return <Page size="A4" style={styles.page}><Header model={model} section={section} />{children}<Footer model={model} meta={meta} /></Page>; }
function PageTitle({ title, note }: { title: string; note: string }) { return <View><Text style={styles.title}>{title}</Text><Text style={styles.standfirst}>{note}</Text></View>; }
function Panel({ title, note, children, fill = false }: { title: string; note?: string; children: ReactNode; fill?: boolean }) { return <View style={[styles.panel, fill ? { height: "100%" } : {}]}><Text style={styles.panelTitle}>{title}</Text>{note && <Text style={styles.panelNote}>{note}</Text>}{children}</View>; }

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

function metricColour(key: string, index: number): string { if (/burden/i.test(key)) return C.coral; if (/incidence/i.test(key)) return /overall/i.test(key) ? C.cyan : C.amber; if (/severity/i.test(key)) return C.purple; if (/exposure|hour/i.test(key)) return C.mint; if (/time.loss/i.test(key)) return C.amber; return PALETTE[index % PALETTE.length]; }
function metricSeries(metric: ReportMetric, rows: readonly ReportPatternRow[]): Array<number | null> { if (/overall.incidence/i.test(metric.key)) return rows.map((r) => r.overallIncidencePer1000h); if (/incidence/i.test(metric.key)) return rows.map((r) => r.incidencePer1000h); if (/burden/i.test(metric.key)) return rows.map((r) => r.burdenPer1000h); if (/time.loss/i.test(metric.key)) return rows.map((r) => r.timeLossInjuries); if (/recorded/i.test(metric.key)) return rows.map((r) => r.recordedInjuries); return rows.map(() => null); }
function Sparkline({ values, colour }: { values: Array<number | null>; colour: string }) {
  const data = values.map((value, index) => ({ value, index })).filter((p): p is { value: number; index: number } => typeof p.value === "number" && Number.isFinite(p.value));
  if (data.length < 2) return null;
  const min = Math.min(...data.map((p) => p.value)), max = Math.max(...data.map((p) => p.value)), span = max - min || 1;
  const y = (v: number) => 19 - ((v - min) / span) * 15, last = data[data.length - 1];
  const path = data.map((p, i) => `${i ? "L" : "M"} ${(p.index / Math.max(1, values.length - 1)) * 100} ${y(p.value)}`).join(" ");
  return <Svg viewBox="0 0 100 22" style={{ height: 14, marginTop: 3 }}>
    <Line x1={0} x2={100} y1={20.5} y2={20.5} stroke={C.rule} strokeWidth={0.8} />
    <Path d={path} stroke={colour} strokeWidth={2} fill="none" />
    <Circle cx={(last.index / Math.max(1, values.length - 1)) * 100} cy={y(last.value)} r={2.4} fill={colour} />
  </Svg>;
}
function MetricCards({ model, dark = false, limit = 7, trend = true }: { model: ReportModel; dark?: boolean; limit?: number; trend?: boolean }) {
  const metrics = model.snapshotMetrics.slice(0, limit), pattern = model.monthlyInjuryPattern, range = monthRange(pattern);
  return <View style={styles.metricGrid}>{metrics.map((metric, index) => {
    const colour = metricColour(metric.key, index), series = trend ? metricSeries(metric, pattern) : [];
    const plotted = series.filter((value) => typeof value === "number" && Number.isFinite(value)).length;
    return <View key={metric.key} style={[styles.metricCell, { width: metrics.length > 4 ? "25%" : `${100 / metrics.length}%` }, metrics.length === 7 && index === 4 ? { marginLeft: "12.5%" } : {}]}>
      <View style={[styles.metricCard, dark ? { backgroundColor: C.navy2, borderColor: "#294565" } : {}, trend ? { minHeight: 76 } : { minHeight: 52 }]}>
        <Text style={[styles.metricLabel, dark ? { color: C.white } : {}]}>{metric.label}</Text>
        <Text style={[styles.metricValue, dark ? { color: C.white } : {}]}>{fmt(metric.value)}</Text>
        <Text style={[styles.metricUnit, dark ? { color: "#AFC1D4" } : {}]}>{metric.unit}</Text>
        {trend && (plotted > 1
          ? <><Sparkline values={series} colour={colour} /><Text style={[styles.metricUnit, { marginTop: 2 }]}>Monthly trend, {range}</Text></>
          : <Text style={[styles.metricUnit, { marginTop: 10 }]}>Monthly trend not available</Text>)}
        {!trend && <Text style={[styles.metricUnit, { marginTop: 6 }]}>Released season total</Text>}
      </View>
    </View>;
  })}</View>;
}

function TimelineChart({ rows, chartHeight = 235 }: { rows: readonly ReportPatternRow[]; chartHeight?: number }) {
  const w = 517, h = chartHeight, left = 42, right = 56, top = 24, bottom = 36;
  const plotW = w - left - right, plotH = h - top - bottom;
  const cases = niceScale(Math.max(1, ...rows.flatMap((r) => [r.recordedInjuries ?? 0, r.timeLossInjuries])));
  const rate = niceScale(Math.max(1, ...rows.flatMap((r) => [r.overallIncidencePer1000h ?? 0, r.incidencePer1000h ?? 0])));
  const slot = plotW / Math.max(1, rows.length), x = (i: number) => left + slot * i + slot / 2;
  const caseY = (v: number) => top + plotH - (v / cases.top) * plotH, rateY = (v: number) => top + plotH - (v / rate.top) * plotH;
  const linePath = (pick: (r: ReportPatternRow) => number | null) => rows.map((r, i) => pick(r) === null ? "" : `${i ? "L" : "M"} ${x(i)} ${rateY(pick(r) ?? 0)}`).filter(Boolean).join(" ");
  const barWidth = Math.min(15, slot * 0.34);
  return <View>
    <Svg viewBox={`0 0 ${w} ${h}`} style={{ height: h }}>
      <Rect x={left} y={top} width={plotW} height={plotH} fill={C.white} stroke={C.line} strokeWidth={0.8} />
      {cases.ticks.map((tick) => <G key={`case-${tick}`}>
        <Line x1={left} x2={left + plotW} y1={caseY(tick)} y2={caseY(tick)} stroke={C.rule} strokeWidth={0.8} />
        <SvgText x={left - 5} y={caseY(tick) + 2.4} textAnchor="end" fontSize={6.5} fill={C.muted}>{tickText(tick)}</SvgText>
      </G>)}
      {rate.ticks.map((tick) => <G key={`rate-${tick}`}>
        <Line x1={left + plotW} x2={left + plotW + 3} y1={rateY(tick)} y2={rateY(tick)} stroke={C.line} strokeWidth={0.8} />
        <SvgText x={left + plotW + 6} y={rateY(tick) + 2.4} fontSize={6.5} fill={C.muted}>{tickText(tick)}</SvgText>
      </G>)}
      {rows.map((r, i) => { const centre = x(i); return <G key={r.month}>
        <Rect x={centre - barWidth - 1} y={caseY(r.recordedInjuries ?? 0)} width={barWidth} height={top + plotH - caseY(r.recordedInjuries ?? 0)} fill={C.cyan} opacity={0.72} />
        <Rect x={centre + 1} y={caseY(r.timeLossInjuries)} width={barWidth} height={top + plotH - caseY(r.timeLossInjuries)} fill={C.amber} />
        <SvgText x={centre} y={top + plotH + 12} textAnchor="middle" fontSize={6.5} fill={C.muted}>{shortMonth(r.month)}</SvgText>
      </G>; })}
      <Path d={linePath((r) => r.overallIncidencePer1000h)} fill="none" stroke={C.cyan} strokeWidth={2.2} />
      <Path d={linePath((r) => r.incidencePer1000h)} fill="none" stroke={C.amber} strokeWidth={2.2} />
      {rows.map((r, i) => <G key={`point-${r.month}`}>
        {r.overallIncidencePer1000h !== null && <Circle cx={x(i)} cy={rateY(r.overallIncidencePer1000h)} r={2.4} fill={C.cyan} stroke={C.white} strokeWidth={0.8} />}
        {r.incidencePer1000h !== null && <Circle cx={x(i)} cy={rateY(r.incidencePer1000h)} r={2.4} fill={C.amber} stroke={C.white} strokeWidth={0.8} />}
      </G>)}
      <SvgText x={2} y={top - 9} fontSize={6.8} fill={C.ink}>Injuries (cases)</SvgText>
      <SvgText x={w - 2} y={top - 9} textAnchor="end" fontSize={6.8} fill={C.ink}>Injuries per 1,000 player-hours</SvgText>
    </Svg>
    <Legend items={[
      { label: "Recorded injuries", colour: C.cyan, shape: "bar" },
      { label: "Time-loss injuries", colour: C.amber, shape: "bar" },
      { label: "Overall incidence", colour: C.cyan, shape: "line" },
      { label: "Time-loss incidence", colour: C.amber, shape: "line" },
    ]} />
    <Caption>Bars read against the left axis in cases. Lines read against the right axis in injuries per 1,000 player-hours.</Caption>
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
      <Text style={{ color: "#C0D0E0", fontSize: 6.8, marginTop: 1 }}>time-loss injuries</Text>
      {([["Recorded injuries", r.recordedInjuries, "cases"], ["Time-loss incidence", r.incidencePer1000h, "/1,000 h"], ["Burden", r.burdenPer1000h, "days/1,000 h"], ["Mean severity", r.meanSeverityDays, "days"], ["Exposure", r.exposureHours, "hours"]] as const).map(([label, amount, unit]) =>
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
      <Text style={{ color: colours[r.setting] ?? C.blue, fontFamily: "Helvetica-Bold", fontSize: 16 }}>{r.timeLossInjuries} TL</Text>
    </View>
    {([["Incidence", r.incidencePer1000h, "/1,000 h"], ["Burden", r.burdenPer1000h, "days/1,000 h"], ["Mean severity", r.meanSeverityDays, "days"]] as const).map(([label, value, unit]) =>
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

function RankedBars({ rows, metric = "timeLossInjuries", limit = 8, coloured = false, heading, unit, rowGap = 6 }: { rows: readonly ReportProfileRow[]; metric?: ProfileMetric; limit?: number; coloured?: boolean; heading: string; unit: string; rowGap?: number }) {
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
        <View style={{ height: 8, width: `${profileValue(r, metric) / max * 100}%`, backgroundColor: coloured ? profileColour(r.code) : C.cyan }} />
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
const NO_CASE_FILL = "#D7E2EA";
function bodyHeat(value: number, max: number) { if (value <= 0) return NO_CASE_FILL; const ratio = Math.min(1, value / Math.max(1, max)); return ratio > .72 ? "#D93F45" : ratio > .38 ? C.orange : C.amber; }
/** Turns the heat bands into explicit case ranges so the legend carries units. */
function bodyHeatLegend(max: number): LegendItem[] {
  const buckets = new Map<string, number[]>();
  for (let value = 1; value <= max; value += 1) { const colour = bodyHeat(value, max); buckets.set(colour, [...(buckets.get(colour) ?? []), value]); }
  const items: LegendItem[] = [{ label: "No time-loss cases", colour: NO_CASE_FILL, shape: "swatch" }];
  for (const [colour, values] of buckets) {
    const low = values[0], high = values[values.length - 1];
    items.push({ label: low === high ? `${low} case${low === 1 ? "" : "s"}` : `${low} to ${high} cases`, colour, shape: "swatch" });
  }
  return items;
}
function BodyMapPdf({ rows, chartHeight = 300 }: { rows: readonly ReportProfileRow[]; chartHeight?: number }) {
  const byCode = new Map(rows.map((r) => [r.code, r])), max = Math.max(1, ...rows.map((r) => r.timeLossInjuries));
  const figure = (shapes: typeof BODY_PATHS, offset: number, label: string) => <G transform={`translate(${offset} 14)`}>
    <SvgText x={60} y={-3} textAnchor="middle" fontSize={10} fill={C.ink}>{label}</SvgText>
    {shapes.map((shape) => {
      const props = { fill: bodyHeat(byCode.get(shape.code)?.timeLossInjuries ?? 0, max), stroke: C.white, strokeWidth: 1 };
      if (shape.circle) return <Circle key={`${label}-${shape.code}`} cx={shape.circle[0]} cy={shape.circle[1]} r={shape.circle[2]} {...props} />;
      if (shape.rect) return <Rect key={`${label}-${shape.code}`} x={shape.rect[0]} y={shape.rect[1]} width={shape.rect[2]} height={shape.rect[3]} rx={shape.rect[4]} {...props} />;
      return <Path key={`${label}-${shape.code}`} d={shape.d ?? ""} {...props} />;
    })}
  </G>;
  return <View>
    <Svg viewBox="0 0 270 422" style={{ height: chartHeight }}>{figure(BODY_PATHS, 5, "Front")}{figure(BACK_PATHS, 140, "Back")}</Svg>
    <Legend items={bodyHeatLegend(max)} />
    <Caption>Shading is the time-loss case count for each region, from 0 to {max} cases.</Caption>
  </View>;
}

function MirroredBars({ rows, limit = 9, rowGap = 6, heading }: { rows: readonly ReportProfileRow[]; limit?: number; rowGap?: number; heading: string }) {
  const allRows = overall(rows).sort((a, b) => b.timeLossInjuries - a.timeLossInjuries).slice(0, limit);
  const byKey = new Map(rows.map((r) => [`${r.setting}:${r.code}`, r]));
  const max = Math.max(1, ...allRows.flatMap((r) => [byKey.get(`match:${r.code}`)?.timeLossInjuries ?? 0, byKey.get(`training:${r.code}`)?.timeLossInjuries ?? 0]));
  return <View>
    <View style={styles.headRow}>
      <Text style={[styles.columnHead, { width: 34, textAlign: "right", paddingRight: 6, color: C.cyan }]}>Match</Text>
      <Text style={[styles.columnHead, { flex: 1, textAlign: "right", paddingRight: 6 }]}>{tickText(max)} to 0 cases</Text>
      <Text style={[styles.columnHead, { width: 125, textAlign: "center" }]}>{heading}</Text>
      <Text style={[styles.columnHead, { flex: 1, paddingLeft: 6 }]}>0 to {tickText(max)} cases</Text>
      <Text style={[styles.columnHead, { width: 34, paddingLeft: 6, color: C.mint }]}>Training</Text>
    </View>
    {allRows.map((r) => {
      const match = byKey.get(`match:${r.code}`)?.timeLossInjuries ?? 0, training = byKey.get(`training:${r.code}`)?.timeLossInjuries ?? 0;
      return <View key={r.code} style={{ flexDirection: "row", alignItems: "center", marginBottom: rowGap }}>
        <Text style={{ width: 34, textAlign: "right", paddingRight: 6, color: C.ink, fontSize: 6.8 }}>{match}</Text>
        <View style={{ flex: 1, height: 8, alignItems: "flex-end", backgroundColor: C.track, marginRight: 6 }}>
          <View style={{ width: `${match / max * 100}%`, height: 8, backgroundColor: C.cyan }} />
        </View>
        <Text style={{ width: 125, textAlign: "center", fontSize: 7 }}>{r.label}</Text>
        <View style={{ flex: 1, height: 8, backgroundColor: C.track, marginLeft: 6 }}>
          <View style={{ width: `${training / max * 100}%`, height: 8, backgroundColor: C.mint }} />
        </View>
        <Text style={{ width: 34, paddingLeft: 6, color: C.ink, fontSize: 6.8 }}>{training}</Text>
      </View>;
    })}
    <Legend items={[{ label: "Match time-loss injuries", colour: C.cyan, shape: "bar" }, { label: "Training time-loss injuries", colour: C.mint, shape: "bar" }]} />
    <Caption>Both sides use one shared scale of 0 to {tickText(max)} time-loss cases. Match reads right to left, training reads left to right.</Caption>
  </View>;
}

function CommonLanes({ rows, cardHeight = 49 }: { rows: readonly ReportProfileRow[]; cardHeight?: number }) {
  const defs: Array<{ metric: ProfileMetric; label: string; unit: string }> = [
    { metric: "timeLossInjuries", label: "Frequency", unit: "cases" },
    { metric: "incidencePer1000h", label: "Incidence", unit: "per 1,000 h" },
    { metric: "burdenPer1000h", label: "Burden", unit: "days per 1,000 h" },
    { metric: "meanSeverityDays", label: "Severity", unit: "mean days" },
  ];
  return <View style={{ flexDirection: "row", marginHorizontal: -3 }}>
    {defs.map((d) => {
      const ranked = [...rows].filter((r) => profileValue(r, d.metric) > 0).sort((a, b) => profileValue(b, d.metric) - profileValue(a, d.metric)).slice(0, 5);
      return <View key={d.metric} style={{ width: "25%", paddingHorizontal: 3 }}>
        <View style={[styles.headRow, { flexDirection: "column", alignItems: "flex-start" }]}>
          <Text style={styles.panelTitle}>{d.label}</Text>
          <Text style={styles.columnHead}>{d.unit}</Text>
        </View>
        {ranked.map((r, i) => { const fill = profileColour(r.code), text = readableOn(fill); return <View key={r.code} style={{ backgroundColor: fill, borderRadius: 3, padding: 5, minHeight: cardHeight, marginBottom: 4 }}>
          <Text style={{ color: text, fontFamily: "Helvetica-Bold", fontSize: 6.8, lineHeight: 1.2 }}>{i + 1}. {r.label}</Text>
          <Text style={{ color: text, fontFamily: "Helvetica-Bold", fontSize: 12.5, marginTop: 4 }}>{fmt(profileValue(r, d.metric))}</Text>
        </View>; })}
      </View>;
    })}
  </View>;
}

function impactRows(rows: readonly ReportProfileRow[]) { return overall(rows).filter((r) => (r.incidencePer1000h ?? 0) > 0 && (r.meanSeverityDays ?? 0) > 0).sort((a, b) => b.timeLossInjuries - a.timeLossInjuries || (b.burdenPer1000h ?? 0) - (a.burdenPer1000h ?? 0)); }
type LabelSpot = { x: number; y: number; offset: boolean };
/**
 * Data points stay on their exact coordinates. Only the numeral moves when
 * circles overlap, and a leader line ties the moved numeral back to its point.
 */
function placeLabels(points: Array<{ x: number; y: number }>, radius: number, bounds: { x0: number; y0: number; x1: number; y1: number }): LabelSpot[] {
  const near = radius + 7, far = radius + 15;
  const offsets: Array<[number, number]> = [[0, 0], [0, -near], [near, 0], [0, near], [-near, 0], [near - 1, -(near - 1)], [-(near - 1), -(near - 1)], [near - 1, near - 1], [-(near - 1), near - 1], [0, -far], [far, 0], [-far, 0], [0, far]];
  const placed: LabelSpot[] = [];
  return points.map((point, index) => {
    const crowded = points.some((other, j) => j !== index && Math.hypot(other.x - point.x, other.y - point.y) < radius * 2);
    const candidates = crowded ? offsets.slice(1) : offsets;
    const choice = candidates.find(([dx, dy]) => {
      const x = point.x + dx, y = point.y + dy;
      if (x < bounds.x0 + 6 || x > bounds.x1 - 6 || y < bounds.y0 + 6 || y > bounds.y1 - 6) return false;
      if (placed.some((spot) => Math.hypot(spot.x - x, spot.y - y) < 9)) return false;
      if (dx === 0 && dy === 0) return true;
      return points.every((other, j) => j === index || Math.hypot(other.x - x, other.y - y) >= radius + 4);
    }) ?? candidates[candidates.length - 1];
    const spot: LabelSpot = { x: point.x + choice[0], y: point.y + choice[1], offset: choice[0] !== 0 || choice[1] !== 0 };
    placed.push(spot);
    return spot;
  });
}
function ImpactMatrix({ rows, chartHeight = 250 }: { rows: readonly ReportProfileRow[]; chartHeight?: number }) {
  const data = impactRows(rows).slice(0, 12);
  const w = 316, h = chartHeight, left = 40, top = 24, right = 10, bottom = 38;
  const plotW = w - left - right, plotH = h - top - bottom;
  const xScale = niceScale(Math.max(0.1, ...data.map((r) => r.incidencePer1000h ?? 0)));
  const severityTop = Math.max(2, ...data.map((r) => r.meanSeverityDays ?? 0)) * 1.2;
  const logTop = Math.max(0.1, Math.log10(severityTop));
  const px = (v: number) => left + v / xScale.top * plotW;
  const py = (v: number) => top + plotH - Math.log10(Math.max(1, v)) / logTop * plotH;
  const radius = 6.5;
  const points = data.map((r) => ({ x: px(r.incidencePer1000h ?? 0), y: py(r.meanSeverityDays ?? 1) }));
  const labels = placeLabels(points, radius, { x0: left, y0: top, x1: left + plotW, y1: top + plotH });
  const keyRowHeight = Math.max(17, Math.min(30, (h - 22) / Math.max(1, data.length)));
  return <View style={styles.split}>
    <View style={{ width: "62%", paddingHorizontal: 4 }}>
      <Svg viewBox={`0 0 ${w} ${h}`} style={{ height: h }}>
      <Rect x={left} y={top} width={plotW} height={plotH} fill={C.white} stroke={C.line} strokeWidth={0.8} />
      {logTicks(severityTop).map((tick) => <G key={`y-${tick}`}>
        <Line x1={left} x2={left + plotW} y1={py(tick)} y2={py(tick)} stroke={C.rule} strokeWidth={0.8} />
        <SvgText x={left - 5} y={py(tick) + 2.4} textAnchor="end" fontSize={6.5} fill={C.muted}>{tick}</SvgText>
      </G>)}
      {xScale.ticks.map((tick) => <G key={`x-${tick}`}>
        <Line x1={px(tick)} x2={px(tick)} y1={top} y2={top + plotH} stroke={C.rule} strokeWidth={0.8} />
        <SvgText x={px(tick)} y={top + plotH + 11} textAnchor="middle" fontSize={6.5} fill={C.muted}>{tickText(tick)}</SvgText>
      </G>)}
      {points.map((point, i) => { const spot = labels[i]; if (!spot.offset) return null; const angle = Math.atan2(spot.y - point.y, spot.x - point.x); return <Line key={`leader-${data[i].code}`} x1={point.x + Math.cos(angle) * radius} y1={point.y + Math.sin(angle) * radius} x2={spot.x - Math.cos(angle) * 4.5} y2={spot.y - Math.sin(angle) * 4.5} stroke={C.muted} strokeWidth={0.5} />; })}
      {data.map((r, i) => <Circle key={r.code} cx={points[i].x} cy={points[i].y} r={radius} fill={profileColour(r.code)} stroke={C.white} strokeWidth={1.2} />)}
      {data.map((r, i) => { const spot = labels[i], fill = profileColour(r.code); return <SvgText key={`n-${r.code}`} x={spot.x} y={spot.y + 2.3} textAnchor="middle" fontSize={6.5} fontWeight="bold" fill={spot.offset ? fill : readableOn(fill)}>{i + 1}</SvgText>; })}
      <SvgText x={2} y={top - 9} fontSize={6.8} fill={C.ink}>Mean severity (days, logarithmic)</SvgText>
      <SvgText x={left + plotW / 2} y={h - 5} textAnchor="middle" fontSize={6.8} fill={C.ink}>Time-loss incidence per 1,000 player-hours</SvgText>
      </Svg>
    </View>
    <View style={{ width: "38%", paddingHorizontal: 4 }}>
      <View style={styles.headRow}>
        <Text style={[styles.columnHead, { flex: 1 }]}>Key</Text>
        <Text style={[styles.columnHead, { width: 40, textAlign: "right" }]}>Burden{"\n"}days/1,000 h</Text>
      </View>
      {data.map((r, i) => <View key={r.code} style={{ flexDirection: "row", alignItems: "center", minHeight: keyRowHeight }}>
        <View style={{ width: 12, height: 12, borderRadius: 6, backgroundColor: profileColour(r.code), alignItems: "center", justifyContent: "center", marginRight: 5 }}>
          <Text style={{ color: readableOn(profileColour(r.code)), fontFamily: "Helvetica-Bold", fontSize: 6.5 }}>{i + 1}</Text>
        </View>
        <Text style={{ flex: 1, fontSize: 6.5, lineHeight: 1.2, paddingRight: 4 }}>{r.label}</Text>
        <Text style={{ width: 40, textAlign: "right", color: C.ink, fontSize: 6.5 }}>{fmt(r.burdenPer1000h)}</Text>
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
    <Caption>Bars are time-loss cases on a shared scale of 0 to {tickText(max)}.</Caption>
  </View>;
}
function FamilyDossier({ rows }: { rows: readonly ReportInjuryTypeFamily[] }) {
  const lead = rows.filter((r) => r.setting === "all").sort((a, b) => b.timeLossInjuries - a.timeLossInjuries)[0];
  if (!lead) return <Text style={styles.panelNote}>Not available</Text>;
  return <View>
    <View style={styles.darkPanel}>
      <Text style={{ color: C.cyan, fontSize: 6.8, letterSpacing: 1, fontFamily: "Helvetica-Bold" }}>LEADING FAMILY</Text>
      <Text style={{ color: C.white, fontFamily: "Helvetica-Bold", fontSize: 16, marginTop: 5 }}>{lead.label}</Text>
      <View style={{ flexDirection: "row", marginTop: 10 }}>{([["Time-loss injuries", lead.timeLossInjuries, "cases"], ["Incidence", lead.incidencePer1000h, "per 1,000 h"], ["Burden", lead.burdenPer1000h, "days per 1,000 h"], ["Mean severity", lead.meanSeverityDays, "days"]] as const).map(([label, value, unit]) =>
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
function safeComparisonRows(model: ReportModel) { let anonymous = 0; return model.comparisonHeatmap.map((row) => ({ ...row, label: row.isSubject ? model.subjectName : `Anonymous club ${String(++anonymous).padStart(2, "0")}` })); }
function Heatmap({ model, rowHeight = 16 }: { model: ReportModel; rowHeight?: number }) {
  return <View>
    <View style={[styles.heatRow, { minHeight: 30, borderBottomColor: C.navy, borderLeftWidth: 2.5, borderLeftColor: C.white, alignItems: "flex-end", paddingBottom: 3 }]}>
      <Text style={[styles.heatName, styles.columnHead]}>Club</Text>
      {heatColumns.map((c) => <View key={c.key} style={{ flex: 1, paddingHorizontal: 2 }}>
        <Text style={[styles.columnHead, { textAlign: "center" }]}>{c.label}</Text>
        <Text style={[styles.columnHead, { textAlign: "center", color: C.grey }]}>{c.unit}</Text>
      </View>)}
    </View>
    {safeComparisonRows(model).map((r, i) => <View key={`${r.label}-${i}`} style={[styles.heatRow, { minHeight: rowHeight, borderLeftWidth: 2.5, borderLeftColor: r.isSubject ? model.brand.accentColour : C.white }, r.isSubject ? { backgroundColor: "#EDF3F9" } : {}]}>
      <Text style={[styles.heatName, r.isSubject ? { fontFamily: "Helvetica-Bold", color: model.brand.accentColour } : {}]}>{r.label}</Text>
      {heatColumns.map((c) => { const colour = benchmarkColour(r[c.key], model.comparisonBenchmarks[c.key]); return <Text key={c.key} style={[styles.heatCell, { backgroundColor: colour, color: colour === HEAT_NEUTRAL ? C.ink : C.white }]}>{fmt(r[c.key])}</Text>; })}
    </View>)}
    <Legend items={[
      { label: "Below mean", colour: C.green, shape: "swatch" },
      { label: "Within 10%", colour: HEAT_AMBER, shape: "swatch" },
      { label: "Above mean", colour: C.red, shape: "swatch" },
      { label: "Not available", colour: HEAT_NEUTRAL, shape: "swatch" },
    ]} />
    <Caption>Below and above mean the value differs from the released league mean by at least 10%. {model.subjectName} carries the accent rule.</Caption>
  </View>;
}
function ComparisonLadder({ model, rowGap = 9 }: { model: ReportModel; rowGap?: number }) {
  const rows = safeComparisonRows(model).filter((r) => r.allIncidencePer1000h !== null).sort((a, b) => (b.allIncidencePer1000h ?? 0) - (a.allIncidencePer1000h ?? 0));
  const max = Math.max(1, ...rows.map((r) => r.allIncidencePer1000h ?? 0)), mean = model.comparisonBenchmarks.allIncidencePer1000h ?? 0;
  return <View>
    <View style={styles.headRow}>
      <Text style={[styles.columnHead, { width: 16 }]}>#</Text>
      <Text style={[styles.columnHead, { width: 74 }]}>Club</Text>
      <Text style={[styles.columnHead, { flex: 1 }]}>0 to {tickText(max)}</Text>
      <Text style={[styles.columnHead, { width: 30, textAlign: "right" }]}>/1,000 h</Text>
    </View>
    {rows.map((r, i) => <View key={`${r.label}-${i}`} style={{ flexDirection: "row", alignItems: "center", marginBottom: rowGap }}>
      <Text style={{ width: 16, color: C.muted, fontSize: 6.5 }}>{i + 1}</Text>
      <Text style={{ width: 74, fontFamily: r.isSubject ? "Helvetica-Bold" : "Helvetica", color: r.isSubject ? model.brand.accentColour : C.ink, fontSize: 6.5, paddingRight: 3 }}>{r.label}</Text>
      <View style={{ flex: 1, height: 8, backgroundColor: C.track, position: "relative", marginRight: 5 }}>
        <View style={{ height: 8, width: `${(r.allIncidencePer1000h ?? 0) / max * 100}%`, backgroundColor: r.isSubject ? model.brand.accentColour : C.blue }} />
        <View style={{ position: "absolute", left: `${mean / max * 100}%`, top: -2, width: 1.2, height: 12, backgroundColor: C.coral }} />
      </View>
      <Text style={{ width: 30, textAlign: "right", fontSize: 6.5 }}>{fmt(r.allIncidencePer1000h)}</Text>
    </View>)}
    <Legend items={[{ label: model.subjectName, colour: model.brand.accentColour, shape: "bar" }, { label: "Anonymous club", colour: C.blue, shape: "bar" }, { label: `League mean ${fmt(mean)}`, colour: C.coral, shape: "line" }]} />
  </View>;
}
function ComparisonScatter({ model, chartHeight = 275 }: { model: ReportModel; chartHeight?: number }) {
  const data = safeComparisonRows(model).filter((r) => r.matchIncidencePer1000h !== null && r.trainingIncidencePer1000h !== null);
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
      <SvgText x={2} y={top - 9} fontSize={6.8} fill={C.ink}>Training time-loss incidence (per 1,000 player-hours)</SvgText>
      <SvgText x={left + plotW / 2} y={h - 5} textAnchor="middle" fontSize={6.8} fill={C.ink}>Match time-loss incidence (injuries per 1,000 player-hours)</SvgText>
    </Svg>
    <Legend items={[{ label: model.subjectName, colour: model.brand.accentColour }, { label: "Anonymous club", colour: C.blue }, { label: `League mean, match ${fmt(meanX)} and training ${fmt(meanY)}`, colour: C.coral, shape: "line" }]} />
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
  const distancePath = rows.map((r, i) => r.distanceKm === null ? "" : `${i ? "L" : "M"} ${x(i)} ${distY(r.distanceKm)}`).filter(Boolean).join(" ");
  const barWidth = Math.min(30, slot * 0.6);
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
        <Rect x={x(i) - barWidth / 2} y={hoursY(r.exposureHours ?? 0)} width={barWidth} height={top + plotH - hoursY(r.exposureHours ?? 0)} fill={C.mint} />
        <SvgText x={x(i)} y={top + plotH + 12} textAnchor="middle" fontSize={6.5} fill={C.muted}>{shortMonth(r.month)}</SvgText>
      </G>)}
      <Path d={distancePath} fill="none" stroke={C.cyan} strokeWidth={2.3} />
      {rows.map((r, i) => r.distanceKm !== null ? <Circle key={`p-${r.month}`} cx={x(i)} cy={distY(r.distanceKm)} r={2.4} fill={C.cyan} stroke={C.white} strokeWidth={0.8} /> : null)}
      <SvgText x={2} y={top - 9} fontSize={6.8} fill={C.ink}>Player-hours</SvgText>
      <SvgText x={w - 2} y={top - 9} textAnchor="end" fontSize={6.8} fill={C.ink}>Distance (km)</SvgText>
    </Svg>
    <Legend items={[{ label: "Player-hours (left axis)", colour: C.mint, shape: "bar" }, { label: "Distance in km (right axis)", colour: C.cyan, shape: "line" }]} />
    <Caption>Monthly released exposure across {monthRange(rows)}.</Caption>
  </View>;
}
function ExposureLadder({ model, keyName, label, unit, colour, rowGap = 9 }: { model: ReportModel; keyName: "exposureHours" | "distanceKm"; label: string; unit: string; colour: string; rowGap?: number }) {
  const rows = safeComparisonRows(model).filter((r) => r[keyName] !== null).sort((a, b) => (b[keyName] ?? 0) - (a[keyName] ?? 0));
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
function ComparisonTable({ metrics, currentLabel = "Selected", comparisonLabel = "Comparison", limit = 6, sharedReason }: { metrics: readonly SeasonComparisonMetric[]; currentLabel?: string; comparisonLabel?: string; limit?: number; sharedReason?: string }) {
  return <View>
    <View style={[styles.headRow, { marginBottom: 3 }]}>
      <Text style={[styles.columnHead, { flex: 1 }]}>Metric</Text>
      <Text style={[styles.columnHead, { width: 44, textAlign: "right" }]}>{currentLabel}</Text>
      <Text style={[styles.columnHead, { width: 44, textAlign: "right" }]}>{comparisonLabel}</Text>
      <Text style={[styles.columnHead, { width: 118, paddingLeft: 8 }]}>Change</Text>
    </View>
    {metrics.slice(0, limit).map((m) => <View key={m.key} style={[styles.compactTableRow, { minHeight: 24, alignItems: "center" }]}>
      <Text style={styles.compactLabel}>{m.label}</Text>
      <Text style={[styles.compactNumber, { width: 44, color: C.navy, fontFamily: "Helvetica-Bold" }]}>{fmt(m.currentValue)}</Text>
      <Text style={[styles.compactNumber, { width: 44 }]}>{fmt(m.priorValue)}</Text>
      <Text style={{ width: 118, paddingLeft: 8, color: C.muted, fontSize: 6.5, lineHeight: 1.25 }}>{sharedReason && m.deltaReason === sharedReason ? "Not comparable*" : m.deltaReason ?? fmt(m.delta)}</Text>
    </View>)}
    {sharedReason && <Caption>* {sharedReason}.</Caption>}
  </View>;
}

function CoverPage({ model, meta }: { model: ReportModel; meta: ReportMetadata }) {
  return <Page size="A4" style={styles.cover}>
    <View style={{ height: 38, flexDirection: "row", alignItems: "center" }}><Text style={styles.eyebrow}>United Rugby Championship</Text></View>
    <View style={{ position: "absolute", right: -60, top: 145, width: 300, height: 300, borderRadius: 150, borderWidth: 34, borderColor: "#0C315D", opacity: .65 }} />
    <View style={{ position: "absolute", right: 10, top: 215, width: 180, height: 180, borderRadius: 90, borderWidth: 2, borderColor: C.cyan, opacity: .28 }} />
    <View style={{ flex: 1, justifyContent: "center" }}>
      <View style={{ flexDirection: "row", alignItems: "center" }}>
        <View style={{ width: "68%" }}>
          <Text style={{ color: C.cyan, fontFamily: "Helvetica-Bold", fontSize: 9, letterSpacing: 1.5 }}>TEAM PERFORMANCE REPORT</Text>
          <Text style={{ color: C.white, fontFamily: "Helvetica-Bold", fontSize: 38, lineHeight: 1.02, marginTop: 14 }}>{model.subjectName}</Text>
          <Text style={{ color: C.white, fontFamily: "Helvetica-Bold", fontSize: 28, lineHeight: 1.04 }}>Injury surveillance</Text>
          <Text style={{ color: C.blue, fontFamily: "Helvetica-Bold", fontSize: 17, marginTop: 13 }}>{model.season} season</Text>
        </View>
        <View style={{ width: "32%", alignItems: "center" }}>{model.brand.crestDataUri && <Image src={model.brand.crestDataUri} style={{ width: 122, height: 122, objectFit: "contain" }} />}</View>
      </View>
      <View style={{ height: 1, backgroundColor: "#294565", marginTop: 32, marginBottom: 18 }} />
      <View style={{ flexDirection: "row" }}>
        <View style={{ width: "50%" }}><Text style={{ color: "#93A9C1", fontSize: 6.8, letterSpacing: 1 }}>ANALYSIS WINDOW</Text><Text style={{ color: C.white, fontSize: 10, marginTop: 5 }}>{formatDate(model.analysisWindow.start)} to {formatDate(model.analysisWindow.end)}</Text></View>
        <View style={{ width: "25%" }}><Text style={{ color: "#93A9C1", fontSize: 6.8, letterSpacing: 1 }}>REPORT VERSION</Text><Text style={{ color: C.white, fontSize: 10, marginTop: 5 }}>v{meta.version}</Text></View>
        <View style={{ width: "25%" }}><Text style={{ color: "#93A9C1", fontSize: 6.8, letterSpacing: 1 }}>EXPORTED</Text><Text style={{ color: C.white, fontSize: 10, marginTop: 5 }}>{formatDate(meta.exportedAt)}</Text></View>
      </View>
    </View>
    <Footer model={model} meta={meta} cover />
  </Page>;
}

function SeasonPattern({ model, meta }: { model: ReportModel; meta: ReportMetadata }) {
  return <PageShell model={model} meta={meta} section="season-pattern">
    <PageTitle title="Season overview" note="Headline measures, the monthly pattern and the setting split are brought together on the first analytical page." />
    <MetricCards model={model} />
    <View style={{ marginTop: 8 }}><Panel title="Monthly injury pattern" note="Case counts and incidence for each month of the analysis window."><TimelineChart rows={model.monthlyInjuryPattern} chartHeight={215} /></Panel></View>
    <View style={{ marginTop: 8 }}><Panel title="Match and training" note="Released setting measures shown side by side."><SettingBench rows={model.matchTraining} /></Panel></View>
  </PageShell>;
}
function SeverityContact({ model, meta }: { model: ReportModel; meta: ReportMetadata }) {
  return <PageShell model={model} meta={meta} section="severity-contact">
    <PageTitle title="Severity and mechanism" note="Case consequences and contact context are shown alongside the team setting split." />
    <View style={[styles.split, { height: 300 }]}>
      <View style={styles.third}><Panel fill title="Severity profile" note="All recorded injuries by released duration band."><HalfRing rows={model.severityDistribution} colours={SEVERITY_COLOURS} unitHead="Cases (share)" /></Panel></View>
      <View style={styles.third}><Panel fill title="Contact mechanism" note="Time-loss injuries by released mechanism."><HalfRing rows={model.contactDistribution} colours={CONTACT_COLOURS} value="timeLoss" unitHead="Cases (share)" /></Panel></View>
      <View style={styles.third}><Panel fill title="Setting contrast" note="Match and training measures for the same window."><CompactSettingBench rows={model.matchTraining} /></Panel></View>
    </View>
    <View style={{ marginTop: 8, height: 320 }}>
      <Panel fill title="Leading locations and injury types" note="Time-loss rankings from the released profile rows. Each category keeps one colour throughout the report.">
        <View style={styles.split}>
          <View style={styles.half}><RankedBars rows={overall(model.injuryProfile.bodyLocations)} limit={10} coloured heading="Body region" unit="Cases" rowGap={15} /></View>
          <View style={styles.half}><RankedBars rows={overall(model.injuryProfile.injuryTypes)} limit={10} coloured heading="Injury type" unit="Cases" rowGap={15} /></View>
        </View>
      </Panel>
    </View>
  </PageShell>;
}
function InjuryLocation({ model, meta }: { model: ReportModel; meta: ReportMetadata }) {
  const rows = overall(model.injuryProfile.bodyLocations);
  return <PageShell model={model} meta={meta} section="injury-location">
    <PageTitle title="Injury location" note="The body map, ranked locations and match-training split use the released body-location rows." />
    <View style={[styles.split, { height: 400 }]}>
      <View style={{ width: "38%", paddingHorizontal: 4 }}><Panel fill title="Body heat map" note="Front and back views of the released body-location rows."><BodyMapPdf rows={rows} chartHeight={270} /></Panel></View>
      <View style={{ width: "62%", paddingHorizontal: 4 }}>
        <Panel fill title="Ranked locations" note="Time-loss case counts, then the matching rate measures for the leading regions.">
          <RankedBars rows={rows} limit={11} coloured heading="Body region" unit="Cases" rowGap={5} />
          <View style={[styles.headRow, { marginTop: 8, alignItems: "flex-end" }]}>
            <Text style={[styles.columnHead, { flex: 1 }]}>Body region</Text>
            <View style={{ width: 174 }}>
              <Text style={[styles.columnHead, { textAlign: "right", marginBottom: 3 }]}>Time-loss rate measures</Text>
              <View style={{ flexDirection: "row" }}>
                <Text style={[styles.columnHead, { width: 58, textAlign: "right", paddingLeft: 3 }]}>Incidence{"\n"}/1,000 h</Text>
                <Text style={[styles.columnHead, { width: 58, textAlign: "right", paddingLeft: 4, borderLeftWidth: 1, borderLeftColor: C.rule }]}>Burden{"\n"}days/1,000 h</Text>
                <Text style={[styles.columnHead, { width: 58, textAlign: "right", paddingLeft: 4, borderLeftWidth: 1, borderLeftColor: C.rule }]}>Mean severity{"\n"}days</Text>
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
    <View style={{ marginTop: 8, height: 275 }}><Panel fill title="Match versus training by region" note="Time-loss case counts for the leading regions."><MirroredBars rows={model.injuryProfile.bodyLocations} rowGap={11} heading="Body region" /></Panel></View>
  </PageShell>;
}
function CommonInjuries({ model, meta }: { model: ReportModel; meta: ReportMetadata }) {
  const diagnoses = overall(model.injuryProfile.diagnoses);
  return <PageShell model={model} meta={meta} section="common-injuries">
    <PageTitle title="Common injuries" note="Each diagnosis keeps one colour across frequency, incidence, burden and severity." />
    <View style={{ height: 330 }}><Panel fill title="Four views of the leading diagnoses" note="The top five released diagnoses for each measure. Each diagnosis keeps one colour across the four columns."><CommonLanes rows={diagnoses} cardHeight={45} /></Panel></View>
    <View style={{ marginTop: 8, height: 342 }}>
      <Panel fill title="Diagnosis impact matrix" note="Horizontal position is time-loss incidence and vertical position is mean severity on a logarithmic scale.">
        <ImpactMatrix rows={model.injuryProfile.diagnoses} chartHeight={282} />
      </Panel>
    </View>
  </PageShell>;
}
function ImpactMatrices({ model, meta }: { model: ReportModel; meta: ReportMetadata }) {
  return <PageShell model={model} meta={meta} section="impact-matrices">
    <PageTitle title="Injury impact matrices" note="Location and injury-type views use the same axes and visual grammar as the diagnosis matrix." />
    <View style={{ height: 336 }}><Panel fill title="Location impact" note="Time-loss incidence against mean severity on a logarithmic scale."><ImpactMatrix rows={model.injuryProfile.bodyLocations} chartHeight={291} /></Panel></View>
    <View style={{ marginTop: 8, height: 336 }}><Panel fill title="Injury-type impact" note="Time-loss incidence against mean severity on a logarithmic scale."><ImpactMatrix rows={model.injuryProfile.injuryTypes} chartHeight={291} /></Panel></View>
  </PageShell>;
}
function InjuryTypes({ model, meta }: { model: ReportModel; meta: ReportMetadata }) {
  return <PageShell model={model} meta={meta} section="injury-types">
    <PageTitle title="Injury type" note="Injury families, subtype detail and setting contrast share one analytical page." />
    <View style={[styles.split, { height: 300 }]}>
      <View style={styles.half}><Panel fill title="Injury-family ranking" note="Overall time-loss injuries and incidence."><FamilyRanking rows={model.injuryProfile.injuryTypeFamilies} rowGap={6} /></Panel></View>
      <View style={styles.half}><Panel fill title="Leading-family dossier" note="Released family and subtype measures."><FamilyDossier rows={model.injuryProfile.injuryTypeFamilies} /></Panel></View>
    </View>
    <View style={{ marginTop: 8, height: 350 }}><Panel fill title="Match versus training by injury type" note="Time-loss case counts for the leading injury types."><MirroredBars rows={model.injuryProfile.injuryTypes} limit={10} rowGap={16} heading="Injury type" /></Panel></View>
  </PageShell>;
}
function Exposure({ model, meta }: { model: ReportModel; meta: ReportMetadata }) {
  const cards: Array<ReportMetric> = [
    { key: "total-hours", label: "Total exposure", value: model.exposure.totalHours, unit: "player-hours", formula: "released exposure" },
    { key: "match-hours", label: "Match exposure", value: model.exposure.matchHours, unit: "player-hours", formula: "released exposure" },
    { key: "training-hours", label: "Training exposure", value: model.exposure.trainingHours, unit: "player-hours", formula: "released exposure" },
    { key: "distance", label: "Distance", value: model.exposure.totalDistanceKm, unit: "km", formula: "released distance" },
  ];
  const pseudo = { ...model, snapshotMetrics: cards };
  return <PageShell model={model} meta={meta} section="exposure">
    <PageTitle title="Exposure" note="The released denominator is shown over time and against the anonymous league cohort." />
    <MetricCards model={pseudo} limit={4} trend={false} />
    <View style={{ marginTop: 8, height: 280 }}><Panel fill title="Monthly exposure and distance" note="Player-hours on the left axis and kilometres on the right axis."><ExposureTrend model={model} chartHeight={213} /></Panel></View>
    <View style={[styles.split, { marginTop: 8, height: 320 }]}>
      <View style={styles.half}><Panel fill title="Club exposure hours" note="Released player-hours for every club in the cohort."><ExposureLadder model={model} keyName="exposureHours" label="Player-hours" unit="Hours" colour={C.mint} rowGap={9} /></Panel></View>
      <View style={styles.half}><Panel fill title="Club distance" note="Released distance for every club in the cohort."><ExposureLadder model={model} keyName="distanceKm" label="Kilometres" unit="km" colour={C.cyan} rowGap={9} /></Panel></View>
    </View>
  </PageShell>;
}
function TeamComparison({ model, meta }: { model: ReportModel; meta: ReportMetadata }) {
  return <PageShell model={model} meta={meta} section="team-comparison">
    <PageTitle title="Team comparison" note={`Other clubs remain anonymous. ${model.subjectName} is highlighted against released league benchmarks.`} />
    <View style={{ height: 322 }}>
      <Panel fill title="Match versus training time-loss incidence" note="One bubble for each club in the released cohort. Dashed lines are the league means.">
        <ComparisonScatter model={model} chartHeight={238} />
      </Panel>
    </View>
    <View style={[styles.split, { marginTop: 8, height: 350 }]}>
      <View style={{ width: "42%", paddingHorizontal: 4 }}><Panel fill title="Overall incidence ladder" note="Time-loss injuries per 1,000 player-hours."><ComparisonLadder model={model} rowGap={9} /></Panel></View>
      <View style={{ width: "58%", paddingHorizontal: 4 }}><Panel fill title="Four-metric benchmark heat map" note="Each cell is compared with the released league mean for that metric."><Heatmap model={model} rowHeight={15} /></Panel></View>
    </View>
  </PageShell>;
}
function SeasonMethodology({ model, meta }: { model: ReportModel; meta: ReportMetadata }) {
  const items = [...model.method, ...model.limitations];
  return <PageShell model={model} meta={meta} section="season-methodology">
    <PageTitle title="Season comparison and method" note={`The selected ${model.season} release is compared with the approved ${model.seasonComparison.comparisonSeason} release where definitions permit.`} />
    <View style={[styles.split, { height: 312 }]}>
      <View style={{ width: "58%", paddingHorizontal: 4 }}>
        <Panel fill title={`${model.season} versus ${model.seasonComparison.comparisonSeason}`} note="Unavailable differences are explained rather than inferred.">
          <ComparisonTable metrics={model.seasonComparison.headline} currentLabel={model.season} comparisonLabel={model.seasonComparison.comparisonSeason} limit={7} />
          <View style={[styles.note, { marginTop: 9 }]}><Text>{model.seasonComparison.note || model.seasonComparison.status}</Text></View>
        </Panel>
      </View>
      <View style={{ width: "42%", paddingHorizontal: 4 }}>
        <Panel fill title="Methodology and limitations" note="Released aggregate dashboard values only.">
          {items.length
            ? items.slice(0, 12).map((item, i) => <View key={`${i}-${item}`} style={styles.listItem}><View style={styles.bullet} /><Text style={{ flex: 1, fontSize: 6.8, lineHeight: 1.35 }}>{item}</Text></View>)
            : <Text style={styles.panelNote}>Not available</Text>}
          <View style={[styles.note, { marginTop: 8 }]}><Text>Not available values remain unavailable. They are not reconstructed for this report.</Text></View>
        </Panel>
      </View>
    </View>
    <View style={{ marginTop: 8, height: 256 }}><Panel fill title="Setting comparison" note="Match and training values from both approved season releases."><ComparisonTable metrics={model.seasonComparison.settings} currentLabel={model.season} comparisonLabel={model.seasonComparison.comparisonSeason} limit={6} sharedReason="Released setting definitions do not include comparable formula metadata" /></Panel></View>
    <View style={{ marginTop: 8, height: 92 }}>
      <Panel fill title="Publication record" note="This information appears on every page for auditability.">
        <View style={[styles.split, { marginTop: 4 }]}>
          <View style={styles.third}><Text style={styles.columnHead}>Report version</Text><Text style={[styles.metricValue, { fontSize: 14, marginTop: 6 }]}>v{meta.version}</Text></View>
          <View style={styles.third}><Text style={styles.columnHead}>Source generated</Text><Text style={[styles.metricValue, { fontSize: 14, marginTop: 6 }]}>{formatDate(meta.sourceGeneratedAt)}</Text></View>
          <View style={styles.third}><Text style={styles.columnHead}>Export date</Text><Text style={[styles.metricValue, { fontSize: 14, marginTop: 6 }]}>{formatDate(meta.exportedAt)}</Text></View>
        </View>
      </Panel>
    </View>
  </PageShell>;
}

const sectionPages: Record<ReportSectionId, (model: ReportModel, meta: ReportMetadata) => ReactElement> = {
  cover: (m, x) => <CoverPage model={m} meta={x} />, "season-pattern": (m, x) => <SeasonPattern model={m} meta={x} />,
  "severity-contact": (m, x) => <SeverityContact model={m} meta={x} />, "injury-location": (m, x) => <InjuryLocation model={m} meta={x} />,
  "common-injuries": (m, x) => <CommonInjuries model={m} meta={x} />, "impact-matrices": (m, x) => <ImpactMatrices model={m} meta={x} />,
  "injury-types": (m, x) => <InjuryTypes model={m} meta={x} />, exposure: (m, x) => <Exposure model={m} meta={x} />,
  "team-comparison": (m, x) => <TeamComparison model={m} meta={x} />, "season-methodology": (m, x) => <SeasonMethodology model={m} meta={x} />,
};
export function enabledReportSections(sectionIds?: readonly ReportSectionId[]) { const requested = new Set(sectionIds ?? DEFAULT_REPORT_SECTION_IDS); return DEFAULT_REPORT_SECTION_IDS.filter((id) => requested.has(id)); }
export function ReportDocument({ model, enabledSectionIds }: { model: ReportModel; enabledSectionIds?: readonly ReportSectionId[] }) { if (model.schemaVersion !== "urc-report-v1") throw new Error("Unsupported report model schema"); const meta = metadata(model); return <Document title={`${model.subjectName} injury surveillance report ${model.season}`} author="United Rugby Championship" subject={`Released aggregate injury surveillance metrics | ${meta.version}`} creator="URC injury surveillance" creationDate={new Date(meta.exportedAt)}>{enabledReportSections(enabledSectionIds).map((section) => cloneElement(sectionPages[section](model, meta), { key: section }))}</Document>; }
