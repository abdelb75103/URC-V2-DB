import { getMunsterDashboard, type AnalyticsRow } from "../lib/reporting";

export const dynamic = "force-static";

function fmt(value: number | null | undefined, digits = 1) {
  if (value === null || value === undefined) return "Pending";
  return new Intl.NumberFormat("en-IE", {
    maximumFractionDigits: digits,
    minimumFractionDigits: Number.isInteger(value) ? 0 : digits,
  }).format(value);
}

function metricValue(
  headline: Record<string, { value: number | null; unit: string }>,
  key: string,
) {
  return headline[key]?.value;
}

function maxValue(rows: AnalyticsRow[], key: keyof AnalyticsRow) {
  return Math.max(...rows.map((row) => Number(row[key]) || 0), 1);
}

function MonthlyBars({
  rows,
  valueKey,
  digits = 1,
  label,
}: {
  rows: AnalyticsRow[];
  valueKey: keyof AnalyticsRow;
  digits?: number;
  label: string;
}) {
  const max = maxValue(rows, valueKey);

  return (
    <ol className="monthlyBars" aria-label={label}>
      {rows.map((row) => {
        const value = Number(row[valueKey]) || 0;
        return (
          <li key={row.month}>
            <span className="barValue">{fmt(value, digits)}</span>
            <span className="barColumn" aria-hidden="true">
              <span style={{ height: `${Math.max((value / max) * 100, value ? 3 : 0)}%` }} />
            </span>
            <span className="barMonth">{row.month?.split(" ")[0]}</span>
          </li>
        );
      })}
    </ol>
  );
}

export default function Home() {
  const dashboard = getMunsterDashboard();
  const headline = Object.fromEntries(dashboard.headline.map((metric) => [metric.key, metric]));
  const medicalAttention = dashboard.severity_distribution.find(
    (row) => row.key === "zero_days_medical_attention_only",
  )?.recorded_injuries;
  const daysLost = dashboard.setting_split.reduce((sum, row) => sum + row.days_lost, 0);
  const maxSeverity = Math.max(
    ...dashboard.severity_distribution.map((row) => row.recorded_injuries),
    1,
  );

  return (
    <div className="appShell">
      <header className="teamHeader">
        <a className="backButton" href="#" aria-label="Back to dashboard index">
          <span aria-hidden="true">‹</span>
        </a>
        <img className="teamCrest" src="/munster-crest.png" alt="Munster Rugby crest" />
        <div>
          <h1>Munster Dashboard</h1>
          <p>{dashboard.season} injury surveillance</p>
        </div>
      </header>

      <nav className="teamTabs" aria-label="Munster dashboard sections">
        <a className="active" href="#overview" aria-current="page">Overview</a>
        <span aria-disabled="true">Teams Comparison</span>
        <span aria-disabled="true">Most Common Injuries &amp; Illnesses</span>
        <span aria-disabled="true">Injury by Location</span>
        <span aria-disabled="true">Injury by Type &amp; Tissue</span>
        <span aria-disabled="true">Exposure</span>
      </nav>

      <main id="overview">
        <div className="pageHeading">
          <div>
            <h2>Team Overview</h2>
            <p>Validated aggregate results for the accepted Munster coverage window.</p>
          </div>
          <span className="releaseStatus">V2 pilot</span>
        </div>

        <section className="snapshot panel" aria-labelledby="snapshot-title">
          <h3 id="snapshot-title">Injury Snapshot</h3>
          <div className="snapshotGrid">
            <div className="snapshotCounts">
              <div className="totalMetric">
                <span>Recorded injuries</span>
                <strong>{fmt(metricValue(headline, "recorded_injuries"), 0)}</strong>
              </div>
              <div className="countGrid">
                <div className="metricInset">
                  <span>Time-loss</span>
                  <strong>{fmt(metricValue(headline, "time_loss_injuries"), 0)}</strong>
                </div>
                <div className="metricInset">
                  <span>Medical-attention only</span>
                  <strong>{fmt(medicalAttention, 0)}</strong>
                </div>
              </div>
            </div>

            <div className="snapshotRates">
              <p className="metricGroupLabel">All-activity rates</p>
              <div className="rateGrid">
                <div className="metricInset">
                  <span>Incidence</span>
                  <strong>{fmt(metricValue(headline, "incidence_per_1000h"))}</strong>
                  <small>per 1,000 player-hours</small>
                </div>
                <div className="metricInset">
                  <span>Burden</span>
                  <strong>{fmt(metricValue(headline, "burden_per_1000h"))}</strong>
                  <small>days per 1,000 player-hours</small>
                </div>
                <div className="metricInset">
                  <span>Mean severity</span>
                  <strong>{fmt(metricValue(headline, "severity_mean_days"))}</strong>
                  <small>days lost per injury</small>
                </div>
              </div>
              <p className="metricNote">
                Match and training rates remain pending until setting-specific exposure is available.
              </p>
            </div>
          </div>
        </section>

        <dl className="coverageStrip" aria-label="Coverage summary">
          <div><dt>Player-hours</dt><dd>{fmt(dashboard.coverage.hours)}</dd></div>
          <div><dt>Exposed players</dt><dd>{fmt(dashboard.coverage.exposed_players, 0)}</dd></div>
          <div><dt>Reporting weeks</dt><dd>{fmt(dashboard.coverage.weeks, 0)}</dd></div>
          <div><dt>Days lost</dt><dd>{fmt(daysLost, 0)}</dd></div>
          <div><dt>Coverage window</dt><dd>{dashboard.analysis_window.start} to {dashboard.analysis_window.end}</dd></div>
        </dl>

        <section className="panel chartPanel" aria-labelledby="injuries-month-title">
          <div className="panelHeading">
            <div>
              <h3 id="injuries-month-title">Time-Loss Injuries by Month</h3>
              <p>Injuries with more than zero days lost, grouped by injury month.</p>
            </div>
            <span className="chartUnit">Count</span>
          </div>
          <MonthlyBars
            rows={dashboard.monthly}
            valueKey="time_loss_injuries"
            digits={0}
            label="Monthly time-loss injury counts"
          />
        </section>

        <div className="chartGrid">
          <section className="panel chartPanel" aria-labelledby="incidence-month-title">
            <div className="panelHeading">
              <div>
                <h3 id="incidence-month-title">Incidence by Month</h3>
                <p>Time-loss injuries per 1,000 all-activity player-hours.</p>
              </div>
              <span className="chartUnit">Per 1,000h</span>
            </div>
            <MonthlyBars
              rows={dashboard.monthly}
              valueKey="incidence_per_1000h"
              label="Monthly injury incidence"
            />
          </section>

          <section className="panel chartPanel" aria-labelledby="burden-month-title">
            <div className="panelHeading">
              <div>
                <h3 id="burden-month-title">Burden by Month</h3>
                <p>Days lost per 1,000 all-activity player-hours.</p>
              </div>
              <span className="chartUnit">Days per 1,000h</span>
            </div>
            <MonthlyBars
              rows={dashboard.monthly}
              valueKey="burden_per_1000h"
              label="Monthly injury burden"
            />
          </section>
        </div>

        <section className="panel severityPanel" aria-labelledby="severity-title">
          <div className="panelHeading">
            <div>
              <h3 id="severity-title">Severity of Recorded Injuries</h3>
              <p>IOC-aligned distribution by days lost, including unknown or censored records.</p>
            </div>
            <span className="chartUnit">Recorded injuries</span>
          </div>
          <div className="severityGrid">
            {dashboard.severity_distribution.map((row) => (
              <div className="severityItem" key={row.key}>
                <div>
                  <span>{row.label}</span>
                  <strong>{row.recorded_injuries}</strong>
                </div>
                <div className="severityBar" aria-hidden="true">
                  <span style={{ width: `${(row.recorded_injuries / maxSeverity) * 100}%` }} />
                </div>
              </div>
            ))}
          </div>
          <div className="severitySummary">
            <div><span>Mean severity</span><strong>{fmt(metricValue(headline, "severity_mean_days"))} days</strong></div>
            <div><span>Median severity</span><strong>{fmt(metricValue(headline, "severity_median_days"), 0)} days</strong></div>
            <div><span>Unknown or censored</span><strong>{dashboard.severity_distribution.at(-1)?.recorded_injuries ?? 0} records</strong></div>
          </div>
        </section>

        <div className="detailGrid">
          <section className="panel detailPanel" aria-labelledby="setting-title">
            <div className="panelHeading">
              <div>
                <h3 id="setting-title">Injuries by Setting</h3>
                <p>Counts and days lost only. Setting-specific rates are not calculated.</p>
              </div>
            </div>
            <div className="dataRows">
              {dashboard.setting_split.map((row) => (
                <div className="dataRow" key={row.label}>
                  <span className="dataLabel">{row.label}</span>
                  <span><strong>{row.time_loss_injuries}</strong> injuries</span>
                  <span><strong>{fmt(row.days_lost, 0)}</strong> days lost</span>
                </div>
              ))}
            </div>
          </section>

          <section className="panel detailPanel" aria-labelledby="comparison-title">
            <div className="panelHeading">
              <div>
                <h3 id="comparison-title">Prior-Season Comparison</h3>
                <p>A comparable prior-season denominator has not passed the V2 workflow.</p>
              </div>
            </div>
            <div className="pendingState">
              <strong>{dashboard.prior_season.season}</strong>
              <span>Pending matched V2 data</span>
              <p>{dashboard.prior_season.note}</p>
            </div>
          </section>
        </div>

        <section className="methodNote" aria-labelledby="method-title">
          <h3 id="method-title">Calculation basis</h3>
          <p>
            Incidence is time-loss injuries divided by exposure hours. Burden is days lost divided
            by exposure hours. Both are reported per 1,000 player-hours from the same accepted V2
            aggregate artifact.
          </p>
        </section>
      </main>

      <footer>
        United Rugby Championship and University College Dublin. Aggregate research dashboard.
      </footer>
    </div>
  );
}
