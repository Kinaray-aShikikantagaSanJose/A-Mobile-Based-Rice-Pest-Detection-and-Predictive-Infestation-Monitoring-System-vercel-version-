import { useState } from 'react';
import { api } from '../api.js';
import AuthImage from '../components/AuthImage.jsx';
import RecordDrawer from '../components/RecordDrawer.jsx';
import { useT } from '../i18n/index.jsx';
import { Badge, Button, Empty, ErrorNote, Field, LevelBadge, Loading, Panel, PageHeader, Select, STATUS_OPTIONS, StatusBadge, Table } from '../components/ui.jsx';
import { CROP_STAGES, fmtCount, fmtDate, LAND_TYPES, landTypeLabel, LEVELS, useAsync, useDebounced } from '../lib.js';

const STATUSES = [...STATUS_OPTIONS, ['all', 'All statuses']];
const PAGE = 50;
const NO_FILTERS = { status: 'validated', pest: '', level: '', municipality: '', crop_stage: '', land_type: '', start: '', end: '' };

export default function RecordsPage({ viewer, onChanged }) {
  const t = useT();
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
      label: t('Observation'),
      render: (r) => (
        <div>
          <div className="font-semibold text-ink">#{r.id}</div>
          <div className="text-xs text-ink2">{fmtDate(r.created_at)}</div>
        </div>
      ),
    },
    {
      key: 'where',
      label: t('Submitted by · area'),
      render: (r) => (
        <div className="max-w-[220px]">
          <div className="truncate font-medium text-ink">{r.farmer_name || r.user_email}</div>
          <div className="truncate text-xs text-ink2">{[r.barangay, r.municipality].filter(Boolean).join(', ')}</div>
        </div>
      ),
    },
    {
      key: 'pest',
      label: t('Pest / report'),
      render: (r) =>
        r.is_disease ? (
          <Badge tone="purple">{t('Disease report')}</Badge>
        ) : (
          <span className="font-medium">{['No pests found', 'Not identified yet', 'Unidentified', 'Outside the supported pests'].includes(r.pest) ? t(r.pest) : r.pest}</span>
        ),
    },
    {
      key: 'count',
      label: t('Count'),
      align: 'right',
      render: (r) => {
        if (r.is_disease) return <span className="text-muted">—</span>;
        // Not validated yet: only the model result's count exists.
        if (r.status !== 'validated') return r.ai_count == null ? <span className="text-muted">—</span> : <span className="text-ink2">{t('{n} (model result)', { n: r.ai_count })}</span>;
        return <span className={r.count === null ? 'text-xs text-ink2' : 'font-semibold'}>{fmtCount(r.count)}</span>;
      },
    },
    { key: 'level', label: t('Level'), render: (r) => <LevelBadge level={r.level} /> },
    { key: 'crop_stage', label: t('Crop stage'), render: (r) => (r.crop_stage ? t(r.crop_stage) : <span className="text-muted">—</span>) },
    {
      key: 'land_type',
      label: t('Land type'),
      render: (r) => (r.land_type ? t(r.land_type_label || landTypeLabel(r.land_type)) : <span className="text-muted">—</span>),
    },
    { key: 'status', label: t('Status'), render: (r) => <StatusBadge status={r.status} /> },
    {
      key: 'validated_by',
      label: t('Reviewed by'),
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
        title={t('Validated records')}
        description={t('The official records: observations a technician or agriculturist validated. Search and filter, then open one for the photo, details, review history and treatments.')}
        area={isAgri ? undefined : viewer.area_label}
      />
      <Panel bodyClassName="">
        <div className="grid gap-3 border-b border-line p-5 sm:grid-cols-2 lg:grid-cols-4">
          <Field label={t('Search')} className="sm:col-span-2">
            <input
              className="input"
              value={search}
              onChange={(e) => {
                setShown(PAGE);
                setSearch(e.target.value);
              }}
              placeholder={t('Observation #, name, barangay, pest, diagnosis, notes…')}
            />
          </Field>
          <Field label={t('Status')}>
            <Select value={f.status} onChange={set('status')} options={STATUSES.map(([v, l]) => [v, t(l)])} />
          </Field>
          <Field label={t('Pest / report')}>
            <Select
              value={f.pest}
              onChange={set('pest')}
              placeholder={t('All')}
              options={(res.data?.facets.pests || []).map((p) => [p, ['Disease report', 'No pests found', 'Not identified yet', 'Unidentified'].includes(p) ? t(p) : p])}
            />
          </Field>
          <Field label={t('Infestation level')}>
            <Select value={f.level} onChange={set('level')} placeholder={t('All levels')} options={LEVELS.map((l) => [l, t(l)])} />
          </Field>
          <Field label={t('Crop stage')}>
            <Select value={f.crop_stage} onChange={set('crop_stage')} placeholder={t('All stages')} options={CROP_STAGES.map((c) => [c, t(c)])} />
          </Field>
          <Field label={t('Land type')}>
            <Select value={f.land_type} onChange={set('land_type')} placeholder={t('All land types')} options={LAND_TYPES.map(([v, l]) => [v, t(l)])} />
          </Field>
          {isAgri && (
            <Field label={t('Municipality')}>
              <Select value={f.municipality} onChange={set('municipality')} placeholder={t('All municipalities')} options={res.data?.facets.municipalities || []} />
            </Field>
          )}
          <div className="grid grid-cols-2 gap-3">
            <Field label={t('From')}>
              <input type="date" className="input" value={f.start} onChange={(e) => set('start')(e.target.value)} />
            </Field>
            <Field label={t('To')}>
              <input type="date" className="input" value={f.end} onChange={(e) => set('end')(e.target.value)} />
            </Field>
          </div>
        </div>
        <div className="flex items-center justify-between px-5 py-3 text-xs text-ink2">
          <span>{res.data ? t(rows.length === 1 ? '{n} observation' : '{n} observations', { n: rows.length.toLocaleString('en-PH') }) : ' '}</span>
          <span className="flex items-center gap-3">
            {res.loading && res.data && <span>{t('Updating…')}</span>}
            {filtered && (
              <Button
                variant="ghost"
                size="sm"
                onClick={() => {
                  setSearch('');
                  setF(NO_FILTERS);
                }}
              >
                {t('Clear filters')}
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
            empty={<Empty title={t('No observations match')}>{t('Try clearing a filter or widening the date range.')}</Empty>}
          />
        )}
        {rows.length > shown && (
          <div className="border-t border-line p-4 text-center">
            <Button variant="secondary" onClick={() => setShown((n) => n + PAGE)}>
              {t('Show {n} more', { n: Math.min(PAGE, rows.length - shown) })}
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
