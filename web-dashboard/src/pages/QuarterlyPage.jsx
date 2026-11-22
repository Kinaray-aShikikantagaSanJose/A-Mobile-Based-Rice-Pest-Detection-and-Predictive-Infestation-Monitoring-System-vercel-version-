import { useState } from 'react';
import { api } from '../api.js';
import { QuarterBars } from '../components/Charts.jsx';
import { Badge, Empty, ErrorNote, Loading, Panel, PageHeader, PatternBadge, Segmented, Select, Stat, Table } from '../components/ui.jsx';
import { useT } from '../i18n/index.jsx';
import { fmtNum, fmtPct, quarterLabel, useAsync } from '../lib.js';

export default function QuarterlyPage({ viewer }) {
  const t = useT();
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
        title={t('Quarterly patterns')}
        description={t(
          'Each municipality and pest compared with the previous quarter, and with the same quarter last year to spot recurring infestations. Validated observations only.',
        )}
        area={viewer.role === 'agriculturist' ? undefined : viewer.area_label}
        actions={
          d?.quarters.length ? (
            <Select
              value={d.quarter}
              onChange={setQuarter}
              options={[...d.quarters].reverse().map((q) => [q.quarter, quarterLabel(q.quarter)])}
              className="min-w-[140px]"
              aria-label={t('Quarter')}
            />
          ) : null
        }
      />
      <div className="mb-6">
        <Panel
          title={t('Four-week pest trend forecast')}
          subtitle={t('Scikit-learn projects validated pest counts for your authorized area. This is a planning estimate, not an outbreak alert.')}
        >
          <ErrorNote message={forecast.error} onRetry={forecast.reload} />
          {!prediction && forecast.loading && <Loading />}
          {prediction?.predictions?.length ? (
            <>
              <p className="mb-4 text-sm text-ink2">
                {prediction.method === 'linear_regression'
                  ? t('Linear regression trained on {n} weeks with validated counts.', { n: prediction.observed_weeks })
                  : t('Historical average from {n} weeks with validated counts; more data is needed for regression.', { n: prediction.observed_weeks })}
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
                      {fmtNum(week.pests)} <span className="text-sm font-medium text-ink2">{t('pests')}</span>
                    </p>
                  </div>
                ))}
              </div>
            </>
          ) : (
            prediction && <Empty title={t('Not enough validated pest counts')}>{t('Forecasts appear once there is usable history.')}</Empty>
          )}
        </Panel>
      </div>
      <ErrorNote message={res.error} onRetry={res.reload} />
      {!d && res.loading && <Loading />}
      {d && !d.quarters.length && (
        <Panel>
          <Empty title={t('No validated observations yet')}>{t('Patterns appear once observations are validated.')}</Empty>
        </Panel>
      )}
      {d && d.quarters.length > 0 && (
        <div className="space-y-6">
          <div className="grid grid-cols-2 gap-3 lg:grid-cols-4">
            <Stat
              label={t('Increasing')}
              value={fmtNum(d.summary.increasing)}
              tone={d.summary.increasing ? 'red' : 'muted'}
              hint={t('Up {pct}% or more', { pct: d.threshold_pct })}
            />
            <Stat label={t('Decreasing')} value={fmtNum(d.summary.decreasing)} tone="green" hint={t('Down {pct}% or more', { pct: d.threshold_pct })} />
            <Stat label={t('Stable')} value={fmtNum(d.summary.stable)} tone="muted" hint={t('Within ±{pct}%', { pct: d.threshold_pct })} />
            <Stat
              label={t('Recurring')}
              value={fmtNum(d.summary.recurring)}
              tone={d.summary.recurring ? 'orange' : 'muted'}
              hint={t('Also seen in {quarter}', { quarter: quarterLabel(d.last_year) })}
            />
          </div>

          <Panel
            title={t('{quarter} compared with {previous}', { quarter: quarterLabel(d.quarter), previous: quarterLabel(d.previous) })}
            subtitle={t('Compared by pests counted when there are any; otherwise (disease reports, photos not countable) by number of validated observations.')}
            actions={
              <Segmented
                value={show}
                onChange={setShow}
                options={[
                  ['all', t('All')],
                  ['increasing', t('Increasing')],
                  ['decreasing', t('Decreasing')],
                  ['stable', t('Stable')],
                  ['recurring', t('Recurring')],
                ]}
              />
            }
            bodyClassName=""
          >
            <Table
              rowKey="key"
              rows={rows.map((r) => ({ ...r, key: `${r.area}|${r.pest}` }))}
              empty={<Empty title={t('Nothing in this group')} />}
              columns={[
                { key: 'area', label: t('Municipality'), className: 'font-medium' },
                { key: 'pest', label: t('Pest / report') },
                {
                  key: 'basis',
                  label: t('Compared by'),
                  render: (r) => <span className="text-xs text-ink2">{r.basis === 'pests' ? t('Pests counted') : t('Observations')}</span>,
                },
                { key: 'current', label: quarterLabel(d.quarter), align: 'right', render: (r) => <span className="font-semibold">{value(r, 'current')}</span> },
                { key: 'previous', label: quarterLabel(d.previous), align: 'right', render: (r) => value(r, 'previous') },
                { key: 'last_year', label: quarterLabel(d.last_year), align: 'right', render: (r) => value(r, 'last_year') },
                {
                  key: 'change',
                  label: t('Change'),
                  align: 'right',
                  render: (r) => (r.change_pct === null ? <span className="text-xs text-ink2">{r.previous[r.basis] ? '—' : t('New')}</span> : fmtPct(r.change_pct)),
                },
                {
                  key: 'status',
                  label: t('Pattern'),
                  render: (r) => (
                    <span className="flex flex-wrap gap-1">
                      <PatternBadge status={r.status} />
                      {r.recurring && <Badge tone="orange">{t('Recurring')}</Badge>}
                    </span>
                  ),
                },
              ]}
            />
          </Panel>

          <Panel
            title={t('Past quarters')}
            subtitle={t('Up to the last 8 quarters of validated observations. Click a bar to open that quarter.')}
            actions={
              <Segmented
                value={metric}
                onChange={setMetric}
                options={[
                  ['records', t('Observations')],
                  ['pests', t('Pests counted')],
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
