import { useState } from 'react';
import { api } from '../api.js';
import { QuarterBars } from '../components/Charts.jsx';
import { Badge, Empty, ErrorNote, Loading, Panel, PageHeader, PatternBadge, Segmented, Select, Stat, Table } from '../components/ui.jsx';
import { fmtNum, fmtPct, quarterLabel, useAsync } from '../lib.js';

export default function QuarterlyPage({ viewer }) {
  const [quarter, setQuarter] = useState('');
  const [show, setShow] = useState('all');
  const [metric, setMetric] = useState('records');
  const res = useAsync(() => api.quarterly(quarter), [quarter]);
  const forecast = useAsync(() => api.trendPrediction(), []);
  const d = res.data;
  const prediction = forecast.data;

  const rows = !d ? [] : d.rows.filter((r) => (show === 'all' ? true : show === 'recurring' ? r.recurring : r.status === show));
  const value = (r, key) => fmtNum(r[key][r.basis]);

  return (
    <div>
      <PageHeader
        title="Quarterly patterns"
        description="Each municipality and pest compared with the previous quarter, and with the same quarter last year to spot recurring infestations. Validated observations only."
        area={viewer.role === 'agriculturist' ? undefined : viewer.area_label}
        actions={
          d?.quarters.length ? (
            <Select
              value={d.quarter}
              onChange={setQuarter}
              options={[...d.quarters].reverse().map((q) => [q.quarter, quarterLabel(q.quarter)])}
              className="min-w-[140px]"
              aria-label="Quarter"
            />
          ) : null
        }
      />
      <div className="mb-6">
        <Panel
          title="Four-week pest trend forecast"
          subtitle="Scikit-learn projects validated pest counts for your authorized area. This is a planning estimate, not an outbreak alert."
        >
          <ErrorNote message={forecast.error} onRetry={forecast.reload} />
          {!prediction && forecast.loading && <Loading />}
          {prediction?.predictions?.length ? (
            <>
              <p className="mb-4 text-sm text-ink2">
                {prediction.method === 'linear_regression'
                  ? `Linear regression trained on ${prediction.observed_weeks} weeks with validated counts.`
                  : `Historical average from ${prediction.observed_weeks} weeks with validated counts; more data is needed for regression.`}
              </p>
              <div className="grid grid-cols-2 gap-3 lg:grid-cols-4">
                {prediction.predictions.map((week) => (
                  <div key={week.week} className="rounded-xl border border-line bg-white p-4">
                    <p className="text-sm font-semibold text-ink2">
                      {new Intl.DateTimeFormat('en-PH', { month: 'short', day: 'numeric' }).format(
                        new Date(`${week.week}T00:00:00`),
                      )}
                    </p>
                    <p className="mt-1 text-xl font-bold text-brand-700">
                      {fmtNum(week.pests)} <span className="text-sm font-medium text-ink2">pests</span>
                    </p>
                  </div>
                ))}
              </div>
            </>
          ) : (
            prediction && <Empty title="Not enough validated pest counts">Forecasts appear once there is usable history.</Empty>
          )}
        </Panel>
      </div>
      <ErrorNote message={res.error} onRetry={res.reload} />
      {!d && res.loading && <Loading />}
      {d && !d.quarters.length && (
        <Panel>
          <Empty title="No validated observations yet">Patterns appear once observations are validated.</Empty>
        </Panel>
      )}
      {d && d.quarters.length > 0 && (
        <div className="space-y-6">
          <div className="grid grid-cols-2 gap-3 lg:grid-cols-4">
            <Stat label="Increasing" value={fmtNum(d.summary.increasing)} tone={d.summary.increasing ? 'red' : 'muted'} hint={`Up ${d.threshold_pct}% or more`} />
            <Stat label="Decreasing" value={fmtNum(d.summary.decreasing)} tone="green" hint={`Down ${d.threshold_pct}% or more`} />
            <Stat label="Stable" value={fmtNum(d.summary.stable)} tone="muted" hint={`Within ±${d.threshold_pct}%`} />
            <Stat label="Recurring" value={fmtNum(d.summary.recurring)} tone={d.summary.recurring ? 'orange' : 'muted'} hint={`Also seen in ${quarterLabel(d.last_year)}`} />
          </div>

          <Panel
            title={`${quarterLabel(d.quarter)} compared with ${quarterLabel(d.previous)}`}
            subtitle="Compared by pests counted when there are any; otherwise (disease reports, photos not countable) by number of validated observations."
            actions={
              <Segmented
                value={show}
                onChange={setShow}
                options={[
                  ['all', 'All'],
                  ['increasing', 'Increasing'],
                  ['decreasing', 'Decreasing'],
                  ['stable', 'Stable'],
                  ['recurring', 'Recurring'],
                ]}
              />
            }
            bodyClassName=""
          >
            <Table
              rowKey="key"
              rows={rows.map((r) => ({ ...r, key: `${r.area}|${r.pest}` }))}
              empty={<Empty title="Nothing in this group" />}
              columns={[
                { key: 'area', label: 'Municipality', className: 'font-medium' },
                { key: 'pest', label: 'Pest / report' },
                { key: 'basis', label: 'Compared by', render: (r) => <span className="text-xs text-ink2">{r.basis === 'pests' ? 'Pests counted' : 'Observations'}</span> },
                { key: 'current', label: quarterLabel(d.quarter), align: 'right', render: (r) => <span className="font-semibold">{value(r, 'current')}</span> },
                { key: 'previous', label: quarterLabel(d.previous), align: 'right', render: (r) => value(r, 'previous') },
                { key: 'last_year', label: quarterLabel(d.last_year), align: 'right', render: (r) => value(r, 'last_year') },
                {
                  key: 'change',
                  label: 'Change',
                  align: 'right',
                  render: (r) => (r.change_pct === null ? <span className="text-xs text-ink2">{r.previous[r.basis] ? '—' : 'New'}</span> : fmtPct(r.change_pct)),
                },
                {
                  key: 'status',
                  label: 'Pattern',
                  render: (r) => (
                    <span className="flex flex-wrap gap-1">
                      <PatternBadge status={r.status} />
                      {r.recurring && <Badge tone="orange">Recurring</Badge>}
                    </span>
                  ),
                },
              ]}
            />
          </Panel>

          <Panel
            title="Past quarters"
            subtitle="Up to the last 8 quarters of validated observations. Click a bar to open that quarter."
            actions={
              <Segmented
                value={metric}
                onChange={setMetric}
                options={[
                  ['records', 'Observations'],
                  ['pests', 'Pests counted'],
                ]}
              />
            }
          >
            <QuarterBars quarters={d.quarters} selected={d.quarter} onSelect={setQuarter} metric={metric} />
          </Panel>
        </div>
      )}
    </div>
  );
}
