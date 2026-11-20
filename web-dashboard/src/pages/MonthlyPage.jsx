import { useState } from 'react';
import { api } from '../api.js';
import { Empty, ErrorNote, LevelBar, LEVEL_COLOR, Loading, Panel, PageHeader, Select, Stat, Table } from '../components/ui.jsx';
import { fmtNum, LEVELS, monthLabel, useAsync } from '../lib.js';

function Breakdown({ title, rows, nameLabel }) {
  return (
    <Panel title={title} bodyClassName="">
      <Table
        rowKey="name"
        rows={rows}
        empty={<Empty title="No validated observations this month" />}
        columns={[
          { key: 'name', label: nameLabel, className: 'font-medium' },
          { key: 'records', label: 'Validated', align: 'right', render: (g) => fmtNum(g.records) },
          { key: 'pests', label: 'Pests counted', align: 'right', render: (g) => fmtNum(g.pests) },
          {
            key: 'levels',
            label: 'Low / Medium / High',
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
  const [month, setMonth] = useState('');
  const res = useAsync(() => api.monthly(month), [month]);
  const d = res.data;
  const levelTotal = d ? LEVELS.reduce((n, k) => n + d.by_level[k], 0) : 0;

  return (
    <div>
      <PageHeader
        title="Monthly monitoring summary"
        description="Validated observations for one month by municipality, pest and the infestation level reviewers confirmed. Pests counted leaves out photos marked not countable."
        area={viewer.role === 'agriculturist' ? undefined : viewer.area_label}
        actions={
          d?.months.length ? (
            <Select
              value={d.month}
              onChange={setMonth}
              options={d.months.map((m) => [m.month, monthLabel(m.month)])}
              className="min-w-[200px]"
              aria-label="Month"
            />
          ) : null
        }
      />
      <ErrorNote message={res.error} onRetry={res.reload} />
      {!d && res.loading && <Loading />}
      {d && !d.months.length && (
        <Panel>
          <Empty title="No observations yet">Monthly summaries appear once observations arrive from the mobile app.</Empty>
        </Panel>
      )}
      {d && d.months.length > 0 && (
        <div className="space-y-6">
          <div className="grid grid-cols-2 gap-3 lg:grid-cols-4">
            <Stat label="Validated observations" value={fmtNum(d.totals.validated)} tone="brand" />
            <Stat label="Pests counted" value={fmtNum(d.totals.pests)} hint="Countable validated pest reports" />
            <Stat label="Observations submitted" value={fmtNum(d.totals.observations)} hint="Every status" />
            <Stat
              label="HIGH infestations"
              value={fmtNum(d.by_level.HIGH)}
              tone={d.by_level.HIGH ? 'red' : 'muted'}
              hint={levelTotal ? `${Math.round((d.by_level.HIGH / levelTotal) * 100)}% of leveled pest reports` : undefined}
            />
          </div>

          <Panel title="Infestation levels" subtitle={`${monthLabel(d.month)} · validated pest reports, level as confirmed by the reviewer`}>
            <LevelBar {...d.by_level} className="h-4" />
            <div className="mt-3 grid grid-cols-3 gap-3">
              {LEVELS.map((k) => (
                <div key={k} className="flex items-center gap-2 text-sm">
                  <span className="h-3 w-3 rounded-full" style={{ background: LEVEL_COLOR[k] }} />
                  <span className="font-semibold">{k}</span>
                  <span className="tabular-nums text-ink2">
                    {fmtNum(d.by_level[k])}
                    {levelTotal ? ` · ${Math.round((d.by_level[k] / levelTotal) * 100)}%` : ''}
                  </span>
                </div>
              ))}
            </div>
          </Panel>

          <div className="grid gap-6 xl:grid-cols-2">
            <Breakdown title="By municipality" nameLabel="Municipality" rows={d.by_area} />
            <Breakdown title="By pest" nameLabel="Pest / report" rows={d.by_pest} />
            <Breakdown title="By land type" nameLabel="Land type" rows={d.by_land_type || []} />
          </div>

          <Panel title="All months" subtitle="Click a month to open it" bodyClassName="">
            <Table
              rowKey="month"
              rows={d.months.slice(0, 12)}
              onRowClick={(m) => setMonth(m.month)}
              columns={[
                {
                  key: 'month',
                  label: 'Month',
                  render: (m) => <span className={m.month === d.month ? 'font-bold text-brand-700' : 'font-medium'}>{monthLabel(m.month)}</span>,
                },
                { key: 'observations', label: 'Observations', align: 'right', render: (m) => fmtNum(m.observations) },
                { key: 'validated', label: 'Validated', align: 'right', render: (m) => fmtNum(m.validated) },
                { key: 'pests', label: 'Pests counted', align: 'right', render: (m) => fmtNum(m.pests) },
              ]}
            />
          </Panel>
        </div>
      )}
    </div>
  );
}
