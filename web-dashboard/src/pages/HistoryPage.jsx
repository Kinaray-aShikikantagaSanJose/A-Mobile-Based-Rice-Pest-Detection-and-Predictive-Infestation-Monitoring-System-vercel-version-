import { useState } from 'react';
import { api } from '../api.js';
import RecordDrawer from '../components/RecordDrawer.jsx';
import { Badge, Button, Empty, ErrorNote, Field, LevelBadge, Loading, Panel, PageHeader, ReportTypeBadge, Segmented, Stat, Table } from '../components/ui.jsx';
import { fmtCount, fmtDateTime, fmtNum, REVIEW_ACTIONS, useAsync } from '../lib.js';

const ACTION_TONE = { validated: 'green', returned: 'gray', escalated: 'purple', diagnosis: 'blue' };
const PAGE = 50;

/** A validation that changed the model result's pest or count. */
const corrected = (r) => r.action === 'validated' && r.report_type === 'pest' && r.ai_pest !== r.pest;

export default function HistoryPage({ viewer }) {
  const res = useAsync(() => api.myReviews(), []);
  const [show, setShow] = useState('all');
  const [search, setSearch] = useState('');
  const [shown, setShown] = useState(PAGE);
  const [openId, setOpenId] = useState(null);
  const all = res.data || [];
  const n = (action) => all.filter((r) => r.action === action).length;
  const s = search.trim().toLowerCase().replace(/^#/, '');
  const rows = all.filter(
    (r) =>
      (show === 'all' || (show === 'validated' ? ['validated', 'diagnosis'].includes(r.action) : r.action === show)) &&
      (!s || `${r.scan_id} ${r.farmer} ${r.barangay} ${r.municipality} ${r.pest || ''} ${r.ai_pest || ''} ${r.note}`.toLowerCase().includes(s)),
  );

  return (
    <div>
      <PageHeader
        title="My validation history"
        description="Every decision you made on an observation, newest first (up to 500). Open one to see the record as it is now."
        area={viewer.role === 'technician' ? viewer.area_label : undefined}
      />
      <ErrorNote message={res.error} onRetry={res.reload} />
      {res.data && (
        <div className="mb-6 grid grid-cols-2 gap-3 lg:grid-cols-4">
          <Stat label="Validated" value={fmtNum(n('validated') + n('diagnosis'))} tone="brand" hint={`${fmtNum(n('diagnosis'))} disease diagnoses`} />
          <Stat label="Model result pest corrected" value={fmtNum(all.filter(corrected).length)} hint="Pest differed from the model result" />
          <Stat label="Returned to farmer" value={fmtNum(n('returned'))} tone="muted" />
          <Stat label="Escalated" value={fmtNum(n('escalated'))} tone={n('escalated') ? 'orange' : 'muted'} />
        </div>
      )}
      <Panel
        bodyClassName=""
        title="Decisions"
        actions={
          <Segmented
            value={show}
            onChange={(v) => {
              setShown(PAGE);
              setShow(v);
            }}
            options={[
              ['all', 'All'],
              ['validated', 'Validated'],
              ['returned', 'Returned'],
              ['escalated', 'Escalated'],
            ]}
          />
        }
      >
        <div className="border-b border-line p-5">
          <Field label="Search" className="max-w-md">
            <input className="input" value={search} onChange={(e) => setSearch(e.target.value)} placeholder="Observation #, farmer, barangay, pest, note…" />
          </Field>
        </div>
        {!res.data && res.loading ? (
          <Loading />
        ) : (
          <Table
            rows={rows.slice(0, shown)}
            onRowClick={(r) => setOpenId(r.scan_id)}
            empty={<Empty title={all.length ? 'Nothing matches' : 'No decisions yet'}>{all.length ? 'Try another filter.' : 'Observations you review from the queue appear here.'}</Empty>}
            columns={[
              {
                key: 'when',
                label: 'When',
                render: (r) => (
                  <div>
                    <div className="whitespace-nowrap font-medium">{fmtDateTime(r.created_at)}</div>
                    <div className="text-xs text-ink2">Observation #{r.scan_id}</div>
                  </div>
                ),
              },
              {
                key: 'farmer',
                label: 'Farmer · area',
                render: (r) => (
                  <div className="max-w-[200px]">
                    <div className="truncate font-medium text-ink">{r.farmer}</div>
                    <div className="truncate text-xs text-ink2">{[r.barangay, r.municipality].filter(Boolean).join(', ')}</div>
                  </div>
                ),
              },
              {
                key: 'action',
                label: 'Decision',
                render: (r) => (
                  <span className="flex flex-wrap items-center gap-1">
                    <Badge tone={ACTION_TONE[r.action]}>{REVIEW_ACTIONS[r.action] || r.action}</Badge>
                    <ReportTypeBadge type={r.report_type} />
                  </span>
                ),
              },
              {
                key: 'result',
                label: 'Model result → you set',
                render: (r) =>
                  r.action === 'validated' && r.report_type === 'pest' ? (
                    <div className="text-sm">
                      <span className="text-ink2">{r.ai_pest || 'nothing'}</span> → <b className={corrected(r) ? 'text-orange-700' : 'text-ink'}>{r.pest}</b>
                      <div className="text-xs text-ink2">{fmtCount(r.count)}</div>
                    </div>
                  ) : (
                    <span className="text-muted">—</span>
                  ),
              },
              { key: 'level', label: 'Level', render: (r) => <LevelBadge level={r.level} /> },
              { key: 'note', label: 'Note / reason', render: (r) => <span className="line-clamp-2 max-w-[280px] text-ink2">{r.note || '—'}</span> },
            ]}
          />
        )}
        {rows.length > shown && (
          <div className="border-t border-line p-4 text-center">
            <Button variant="secondary" onClick={() => setShown((x) => x + PAGE)}>
              Show {Math.min(PAGE, rows.length - shown)} more
            </Button>
          </div>
        )}
      </Panel>
      {openId && <RecordDrawer scanId={openId} viewer={viewer} onClose={() => setOpenId(null)} onChanged={res.reload} />}
    </div>
  );
}
