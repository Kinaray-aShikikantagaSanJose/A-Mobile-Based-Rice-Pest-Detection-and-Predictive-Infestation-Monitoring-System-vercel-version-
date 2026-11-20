import { useState } from 'react';
import { api } from '../api.js';
import { Button, ErrorNote, Field, PageHeader, Select } from '../components/ui.jsx';
import { LAND_TYPES, monthLabel, MUNICIPALITIES, quarterLabel, todayIso, useAction, useAsync } from '../lib.js';

function ReportCard({ title, description, columns, children, onDownload, disabled }) {
  const action = useAction();
  const [done, setDone] = useState(false);
  const download = () =>
    action.run(async () => {
      setDone(false);
      await onDownload();
      setDone(true);
    });
  return (
    <section className="flex flex-col rounded-2xl border border-line bg-white p-5 shadow-sm">
      <h2 className="text-base font-bold text-ink">{title}</h2>
      <p className="mt-1 text-sm text-ink2">{description}</p>
      <p className="mt-2 text-xs text-muted">Columns: {columns}</p>
      <div className="mt-4 flex-1 space-y-3">{children}</div>
      <div className="mt-5 flex items-center justify-between gap-3 border-t border-line pt-4">
        <span className="text-xs text-emerald-700">{done && !action.busy ? 'Downloaded.' : ''}</span>
        <Button onClick={download} busy={action.busy} disabled={disabled}>
          Download CSV
        </Button>
      </div>
      <div className="mt-3">
        <ErrorNote message={action.error} />
      </div>
    </section>
  );
}

export default function ReportsPage() {
  const [rec, setRec] = useState({ start: '', end: '', municipality: '', land_type: '' });
  const [treat, setTreat] = useState({ start: '', end: '' });
  const [month, setMonth] = useState('');
  const [quarter, setQuarter] = useState('');
  // The report endpoints fall back to the latest period when asked for one without data,
  // so the pickers only offer periods that have observations.
  const months = useAsync(() => api.monthly(''), []);
  const quarters = useAsync(() => api.quarterly(''), []);
  const monthOptions = (months.data?.months || []).map((m) => [m.month, monthLabel(m.month)]);
  const quarterOptions = [...(quarters.data?.quarters || [])].reverse().map((q) => [q.quarter, quarterLabel(q.quarter)]);
  const pickedMonth = month || monthOptions[0]?.[0] || '';
  const pickedQuarter = quarter || quarterOptions[0]?.[0] || '';
  const stamp = todayIso();

  return (
    <div>
      <PageHeader
        title="Report export"
        description="CSV files for preparing advisories and reports. They open in Excel or Google Sheets and cover every area. Only validated observations count as official records."
      />
      <div className="grid gap-4 lg:grid-cols-2">
        <ReportCard
          title="Validated observations"
          description="Every validated observation with the confirmed pest, count, infestation level, reviewer, diagnosis and guidance."
          columns="observation ID, date, municipality, barangay, submitted by, type, pest, count, infestation level, crop stage, land type, monitoring method, validated by / at, diagnosis, guidance, latitude, longitude"
          onDownload={() => api.downloadReport('records', rec, `validated-observations-${stamp}.csv`)}
        >
          <div className="grid gap-3 sm:grid-cols-4">
            <Field label="From">
              <input type="date" className="input" value={rec.start} onChange={(e) => setRec({ ...rec, start: e.target.value })} />
            </Field>
            <Field label="To">
              <input type="date" className="input" value={rec.end} onChange={(e) => setRec({ ...rec, end: e.target.value })} />
            </Field>
            <Field label="Municipality">
              <Select value={rec.municipality} onChange={(v) => setRec({ ...rec, municipality: v })} placeholder="All" options={MUNICIPALITIES} />
            </Field>
            <Field label="Land type">
              <Select value={rec.land_type} onChange={(v) => setRec({ ...rec, land_type: v })} placeholder="All" options={LAND_TYPES} />
            </Field>
          </div>
        </ReportCard>

        <ReportCard
          title="Monthly summary"
          description="Validated observations and pests counted for one month, broken down by municipality, by pest and by land type with LOW / MEDIUM / HIGH counts."
          columns="month, breakdown, name, validated observations, pests counted, LOW, MEDIUM, HIGH"
          disabled={!pickedMonth}
          onDownload={() => api.downloadReport('monthly', { month: pickedMonth }, `monthly-summary-${pickedMonth}.csv`)}
        >
          <Field label="Month" className="max-w-[240px]">
            {monthOptions.length ? (
              <Select value={pickedMonth} onChange={setMonth} options={monthOptions} />
            ) : (
              <input className="input" disabled value={months.loading ? 'Loading…' : 'No observations yet'} />
            )}
          </Field>
          <ErrorNote message={months.error} />
        </ReportCard>

        <ReportCard
          title="Quarterly patterns"
          description="Each municipality and pest with this quarter, the previous quarter and the same quarter last year, the pattern and the recurring flag. Patterns in past records, not a forecast."
          columns="quarter, municipality, pest, compared by, this quarter, previous quarter, same quarter last year, change %, pattern, recurring, note"
          disabled={!pickedQuarter}
          onDownload={() => api.downloadReport('quarterly', { quarter: pickedQuarter }, `quarterly-patterns-${pickedQuarter}.csv`)}
        >
          <Field label="Quarter" hint="The last 8 quarters with validated observations." className="max-w-[240px]">
            {quarterOptions.length ? (
              <Select value={pickedQuarter} onChange={setQuarter} options={quarterOptions} />
            ) : (
              <input className="input" disabled value={quarters.loading ? 'Loading…' : 'No validated observations yet'} />
            )}
          </Field>
          <ErrorNote message={quarters.error} />
        </ReportCard>

        <ReportCard
          title="Treatment follow-ups"
          description="Each logged treatment with its linked follow-up observation: level and count before and after, change, and outcome."
          columns="treatment ID, observation ID, municipality, barangay, farmer, pest, crop stage, land type, treatment, type, applied, follow-up due, level / count before, follow-up observation, level / count after, change %, outcome"
          onDownload={() => api.downloadReport('treatments', treat, `treatment-followups-${stamp}.csv`)}
        >
          <div className="grid max-w-md grid-cols-2 gap-3">
            <Field label="Applied from">
              <input type="date" className="input" value={treat.start} onChange={(e) => setTreat({ ...treat, start: e.target.value })} />
            </Field>
            <Field label="Applied to">
              <input type="date" className="input" value={treat.end} onChange={(e) => setTreat({ ...treat, end: e.target.value })} />
            </Field>
          </div>
        </ReportCard>
      </div>
    </div>
  );
}
