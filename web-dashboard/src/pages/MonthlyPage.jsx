import { useState } from 'react';
import { api } from '../api.js';
import { Empty, ErrorNote, LevelBar, LEVEL_COLOR, Loading, Panel, PageHeader, Select, Stat, Table } from '../components/ui.jsx';
import { useT } from '../i18n/index.jsx';
import { fmtNum, LEVELS, monthLabel, useAsync } from '../lib.js';

function Breakdown({ title, rows, nameLabel }) {
  const t = useT();
  return (
    <Panel title={title} bodyClassName="">
      <Table
        rowKey="name"
        rows={rows}
        empty={<Empty title={t('No validated observations this month')} />}
        columns={[
          { key: 'name', label: nameLabel, className: 'font-medium', render: (g) => t(g.name) },
          { key: 'records', label: t('Validated'), align: 'right', render: (g) => fmtNum(g.records) },
          { key: 'pests', label: t('Pests counted'), align: 'right', render: (g) => fmtNum(g.pests) },
          {
            key: 'levels',
            label: t('Low / Medium / High'),
            headClassName: 'w-[38%]',
            render: (g) => (
              <div className="flex items-center gap-3">
                <LevelBar LOW={g.LOW} MEDIUM={g.MEDIUM} HIGH={g.HIGH} className="h-2.5 flex-1" />
                <span className="whitespace-nowrap text-xs tabular-nums text-ink2">
                  {g.LOW} / {g.MEDIUM} / {g.HIGH}
                </span>
              </div>
            ),
          },
        ]}
      />
    </Panel>
  );
}

export default function MonthlyPage({ viewer }) {
  const t = useT();
  const [month, setMonth] = useState('');
  const res = useAsync(() => api.monthly(month), [month]);
  const d = res.data;
  const levelTotal = d ? LEVELS.reduce((n, k) => n + d.by_level[k], 0) : 0;

  return (
    <div>
      <PageHeader
        title={t('Monthly monitoring summary')}
        description={t(
          'Validated observations for one month by municipality, pest and the infestation level reviewers confirmed. Pests counted leaves out photos marked not countable.',
        )}
        area={viewer.role === 'agriculturist' ? undefined : viewer.area_label}
        actions={
          d?.months.length ? (
            <Select
              value={d.month}
              onChange={setMonth}
              options={d.months.map((m) => [m.month, monthLabel(m.month)])}
              className="min-w-[200px]"
              aria-label={t('Month')}
            />
          ) : null
        }
      />
      <ErrorNote message={res.error} onRetry={res.reload} />
      {!d && res.loading && <Loading />}
      {d && !d.months.length && (
        <Panel>
          <Empty title={t('No observations yet')}>{t('Monthly summaries appear once observations arrive from the mobile app.')}</Empty>
        </Panel>
      )}
      {d && d.months.length > 0 && (
        <div className="space-y-6">
          <div className="grid grid-cols-2 gap-3 lg:grid-cols-4">
            <Stat label={t('Validated observations')} value={fmtNum(d.totals.validated)} tone="brand" />
            <Stat label={t('Pests counted')} value={fmtNum(d.totals.pests)} hint={t('Countable validated pest reports')} />
            <Stat label={t('Observations submitted')} value={fmtNum(d.totals.observations)} hint={t('Every status')} />
            <Stat
              label={t('HIGH infestations')}
              value={fmtNum(d.by_level.HIGH)}
              tone={d.by_level.HIGH ? 'red' : 'muted'}
              hint={levelTotal ? t('{pct}% of leveled pest reports', { pct: Math.round((d.by_level.HIGH / levelTotal) * 100) }) : undefined}
            />
          </div>

          <Panel
            title={t('Infestation levels')}
            subtitle={t('{month} · validated pest reports, level as confirmed by the reviewer', { month: monthLabel(d.month) })}
          >
            <LevelBar {...d.by_level} className="h-4" />
            <div className="mt-3 grid grid-cols-3 gap-3">
              {LEVELS.map((k) => (
                <div key={k} className="flex items-center gap-2 text-sm">
                  <span className="h-3 w-3 rounded-full" style={{ background: LEVEL_COLOR[k] }} />
                  <span className="font-semibold">{t(k)}</span>
                  <span className="tabular-nums text-ink2">
                    {fmtNum(d.by_level[k])}
                    {levelTotal ? ` · ${Math.round((d.by_level[k] / levelTotal) * 100)}%` : ''}
                  </span>
                </div>
              ))}
            </div>
          </Panel>

          <div className="grid gap-6 xl:grid-cols-2">
            <Breakdown title={t('By municipality')} nameLabel={t('Municipality')} rows={d.by_area} />
            <Breakdown title={t('By pest')} nameLabel={t('Pest / report')} rows={d.by_pest} />
            <Breakdown title={t('By land type')} nameLabel={t('Land type')} rows={d.by_land_type || []} />
          </div>

          <Panel title={t('All months')} subtitle={t('Click a month to open it')} bodyClassName="">
            <Table
              rowKey="month"
              rows={d.months.slice(0, 12)}
              onRowClick={(m) => setMonth(m.month)}
              columns={[
                {
                  key: 'month',
                  label: t('Month'),
                  render: (m) => <span className={m.month === d.month ? 'font-bold text-brand-700' : 'font-medium'}>{monthLabel(m.month)}</span>,
                },
                { key: 'observations', label: t('Observations'), align: 'right', render: (m) => fmtNum(m.observations) },
                { key: 'validated', label: t('Validated'), align: 'right', render: (m) => fmtNum(m.validated) },
                { key: 'pests', label: t('Pests counted'), align: 'right', render: (m) => fmtNum(m.pests) },
              ]}
            />
          </Panel>
        </div>
      )}
    </div>
  );
}
