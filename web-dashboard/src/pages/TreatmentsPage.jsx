import { useState } from 'react';
import { api } from '../api.js';
import RecordDrawer from '../components/RecordDrawer.jsx';
import { Badge, Button, Empty, ErrorNote, LevelBadge, Loading, OutcomeBadge, Pager, Panel, PageHeader, Segmented, Stat, Table } from '../components/ui.jsx';
import { useT } from '../i18n/index.jsx';
import { daysSince, fmtDate, fmtNum, useAction, useAsync } from '../lib.js';

// Outcomes are only classified when both observations were reviewed and show
// the same pest; anything else stays pending or "not comparable".
const OUTCOME_FILTERS = [
  ['all', 'All'],
  ['improved', 'Improved'],
  ['no change', 'No change'],
  ['worsened', 'Worsened'],
  ['not comparable', 'Not comparable'],
  ['pending', 'Pending'],
  ['overdue', 'Overdue'],
];
const PAGE = 50;

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

/** Before → after: date, level and count of the treated observation vs. its follow-up. */
function BeforeAfter({ i }) {
  const t = useT();
  const count = (n) => (n === null || n === undefined ? t('n/c') : fmtNum(n));
  return (
    <div className="flex items-start gap-2 whitespace-nowrap text-sm">
      <span>
        <span className="flex items-center gap-1">
          <LevelBadge level={i.before_level} />
          <span className="text-xs text-ink2">{count(i.before_count)}</span>
        </span>
        <span className="block text-[11px] text-muted">{fmtDate(i.before_at)}</span>
      </span>
      <span className="text-muted">→</span>
      {i.after_level || i.after_count != null ? (
        <span>
          <span className="flex items-center gap-1">
            <LevelBadge level={i.after_level} />
            <span className="text-xs text-ink2">{count(i.after_count)}</span>
          </span>
          <span className="block text-[11px] text-muted">{fmtDate(i.follow_up_at)}</span>
        </span>
      ) : i.follow_up_scan_id ? (
        <span className="text-xs text-muted">
          {i.follow_up_status === 'no_pests' ? t('no pests detected, not reviewed') : t('follow-up not reviewed yet')}
        </span>
      ) : (
        <span className="text-xs text-muted">{t('no follow-up yet')}</span>
      )}
    </div>
  );
}

function OutcomeSplit({ g }) {
  const t = useT();
  const parts = [
    ['improved', g.improved, 'bg-emerald-500'],
    ['no change', g.no_change, 'bg-gray-300'],
    ['worsened', g.worsened ?? g.worse, 'bg-red-500'],
  ];
  if (!g.compared) return <span className="text-xs text-muted">{t('No follow-ups compared yet')}</span>;
  return (
    <div className="flex items-center gap-3">
      <div
        className="flex h-2.5 w-32 overflow-hidden rounded-full bg-gray-100"
        title={t('{improved} improved · {same} no change · {worse} worsened', { improved: g.improved, same: g.no_change, worse: g.worsened ?? g.worse })}
      >
        {parts.map(([k, v, cls]) => (v ? <div key={k} className={cls} style={{ width: `${(v / g.compared) * 100}%` }} /> : null))}
      </div>
      <span className="whitespace-nowrap text-xs tabular-nums text-ink2">
        {g.improved} / {g.no_change} / {g.worsened ?? g.worse}
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
  const t = useT();
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
              aria-label={t('Feedback date')}
            />
            <Button size="sm" busy={action.busy} disabled={!date} onClick={() => save({ follow_up_due: date })}>
              {t('Save')}
            </Button>
            <Button size="sm" variant="ghost" onClick={() => setEditing(false)}>
              {t('Cancel')}
            </Button>
          </div>
        ) : (
          <>
            <div className="whitespace-nowrap text-xs text-ink2">
              {t('Due {date}', { date: fmtDate(i.follow_up_due) })} · {i.follow_up_set_by ? t('set by staff') : t('automatic')}
            </div>
            <div className="mt-0.5 flex gap-3">
              <button type="button" className={linkBtn} onClick={() => setEditing(true)}>
                {t('Change date')}
              </button>
              {i.follow_up_set_by && (
                <button type="button" className={linkBtn} disabled={action.busy} onClick={() => save({ reset_follow_up: true })}>
                  {t('Use automatic date')}
                </button>
              )}
            </div>
          </>
        )}
        {action.error && <div className="mt-1 text-xs text-red-600">{action.error}</div>}
      </div>
    );
  }
  if (!i.library_id) return <div className="mt-0.5 text-xs text-muted">{t("Farmer's own method")}</div>;
  return (
    <div onClick={stop} className="mt-0.5">
      <div className="text-xs text-ink2">
        {i.recommend_again ? t('Recommended to the farmer again') : t('Not recommended again (farmer reported back)')}
      </div>
      <button type="button" className={linkBtn} disabled={action.busy} onClick={() => save({ recommend_again: !i.recommend_again })}>
        {i.recommend_again ? t('Stop recommending it') : t('Recommend it again')}
      </button>
      {action.error && <div className="mt-1 text-xs text-red-600">{action.error}</div>}
    </div>
  );
}

function OverduePanel({ items, onOpen, prominent }) {
  const t = useT();
  return (
    <Panel
      className={prominent ? 'border-orange-300 ring-1 ring-orange-200' : ''}
      title={t('Follow-ups overdue ({n})', { n: items.length })}
      subtitle={t("The farmer hasn't sent the follow-up photo that was due after the treatment. Call to remind them.")}
      bodyClassName=""
    >
      <Table
        rows={items}
        onRowClick={(i) => onOpen(i.scan_id)}
        empty={<Empty title={t('No overdue follow-ups')}>{t("Every farmer who logged a treatment has sent a follow-up or isn't due yet.")}</Empty>}
        columns={[
          {
            key: 'farmer',
            label: t('Farmer'),
            render: (i) => (
              <div className="max-w-[220px]">
                <div className="truncate font-medium text-ink">{i.farmer_name}</div>
                <div className="truncate text-xs text-ink2">{[i.barangay, i.municipality].filter(Boolean).join(', ')}</div>
              </div>
            ),
          },
          {
            key: 'phone',
            label: t('Phone'),
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
            label: t('Treatment'),
            render: (i) => (
              <div className="max-w-[240px]">
                <div className="line-clamp-2">{i.treatment}</div>
                <div className="text-xs text-ink2">
                  {i.pest} · {t('applied {date}', { date: fmtDate(i.applied_at) })}
                </div>
              </div>
            ),
          },
          {
            key: 'due',
            label: t('Due'),
            render: (i) => {
              const late = daysSince(i.follow_up_due);
              return (
                <div className="whitespace-nowrap">
                  <div className="font-medium">{fmtDate(i.follow_up_due)}</div>
                  {late !== null && (
                    <Badge tone={late >= 7 ? 'red' : 'orange'}>{late === 1 ? t('{n} day late', { n: late }) : t('{n} days late', { n: late })}</Badge>
                  )}
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
  const t = useT();
  const isAgri = viewer.role === 'agriculturist';
  const [show, setShow] = useState('all');
  const [offset, setOffset] = useState(0);
  const [openId, setOpenId] = useState(null);
  // Paged on the server; the summary and overdue list always cover everything.
  const res = useAsync(
    () => api.treatments({ outcome: show === 'all' ? '' : show, limit: PAGE, offset }),
    [show, offset],
  );
  const d = res.data;
  const shownItems = d?.items || [];
  const sum = (key) => (d?.summary || []).reduce((n, g) => n + (g[key] || 0), 0);
  const logged = sum('applications');
  const compared = sum('compared');
  const improved = sum('improved');

  const summary = d && (
    <Panel
      title={t('By treatment')}
      subtitle={t('Applications with the same name are grouped. Improved / no change / worsened counts only treatments whose follow-up was reviewed and shows the same pest. A follow-up photo with no pests detected is not counted as improved until a technician reviews it.')}
      bodyClassName=""
    >
      <Table
        rowKey="treatment"
        rows={d.summary}
        empty={<Empty title={t('No treatments logged yet')}>{t('Farmers log treatments in the app once an observation is validated.')}</Empty>}
        columns={[
          { key: 'treatment', label: t('Treatment'), className: 'font-medium' },
          { key: 'option_type', label: t('Type'), render: (g) => <Badge tone="gray">{t(g.option_type)}</Badge> },
          { key: 'applications', label: t('Applications'), align: 'right', render: (g) => fmtNum(g.applications) },
          { key: 'compared', label: t('Compared'), align: 'right', render: (g) => fmtNum(g.compared) },
          { key: 'split', label: t('Improved / no change / worsened'), render: (g) => <OutcomeSplit g={g} /> },
          { key: 'not_comparable', label: t('Not comparable'), align: 'right', render: (g) => fmtNum(g.not_comparable || 0) },
        ]}
      />
    </Panel>
  );

  return (
    <div>
      <PageHeader
        title={isAgri ? t('Treatment effectiveness') : t('Treatments & follow-ups')}
        description={
          isAgri
            ? t(
                'Each intervention a farmer logged, paired with the follow-up observation linked to it. The outcome compares the reviewer-confirmed level (and count, when both were countable) before and after.',
              )
            : t(
                'Treatments farmers in your area logged, and whether their follow-up photos came in. A follow-up is due a week after the treatment unless you set another date.',
              )
        }
        area={isAgri ? undefined : viewer.area_label}
      />
      <ErrorNote message={res.error} onRetry={res.reload} />
      {!d && res.loading && <Loading />}
      {d && (
        <div className="space-y-6">
          {!isAgri && <OverduePanel items={d.overdue} onOpen={setOpenId} prominent />}

          <div className="grid grid-cols-2 gap-3 lg:grid-cols-4">
            <Stat label={t('Treatments logged')} value={fmtNum(logged)} />
            <Stat
              label={t('Follow-ups compared')}
              value={fmtNum(compared)}
              hint={t('{n} still pending', { n: fmtNum(sum('pending')) })}
            />
            <Stat
              label={t('Improved')}
              value={fmtNum(improved)}
              tone="green"
              hint={compared ? t('{pct}% of compared', { pct: Math.round((improved / compared) * 100) }) : undefined}
            />
            <Stat label={t('Follow-ups overdue')} value={fmtNum(d.overdue.length)} tone={d.overdue.length ? 'orange' : 'muted'} />
          </div>

          {isAgri && summary}

          <Panel
            title={t('Interventions and follow-ups')}
            subtitle={t('Click a row to open the treated observation.')}
            actions={
              <Segmented
                value={show}
                onChange={(v) => {
                  setOffset(0);
                  setShow(v);
                }}
                options={OUTCOME_FILTERS.map(([v, label]) => [v, t(label)])}
              />
            }
            bodyClassName=""
          >
            <Table
              rows={shownItems}
              onRowClick={(i) => setOpenId(i.scan_id)}
              empty={<Empty title={t('Nothing in this group')} />}
              columns={[
                {
                  key: 'applied',
                  label: t('Applied'),
                  render: (i) => (
                    <div>
                      <div className="whitespace-nowrap font-medium">{fmtDate(i.applied_at)}</div>
                      <div className="text-xs text-ink2">{t('Observation #{id}', { id: i.scan_id })}</div>
                    </div>
                  ),
                },
                {
                  key: 'farmer',
                  label: t('Farmer · area'),
                  render: (i) => (
                    <div className="max-w-[200px]">
                      <div className="truncate font-medium text-ink">{i.farmer_name}</div>
                      <div className="truncate text-xs text-ink2">{[i.barangay, i.municipality].filter(Boolean).join(', ')}</div>
                    </div>
                  ),
                },
                {
                  key: 'treatment',
                  label: t('Treatment'),
                  render: (i) => (
                    <div className="max-w-[240px]">
                      <div className="line-clamp-2">{i.treatment}</div>
                      {i.was_recommended && <Badge tone="green">{t('Recommended by the reviewer')}</Badge>}
                      <div className="text-xs text-ink2">
                        {t(i.pest)}
                        {i.crop_stage && ` · ${t(i.crop_stage)}`} · {t(i.option_type)}
                      </div>
                    </div>
                  ),
                },
                { key: 'ba', label: t('Before → after'), render: (i) => <BeforeAfter i={i} /> },
                { key: 'change', label: t('Count change'), align: 'right', render: (i) => <Change pct={i.reduction_pct} /> },
                {
                  key: 'follow',
                  label: t('Follow-up'),
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
                {
                  key: 'outcome',
                  label: t('Outcome'),
                  render: (i) => (
                    <div>
                      <OutcomeBadge outcome={i.outcome} />
                      {i.outcome_basis && <div className="mt-0.5 max-w-[180px] text-[11px] text-muted">{t(i.outcome_basis)}</div>}
                    </div>
                  ),
                },
              ]}
            />
            <Pager total={d.total ?? shownItems.length} limit={PAGE} offset={offset} onChange={setOffset} loading={res.loading} />
          </Panel>

          {isAgri ? <OverduePanel items={d.overdue} onOpen={setOpenId} /> : summary}
        </div>
      )}
      {openId && <RecordDrawer scanId={openId} viewer={viewer} onClose={() => setOpenId(null)} onChanged={res.reload} />}
    </div>
  );
}
