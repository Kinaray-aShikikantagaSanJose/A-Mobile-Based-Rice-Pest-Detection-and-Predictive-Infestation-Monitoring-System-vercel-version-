import { useState } from 'react';
import { api } from '../api.js';
import RecordDrawer from '../components/RecordDrawer.jsx';
import { Badge, Button, Empty, ErrorNote, LevelBadge, Loading, OutcomeBadge, Panel, PageHeader, Segmented, Stat, Table } from '../components/ui.jsx';
import { daysSince, fmtDate, fmtNum, useAction, useAsync } from '../lib.js';

const OUTCOME_FILTERS = [
  ['all', 'All'],
  ['improved', 'Improved'],
  ['no change', 'No change'],
  ['worse', 'Worse'],
  ['awaiting follow-up', 'Awaiting'],
  ['overdue', 'Overdue'],
  ['follow-up in review', 'In review'],
];

function Change({ pct }) {
  if (pct === null || pct === undefined) return <span className="text-muted">—</span>;
  const fewer = pct > 0;
  return (
    <span className={`font-semibold tabular-nums ${fewer ? 'text-emerald-700' : pct < 0 ? 'text-red-600' : 'text-ink2'}`}>
      {fewer ? '−' : pct < 0 ? '+' : ''}
      {fmtNum(Math.abs(pct), 1)}%
    </span>
  );
}

/** Before → after: level and count of the treated observation vs. its follow-up. */
function BeforeAfter({ i }) {
  const count = (n) => (n === null || n === undefined ? 'n/c' : fmtNum(n));
  return (
    <div className="flex items-center gap-2 whitespace-nowrap text-sm">
      <span className="flex items-center gap-1">
        <LevelBadge level={i.before_level} />
        <span className="text-xs text-ink2">{count(i.before_count)}</span>
      </span>
      <span className="text-muted">→</span>
      {i.after_level || i.after_count != null ? (
        <span className="flex items-center gap-1">
          <LevelBadge level={i.after_level} />
          <span className="text-xs text-ink2">{count(i.after_count)}</span>
        </span>
      ) : (
        <span className="text-xs text-muted">no follow-up yet</span>
      )}
    </div>
  );
}

function OutcomeSplit({ g }) {
  const parts = [
    ['improved', g.improved, 'bg-emerald-500'],
    ['no change', g.no_change, 'bg-gray-300'],
    ['worse', g.worse, 'bg-red-500'],
  ];
  if (!g.compared) return <span className="text-xs text-muted">No follow-ups compared yet</span>;
  return (
    <div className="flex items-center gap-3">
      <div className="flex h-2.5 w-32 overflow-hidden rounded-full bg-gray-100" title={`${g.improved} improved · ${g.no_change} no change · ${g.worse} worse`}>
        {parts.map(([k, v, cls]) => (v ? <div key={k} className={cls} style={{ width: `${(v / g.compared) * 100}%` }} /> : null))}
      </div>
      <span className="whitespace-nowrap text-xs tabular-nums text-ink2">
        {g.improved} / {g.no_change} / {g.worse}
      </span>
    </div>
  );
}

const linkBtn = 'text-xs font-semibold text-brand-700 hover:text-brand-900 disabled:text-muted';

/**
 * Staff control over the treatment feedback (the follow-up photo):
 * before it arrives, when the farmer is asked for it; after it arrives,
 * whether this library option may be recommended to the farmer again.
 */
function FeedbackControls({ i, onSaved }) {
  const action = useAction();
  const [editing, setEditing] = useState(false);
  const [date, setDate] = useState(i.follow_up_due || '');
  const save = (body) =>
    action.run(async () => {
      await api.updateTreatment(i.id, body);
      setEditing(false);
      onSaved();
    });
  const stop = (e) => e.stopPropagation();

  if (!i.follow_up_scan_id) {
    return (
      <div onClick={stop} className="min-w-[180px]">
        {editing ? (
          <div className="flex flex-wrap items-center gap-1.5">
            <input
              type="date"
              className="input h-8 w-[150px] py-1 text-xs"
              min={(i.applied_at || '').slice(0, 10)}
              value={date}
              onChange={(e) => setDate(e.target.value)}
              aria-label="Feedback date"
            />
            <Button size="sm" busy={action.busy} disabled={!date} onClick={() => save({ follow_up_due: date })}>
              Save
            </Button>
            <Button size="sm" variant="ghost" onClick={() => setEditing(false)}>
              Cancel
            </Button>
          </div>
        ) : (
          <>
            <div className="whitespace-nowrap text-xs text-ink2">
              Due {fmtDate(i.follow_up_due)} · {i.follow_up_set_by ? 'set by staff' : 'automatic'}
            </div>
            <div className="mt-0.5 flex gap-3">
              <button type="button" className={linkBtn} onClick={() => setEditing(true)}>
                Change date
              </button>
              {i.follow_up_set_by && (
                <button type="button" className={linkBtn} disabled={action.busy} onClick={() => save({ reset_follow_up: true })}>
                  Use automatic date
                </button>
              )}
            </div>
          </>
        )}
        {action.error && <div className="mt-1 text-xs text-red-600">{action.error}</div>}
      </div>
    );
  }
  if (!i.library_id) return <div className="mt-0.5 text-xs text-muted">Farmer's own method</div>;
  return (
    <div onClick={stop} className="mt-0.5">
      <div className="text-xs text-ink2">{i.recommend_again ? 'Recommended to the farmer again' : 'Not recommended again (farmer reported back)'}</div>
      <button type="button" className={linkBtn} disabled={action.busy} onClick={() => save({ recommend_again: !i.recommend_again })}>
        {i.recommend_again ? 'Stop recommending it' : 'Recommend it again'}
      </button>
      {action.error && <div className="mt-1 text-xs text-red-600">{action.error}</div>}
    </div>
  );
}

function OverduePanel({ items, onOpen, prominent }) {
  return (
    <Panel
      className={prominent ? 'border-orange-300 ring-1 ring-orange-200' : ''}
      title={`Follow-ups overdue (${items.length})`}
      subtitle="The farmer hasn't sent the follow-up photo that was due after the treatment. Call to remind them."
      bodyClassName=""
    >
      <Table
        rows={items}
        onRowClick={(i) => onOpen(i.scan_id)}
        empty={<Empty title="No overdue follow-ups">Every farmer who logged a treatment has sent a follow-up or isn't due yet.</Empty>}
        columns={[
          {
            key: 'farmer',
            label: 'Farmer',
            render: (i) => (
              <div className="max-w-[220px]">
                <div className="truncate font-medium text-ink">{i.farmer_name}</div>
                <div className="truncate text-xs text-ink2">{[i.barangay, i.municipality].filter(Boolean).join(', ')}</div>
              </div>
            ),
          },
          {
            key: 'phone',
            label: 'Phone',
            render: (i) =>
              i.farmer_phone ? (
                <a href={`tel:${i.farmer_phone}`} onClick={(e) => e.stopPropagation()} className="whitespace-nowrap font-semibold text-brand-700 hover:text-brand-900">
                  {i.farmer_phone}
                </a>
              ) : (
                <span className="text-muted">—</span>
              ),
          },
          {
            key: 'treatment',
            label: 'Treatment',
            render: (i) => (
              <div className="max-w-[240px]">
                <div className="line-clamp-2">{i.treatment}</div>
                <div className="text-xs text-ink2">
                  {i.pest} · applied {fmtDate(i.applied_at)}
                </div>
              </div>
            ),
          },
          {
            key: 'due',
            label: 'Due',
            render: (i) => {
              const late = daysSince(i.follow_up_due);
              return (
                <div className="whitespace-nowrap">
                  <div className="font-medium">{fmtDate(i.follow_up_due)}</div>
                  {late !== null && <Badge tone={late >= 7 ? 'red' : 'orange'}>{late} day{late === 1 ? '' : 's'} late</Badge>}
                </div>
              );
            },
          },
        ]}
      />
    </Panel>
  );
}

/** Technicians: treatments & follow-ups from their farmers. Agriculturists: treatment effectiveness. */
export default function TreatmentsPage({ viewer }) {
  const isAgri = viewer.role === 'agriculturist';
  const res = useAsync(() => api.treatments(), []);
  const [show, setShow] = useState('all');
  const [openId, setOpenId] = useState(null);
  const d = res.data;
  const items = d?.items || [];
  const shownItems = show === 'all' ? items : items.filter((i) => i.outcome === show);
  const count = (o) => items.filter((i) => i.outcome === o).length;
  const compared = count('improved') + count('no change') + count('worse');

  const summary = d && (
    <Panel title="By treatment" subtitle="Applications with the same name are grouped. Improved / no change / worse counts only treatments whose follow-up was validated." bodyClassName="">
      <Table
        rowKey="treatment"
        rows={d.summary}
        empty={<Empty title="No treatments logged yet">Farmers log treatments in the app once an observation is validated.</Empty>}
        columns={[
          { key: 'treatment', label: 'Treatment', className: 'font-medium' },
          { key: 'option_type', label: 'Type', render: (g) => <Badge tone="gray">{g.option_type}</Badge> },
          { key: 'applications', label: 'Applications', align: 'right', render: (g) => fmtNum(g.applications) },
          { key: 'compared', label: 'Compared', align: 'right', render: (g) => fmtNum(g.compared) },
          { key: 'split', label: 'Improved / no change / worse', render: (g) => <OutcomeSplit g={g} /> },
        ]}
      />
    </Panel>
  );

  return (
    <div>
      <PageHeader
        title={isAgri ? 'Treatment effectiveness' : 'Treatments & follow-ups'}
        description={
          isAgri
            ? 'Each intervention a farmer logged, paired with the follow-up observation linked to it. The outcome compares the reviewer-confirmed level (and count, when both were countable) before and after.'
            : 'Treatments farmers in your area logged, and whether their follow-up photos came in. A follow-up is due a week after the treatment unless you set another date.'
        }
        area={isAgri ? undefined : viewer.area_label}
      />
      <ErrorNote message={res.error} onRetry={res.reload} />
      {!d && res.loading && <Loading />}
      {d && (
        <div className="space-y-6">
          {!isAgri && <OverduePanel items={d.overdue} onOpen={setOpenId} prominent />}

          <div className="grid grid-cols-2 gap-3 lg:grid-cols-4">
            <Stat label="Treatments logged" value={fmtNum(items.length)} />
            <Stat label="Follow-ups compared" value={fmtNum(compared)} hint={`${fmtNum(count('awaiting follow-up') + count('follow-up in review'))} awaiting or in review`} />
            <Stat label="Improved" value={fmtNum(count('improved'))} tone="green" hint={compared ? `${Math.round((count('improved') / compared) * 100)}% of compared` : undefined} />
            <Stat label="Follow-ups overdue" value={fmtNum(d.overdue.length)} tone={d.overdue.length ? 'orange' : 'muted'} />
          </div>

          {isAgri && summary}

          <Panel
            title="Interventions and follow-ups"
            subtitle="Click a row to open the treated observation."
            actions={<Segmented value={show} onChange={setShow} options={OUTCOME_FILTERS} />}
            bodyClassName=""
          >
            <Table
              rows={shownItems}
              onRowClick={(i) => setOpenId(i.scan_id)}
              empty={<Empty title="Nothing in this group" />}
              columns={[
                {
                  key: 'applied',
                  label: 'Applied',
                  render: (i) => (
                    <div>
                      <div className="whitespace-nowrap font-medium">{fmtDate(i.applied_at)}</div>
                      <div className="text-xs text-ink2">Observation #{i.scan_id}</div>
                    </div>
                  ),
                },
                {
                  key: 'farmer',
                  label: 'Farmer · area',
                  render: (i) => (
                    <div className="max-w-[200px]">
                      <div className="truncate font-medium text-ink">{i.farmer_name}</div>
                      <div className="truncate text-xs text-ink2">{[i.barangay, i.municipality].filter(Boolean).join(', ')}</div>
                    </div>
                  ),
                },
                {
                  key: 'treatment',
                  label: 'Treatment',
                  render: (i) => (
                    <div className="max-w-[240px]">
                      <div className="line-clamp-2">{i.treatment}</div>
                      <div className="text-xs text-ink2">
                        {i.pest}
                        {i.crop_stage && ` · ${i.crop_stage}`} · {i.option_type}
                      </div>
                    </div>
                  ),
                },
                { key: 'ba', label: 'Before → after', render: (i) => <BeforeAfter i={i} /> },
                { key: 'change', label: 'Count change', align: 'right', render: (i) => <Change pct={i.reduction_pct} /> },
                {
                  key: 'follow',
                  label: 'Follow-up',
                  render: (i) =>
                    i.follow_up_scan_id ? (
                      <div>
                        <button
                          type="button"
                          className="whitespace-nowrap text-sm font-semibold text-brand-700 hover:text-brand-900"
                          onClick={(e) => {
                            e.stopPropagation();
                            setOpenId(i.follow_up_scan_id);
                          }}
                        >
                          #{i.follow_up_scan_id} · {fmtDate(i.follow_up_at)}
                        </button>
                        <FeedbackControls i={i} onSaved={res.reload} />
                      </div>
                    ) : (
                      <FeedbackControls i={i} onSaved={res.reload} />
                    ),
                },
                { key: 'outcome', label: 'Outcome', render: (i) => <OutcomeBadge outcome={i.outcome} /> },
              ]}
            />
          </Panel>

          {isAgri ? <OverduePanel items={d.overdue} onOpen={setOpenId} /> : summary}
        </div>
      )}
      {openId && <RecordDrawer scanId={openId} viewer={viewer} onClose={() => setOpenId(null)} onChanged={res.reload} />}
    </div>
  );
}
