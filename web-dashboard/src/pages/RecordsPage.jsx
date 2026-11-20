import { useState } from 'react';
import { api } from '../api.js';
import AuthImage from '../components/AuthImage.jsx';
import RecordDrawer from '../components/RecordDrawer.jsx';
import { Badge, Button, Empty, ErrorNote, Field, LevelBadge, Loading, Panel, PageHeader, Select, STATUS_OPTIONS, StatusBadge, Table } from '../components/ui.jsx';
import { CROP_STAGES, fmtCount, fmtDate, LAND_TYPES, landTypeLabel, LEVELS, useAsync, useDebounced } from '../lib.js';

const STATUSES = [...STATUS_OPTIONS, ['all', 'All statuses']];
const PAGE = 50;
const NO_FILTERS = { status: 'validated', pest: '', level: '', municipality: '', crop_stage: '', land_type: '', start: '', end: '' };

export default function RecordsPage({ viewer, onChanged }) {
  const isAgri = viewer.role === 'agriculturist';
  const [search, setSearch] = useState('');
  const [f, setF] = useState(NO_FILTERS);
  const [shown, setShown] = useState(PAGE);
  const [openId, setOpenId] = useState(null);
  const q = useDebounced(search);
  const params = { ...f, q };
  const res = useAsync(() => api.records(params), [JSON.stringify(params)]);
  const set = (key) => (value) => {
    setShown(PAGE);
    setF((prev) => ({ ...prev, [key]: value }));
  };
  const rows = res.data?.rows || [];
  const filtered = search || JSON.stringify(f) !== JSON.stringify(NO_FILTERS);

  const columns = [
    {
      key: 'photo',
      label: '',
      className: 'w-16',
      render: (r) => <AuthImage scanId={r.id} className="h-12 w-12 rounded-lg border border-line" />,
    },
    {
      key: 'id',
      label: 'Observation',
      render: (r) => (
        <div>
          <div className="font-semibold text-ink">#{r.id}</div>
          <div className="text-xs text-ink2">{fmtDate(r.created_at)}</div>
        </div>
      ),
    },
    {
      key: 'where',
      label: 'Submitted by · area',
      render: (r) => (
        <div className="max-w-[220px]">
          <div className="truncate font-medium text-ink">{r.farmer_name || r.user_email}</div>
          <div className="truncate text-xs text-ink2">{[r.barangay, r.municipality].filter(Boolean).join(', ')}</div>
        </div>
      ),
    },
    {
      key: 'pest',
      label: 'Pest / report',
      render: (r) => (r.is_disease ? <Badge tone="purple">Disease report</Badge> : <span className="font-medium">{r.pest}</span>),
    },
    {
      key: 'count',
      label: 'Count',
      align: 'right',
      render: (r) => {
        if (r.is_disease) return <span className="text-muted">—</span>;
        // Not validated yet: only the model result's count exists.
        if (r.status !== 'validated') return r.ai_count == null ? <span className="text-muted">—</span> : <span className="text-ink2">{r.ai_count} (model result)</span>;
        return <span className={r.count === null ? 'text-xs text-ink2' : 'font-semibold'}>{fmtCount(r.count)}</span>;
      },
    },
    { key: 'level', label: 'Level', render: (r) => <LevelBadge level={r.level} /> },
    { key: 'crop_stage', label: 'Crop stage', render: (r) => r.crop_stage || <span className="text-muted">—</span> },
    {
      key: 'land_type',
      label: 'Land type',
      render: (r) => (r.land_type ? r.land_type_label || landTypeLabel(r.land_type) : <span className="text-muted">—</span>),
    },
    { key: 'status', label: 'Status', render: (r) => <StatusBadge status={r.status} /> },
    {
      key: 'validated_by',
      label: 'Reviewed by',
      render: (r) =>
        r.validated_by ? (
          <div className="max-w-[180px]">
            <div className="truncate text-ink2">{r.validated_by}</div>
            <div className="text-xs text-muted">{fmtDate(r.validated_at)}</div>
          </div>
        ) : (
          <span className="text-muted">—</span>
        ),
    },
  ];

  return (
    <div>
      <PageHeader
        title="Validated records"
        description="The official records: observations a technician or agriculturist validated. Search and filter, then open one for the photo, details, review history and treatments."
        area={isAgri ? undefined : viewer.area_label}
      />
      <Panel bodyClassName="">
        <div className="grid gap-3 border-b border-line p-5 sm:grid-cols-2 lg:grid-cols-4">
          <Field label="Search" className="sm:col-span-2">
            <input
              className="input"
              value={search}
              onChange={(e) => {
                setShown(PAGE);
                setSearch(e.target.value);
              }}
              placeholder="Observation #, name, barangay, pest, diagnosis, notes…"
            />
          </Field>
          <Field label="Status">
            <Select value={f.status} onChange={set('status')} options={STATUSES} />
          </Field>
          <Field label="Pest / report">
            <Select value={f.pest} onChange={set('pest')} placeholder="All" options={res.data?.facets.pests || []} />
          </Field>
          <Field label="Infestation level">
            <Select value={f.level} onChange={set('level')} placeholder="All levels" options={LEVELS} />
          </Field>
          <Field label="Crop stage">
            <Select value={f.crop_stage} onChange={set('crop_stage')} placeholder="All stages" options={CROP_STAGES} />
          </Field>
          <Field label="Land type">
            <Select value={f.land_type} onChange={set('land_type')} placeholder="All land types" options={LAND_TYPES} />
          </Field>
          {isAgri && (
            <Field label="Municipality">
              <Select value={f.municipality} onChange={set('municipality')} placeholder="All municipalities" options={res.data?.facets.municipalities || []} />
            </Field>
          )}
          <div className="grid grid-cols-2 gap-3">
            <Field label="From">
              <input type="date" className="input" value={f.start} onChange={(e) => set('start')(e.target.value)} />
            </Field>
            <Field label="To">
              <input type="date" className="input" value={f.end} onChange={(e) => set('end')(e.target.value)} />
            </Field>
          </div>
        </div>
        <div className="flex items-center justify-between px-5 py-3 text-xs text-ink2">
          <span>{res.data ? `${rows.length.toLocaleString('en-PH')} observation${rows.length === 1 ? '' : 's'}` : ' '}</span>
          <span className="flex items-center gap-3">
            {res.loading && res.data && <span>Updating…</span>}
            {filtered && (
              <Button
                variant="ghost"
                size="sm"
                onClick={() => {
                  setSearch('');
                  setF(NO_FILTERS);
                }}
              >
                Clear filters
              </Button>
            )}
          </span>
        </div>
        <ErrorNote message={res.error} onRetry={res.reload} />
        {!res.data && res.loading ? (
          <Loading />
        ) : (
          <Table
            rows={rows.slice(0, shown)}
            columns={columns}
            onRowClick={(r) => setOpenId(r.id)}
            empty={<Empty title="No observations match">Try clearing a filter or widening the date range.</Empty>}
          />
        )}
        {rows.length > shown && (
          <div className="border-t border-line p-4 text-center">
            <Button variant="secondary" onClick={() => setShown((n) => n + PAGE)}>
              Show {Math.min(PAGE, rows.length - shown)} more
            </Button>
          </div>
        )}
      </Panel>
      {openId && (
        <RecordDrawer
          scanId={openId}
          viewer={viewer}
          onClose={() => setOpenId(null)}
          onChanged={() => {
            res.reload();
            onChanged?.();
          }}
        />
      )}
    </div>
  );
}
