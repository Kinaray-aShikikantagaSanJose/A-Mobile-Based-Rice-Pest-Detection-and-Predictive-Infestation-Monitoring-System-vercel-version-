import { useMemo, useState } from 'react';
import { api } from '../api.js';
import HotspotMap, { SPREAD_COLORS } from '../components/HotspotMap.jsx';
import RecordDrawer from '../components/RecordDrawer.jsx';
import { Button, Empty, ErrorNote, Field, LEVEL_COLOR, LevelBadge, Loading, Notice, Panel, PageHeader, Segmented, Select, Stat, Table } from '../components/ui.jsx';
import { CROP_STAGES, fmtDate, fmtNum, LAND_TYPES, LEVELS, useAsync } from '../lib.js';
import { filterSample, samplePoints } from '../sampleMapData.js';

const NO_FILTERS = { start: '', end: '', pest: '', crop_stage: '', level: '', municipality: '', land_type: '' };
const SPREAD_WINDOWS = [
  [7, 'Week to week'],
  [14, '2 weeks'],
  [30, '30 days'],
];

/** Active hotspots by highest level, e.g. on the home summary row. */
export function HotspotStat({ counts, days }) {
  return (
    <div className="rounded-2xl border border-line bg-white p-4 shadow-sm">
      <div className="text-xs font-semibold uppercase tracking-wide text-ink2">Active hotspots</div>
      <div className="mt-1 flex items-end gap-4">
        {LEVELS.map((lv) => (
          <div key={lv}>
            <div className="text-2xl font-bold tabular-nums" style={{ color: LEVEL_COLOR[lv] }}>
              {fmtNum(counts[lv])}
            </div>
            <div className="text-[11px] font-semibold text-ink2">{lv}</div>
          </div>
        ))}
      </div>
      <div className="mt-1 text-xs text-muted">Barangays with validated records, last {days} days</div>
    </div>
  );
}

/** A small arrow pointing along `bearing` (degrees clockwise from north). */
function Arrow({ bearing, color }) {
  return (
    <svg width="22" height="22" viewBox="0 0 26 26" style={{ transform: `rotate(${bearing}deg)` }} aria-hidden="true">
      <path d="M13 2 L22 22 L13 17 L4 22 Z" fill={color} />
    </svg>
  );
}

/** Directional spread per pest: the label, dates, records used, and the required note. */
function SpreadPanel({ res, windowDays, onWindow, sample }) {
  const d = res.data;
  return (
    <Panel
      className="mt-6"
      title="Directional spread"
      subtitle={
        d
          ? `${d.windows[0].name}: ${d.windows[0].label} · ${d.windows[1].name}: ${d.windows[1].label} · needs at least ${d.min_records} validated records with a location in each`
          : 'Where validated cases cluster in two consecutive windows'
      }
      actions={<Segmented value={windowDays} onChange={onWindow} options={SPREAD_WINDOWS} />}
    >
      <Notice tone="gray">Based on reported cases only. It shows observed movement, not a forecast.</Notice>
      {sample && <p className="mt-3 text-xs text-muted">Directional spread always uses real validated records, never the sample data.</p>}
      <div className="mt-3">
        <ErrorNote message={res.error} onRetry={res.reload} />
      </div>
      {!d && res.loading && <Loading />}
      {d && !d.pests.length && (
        <Empty title={d.not_enough_message}>
          No validated records with a location in {d.windows[0].name} or {d.windows[1].name} match these filters.
        </Empty>
      )}
      {d && d.pests.length > 0 && (
        <ul className="mt-1 divide-y divide-line">
          {d.pests.map((s, i) => (
            <li key={s.pest} className="flex items-start gap-3 py-3">
              <span className="mt-0.5 flex h-8 w-8 shrink-0 items-center justify-center rounded-full bg-canvas">
                {s.status === 'moved' ? (
                  <Arrow bearing={s.bearing} color={SPREAD_COLORS[i % SPREAD_COLORS.length]} />
                ) : (
                  <span className="text-sm font-bold text-muted">{s.status === 'still' ? '•' : '–'}</span>
                )}
              </span>
              <div className="min-w-0">
                <div className="text-sm font-semibold text-ink">
                  {s.pest}
                  {s.status === 'moved' && (
                    <span className="ml-2 rounded-full bg-violet-50 px-2 py-0.5 text-xs font-bold text-violet-700">{s.direction}</span>
                  )}
                </div>
                <div className={`text-sm ${s.status === 'insufficient' ? 'text-ink2' : 'text-ink'}`}>{s.message}</div>
                <div className="text-xs text-muted">{s.detail}</div>
              </div>
            </li>
          ))}
        </ul>
      )}
    </Panel>
  );
}

/** Filters + map (markers or heatmap) + directional spread + hotspot list. Validated observations only. */
export function HotspotExplorer({ viewer, mapClassName }) {
  const isAgri = viewer.role === 'agriculturist';
  const [filters, setFilters] = useState(NO_FILTERS);
  const [openId, setOpenId] = useState(null);
  const [focus, setFocus] = useState(null);
  const [mode, setMode] = useState('markers');
  const [weightBy, setWeightBy] = useState('level');
  const [sample, setSample] = useState(false);
  const [windowDays, setWindowDays] = useState(7);
  const res = useAsync(() => api.hotspots(filters), [JSON.stringify(filters)]);
  // The spread compares the two windows that end on the "To" date (today when empty).
  const spreadParams = {
    pest: filters.pest,
    level: filters.level,
    municipality: filters.municipality,
    crop_stage: filters.crop_stage,
    land_type: filters.land_type,
    end: filters.end,
    window: windowDays,
  };
  const spread = useAsync(() => api.spread(spreadParams), [JSON.stringify(spreadParams)]);
  const set = (key) => (value) => setFilters((f) => ({ ...f, [key]: value }));
  const d = res.data;
  const filtered = Object.values(filters).some(Boolean);
  const samplePts = useMemo(() => (sample ? filterSample(samplePoints(), filters) : null), [sample, filters]);
  const points = sample ? samplePts : d?.points || [];
  const hotspots = sample ? [] : d?.hotspots || [];

  return (
    <>
      <Panel
        title="Hotspot map"
        subtitle={
          sample
            ? `SAMPLE DATA · ${fmtNum(points.length)} generated points, not real records`
            : d
              ? `Validated observations only · ${fmtNum(d.points.length)} with GPS${filtered ? ' match the filters' : ''} · ${fmtNum(d.hotspots.length)} barangay hotspot${d.hotspots.length === 1 ? '' : 's'}`
              : 'Validated observations only'
        }
        actions={
          filtered && (
            <Button variant="ghost" size="sm" onClick={() => setFilters(NO_FILTERS)}>
              Clear filters
            </Button>
          )
        }
      >
        <div className={`mb-4 grid gap-3 sm:grid-cols-2 lg:grid-cols-4 ${isAgri ? 'xl:grid-cols-7' : 'xl:grid-cols-6'}`}>
          <Field label="Pest type">
            <Select value={filters.pest} onChange={set('pest')} placeholder="All" options={d?.facets.pests || []} />
          </Field>
          <Field label="From">
            <input type="date" className="input" value={filters.start} onChange={(e) => set('start')(e.target.value)} />
          </Field>
          <Field label="To">
            <input type="date" className="input" value={filters.end} onChange={(e) => set('end')(e.target.value)} />
          </Field>
          <Field label="Crop stage">
            <Select value={filters.crop_stage} onChange={set('crop_stage')} placeholder="All stages" options={CROP_STAGES} />
          </Field>
          <Field label="Infestation level">
            <Select value={filters.level} onChange={set('level')} placeholder="All levels" options={LEVELS} />
          </Field>
          <Field label="Land type">
            <Select value={filters.land_type} onChange={set('land_type')} placeholder="All land types" options={LAND_TYPES} />
          </Field>
          {isAgri && (
            <Field label="Municipality">
              <Select value={filters.municipality} onChange={set('municipality')} placeholder="All" options={d?.facets.municipalities || []} />
            </Field>
          )}
        </div>
        <div className="mb-4 flex flex-wrap items-center gap-3">
          <Segmented
            value={mode}
            onChange={setMode}
            options={[
              ['markers', 'Markers'],
              ['heat', 'Heatmap'],
            ]}
          />
          {mode === 'heat' && (
            <Segmented
              value={weightBy}
              onChange={setWeightBy}
              options={[
                ['level', 'Weight: infestation level'],
                ['cases', 'Weight: number of cases'],
              ]}
            />
          )}
          <label className="ml-auto flex items-center gap-2 text-xs font-semibold text-ink2">
            <input type="checkbox" checked={sample} onChange={(e) => setSample(e.target.checked)} />
            Preview with sample data (5,000 points)
          </label>
        </div>
        {sample && (
          <div className="mb-4">
            <Notice tone="orange">
              <b>Sample data.</b> These points are generated for trying the map with many records. They are not real observations;
              untick the box to see validated records.
            </Notice>
          </div>
        )}
        <ErrorNote message={res.error} onRetry={res.reload} />
        {!d && res.loading && !sample ? (
          <Loading label="Loading map…" />
        ) : (
          (d || sample) && (
            <HotspotMap
              points={points}
              hotspots={hotspots}
              focus={focus}
              onSelect={(p) => setOpenId(p.id)}
              className={mapClassName}
              mode={mode}
              weightBy={weightBy}
              spread={sample ? [] : spread.data?.pests || []}
            />
          )
        )}
      </Panel>

      <SpreadPanel res={spread} windowDays={windowDays} onWindow={setWindowDays} sample={sample} />

      {d && (
        <Panel className="mt-6" title="Barangay hotspots" subtitle="Highest confirmed level first. Click a row to zoom the map to it." bodyClassName="">
          <Table
            rowKey="key"
            rows={d.hotspots.map((h) => ({ ...h, key: `${h.municipality}|${h.barangay}` }))}
            onRowClick={(h) => setFocus({ lat: h.lat, lng: h.lng, at: Date.now() })}
            empty={<Empty title="No hotspots">No validated pest observations with a location match these filters.</Empty>}
            columns={[
              { key: 'barangay', label: 'Barangay', className: 'font-medium' },
              { key: 'municipality', label: 'Municipality' },
              { key: 'level', label: 'Highest level', render: (h) => <LevelBadge level={h.level} /> },
              { key: 'records', label: 'Records', align: 'right', render: (h) => fmtNum(h.records) },
              { key: 'pests', label: 'Pests', render: (h) => <span className="text-ink2">{h.pests.join(', ')}</span> },
              { key: 'latest', label: 'Latest', render: (h) => fmtDate(h.latest) },
            ]}
          />
        </Panel>
      )}

      {openId && <RecordDrawer scanId={openId} viewer={viewer} onClose={() => setOpenId(null)} onChanged={res.reload} />}
    </>
  );
}

export default function MapPage({ viewer }) {
  const isAgri = viewer.role === 'agriculturist';
  const overview = useAsync(() => (isAgri ? Promise.resolve(null) : api.overview()), [isAgri]);
  const o = overview.data;
  return (
    <div>
      <PageHeader
        title="Hotspot map"
        description={
          isAgri
            ? 'The whole province. Only validated observations appear; hotspots are barangays coloured by the highest infestation level a reviewer confirmed.'
            : 'Your coverage area. Only validated observations appear; hotspots are barangays coloured by the highest infestation level a reviewer confirmed.'
        }
        area={isAgri ? undefined : viewer.area_label}
      />
      {o && (
        <div className="mb-6 grid grid-cols-2 gap-3 lg:grid-cols-4">
          <Stat label="For validation" value={fmtNum(o.pending)} tone={o.pending ? 'orange' : 'muted'} hint="In your queue" />
          <Stat label="Validated this month" value={fmtNum(o.validated_this_month)} tone="brand" />
          <HotspotStat counts={o.hotspots} days={o.hotspot_days} />
          <Stat label="Escalated" value={fmtNum(o.escalated)} tone={o.escalated ? 'red' : 'muted'} hint="Waiting for an agriculturist" />
        </div>
      )}
      <HotspotExplorer viewer={viewer} />
    </div>
  );
}
