import { useState } from 'react';
import { api } from '../api.js';
import { Badge, Button, CheckChips, Drawer, Empty, ErrorNote, Field, LevelBadge, Loading, Notice, Panel, PageHeader, Segmented, Select } from '../components/ui.jsx';
import { CROP_STAGES, fmtDate, LEVELS, OPTION_TYPES, PEST_OPTIONS, pestLabel, useAction, useAsync } from '../lib.js';

const TYPE_LABEL = Object.fromEntries(OPTION_TYPES);
const DOSE_NOTE =
  'Describe approaches (what to do, when, and why), never product doses or amounts. The app tells farmers to consult their technician before using any pesticide.';

function EntryForm({ entry, onSaved, onCancel }) {
  const [form, setForm] = useState({
    pest: entry?.pest || '',
    option_type: entry?.option_type || '',
    crop_stages: entry?.crop_stages || [],
    levels: entry?.levels || [],
    title: entry?.title || '',
    recommendation: entry?.recommendation || '',
    source_reference: entry?.source_reference || '',
  });
  const set = (key) => (value) => setForm((f) => ({ ...f, [key]: value }));
  const action = useAction();
  const save = () =>
    action.run(async () => {
      const body = {
        ...form,
        title: form.title.trim(),
        recommendation: form.recommendation.trim(),
        source_reference: form.source_reference.trim(),
      };
      const saved = entry ? await api.updateEntry(entry.id, body) : await api.createEntry(body);
      onSaved(saved, !entry);
    });
  const ready = form.pest && form.option_type && form.title.trim() && form.recommendation.trim() && form.source_reference.trim().length >= 3;

  return (
    <div className="space-y-4">
      <Notice tone="orange">{DOSE_NOTE}</Notice>
      <div className="grid gap-3 sm:grid-cols-2">
        <Field label="Pest">
          <Select value={form.pest} onChange={set('pest')} placeholder="Choose…" options={PEST_OPTIONS} />
        </Field>
        <Field label="Type">
          <Select value={form.option_type} onChange={set('option_type')} placeholder="Choose…" options={OPTION_TYPES} />
        </Field>
      </div>
      <Field as="div" label="Crop stages" hint="Leave all unselected to apply at every stage.">
        <CheckChips value={form.crop_stages} onChange={set('crop_stages')} options={CROP_STAGES} noneLabel="All stages" />
      </Field>
      <Field as="div" label="Infestation levels" hint="Leave all unselected to apply at every level.">
        <CheckChips value={form.levels} onChange={set('levels')} options={LEVELS} noneLabel="All levels" />
      </Field>
      <Field label="Title">
        <input className="input" value={form.title} onChange={(e) => set('title')(e.target.value)} maxLength={200} placeholder="e.g. Drain the field for a few days" />
      </Field>
      <Field label="Recommendation">
        <textarea
          className="input min-h-[160px]"
          value={form.recommendation}
          onChange={(e) => set('recommendation')(e.target.value)}
          maxLength={4000}
          placeholder="The approach, its timing, and what to watch for."
        />
      </Field>
      <Field label="Source reference" hint="Required. The publication, advisory or manual this comes from.">
        <input
          className="input"
          value={form.source_reference}
          onChange={(e) => set('source_reference')(e.target.value)}
          maxLength={500}
          placeholder="e.g. PhilRice Rice Production Manual, 2nd ed., p. 112"
        />
      </Field>
      {form.option_type === 'chemical' && (
        <Notice tone="gray">Chemical options are shown to farmers as a last resort, with a reminder to talk to their technician first.</Notice>
      )}
      {!entry && <Notice>New entries start as drafts. Technicians and farmers only see them after you approve them.</Notice>}
      <ErrorNote message={action.error} />
      <div className="flex justify-end gap-2">
        <Button variant="secondary" onClick={onCancel}>
          Cancel
        </Button>
        <Button onClick={save} busy={action.busy} disabled={!ready}>
          {entry ? 'Save changes' : 'Add as draft'}
        </Button>
      </div>
    </div>
  );
}

function EntryCard({ entry, canEdit, onEdit, onChanged }) {
  const action = useAction();
  const approved = entry.status === 'approved';
  const toggle = () =>
    action.run(async () => {
      await api.setEntryStatus(entry.id, approved ? 'draft' : 'approved');
      onChanged(approved ? `"${entry.title}" moved back to draft.` : `"${entry.title}" approved.`);
    });
  const remove = () => {
    if (!window.confirm(`Delete "${entry.title}"? Treatments farmers already logged keep their name.`)) return;
    action.run(async () => {
      await api.deleteEntry(entry.id);
      onChanged(`"${entry.title}" deleted.`);
    });
  };
  return (
    <article className="flex flex-col rounded-2xl border border-line bg-white p-5 shadow-sm">
      <div className="mb-2 flex flex-wrap items-center gap-1.5">
        {entry.crop_stages.length ? entry.crop_stages.map((s) => <Badge key={s}>{s}</Badge>) : <Badge>All stages</Badge>}
        {entry.levels.length ? entry.levels.map((l) => <LevelBadge key={l} level={l} />) : <Badge>All levels</Badge>}
        {canEdit && <Badge tone={approved ? 'green' : 'orange'}>{approved ? 'Approved' : 'Draft'}</Badge>}
      </div>
      <h4 className="text-base font-bold text-ink">{entry.title}</h4>
      <p className="mt-2 flex-1 whitespace-pre-line text-sm leading-relaxed text-ink2">{entry.recommendation}</p>
      <p className="mt-3 text-xs text-ink2">
        <span className="font-semibold">Source:</span> {entry.source_reference}
      </p>
      <div className="mt-2 text-xs text-muted">
        {approved ? `Approved by ${entry.approved_by || '—'} · ${fmtDate(entry.approved_at)}` : `Last edited by ${entry.updated_by || '—'} · ${fmtDate(entry.updated_at)}`}
      </div>
      {canEdit && (
        <div className="mt-4 flex flex-wrap gap-2 border-t border-line pt-4">
          <Button size="sm" variant={approved ? 'secondary' : 'primary'} onClick={toggle} busy={action.busy}>
            {approved ? 'Move to draft' : 'Approve'}
          </Button>
          <Button size="sm" variant="secondary" onClick={() => onEdit(entry)}>
            Edit
          </Button>
          <Button size="sm" variant="danger" onClick={remove} disabled={action.busy}>
            Delete
          </Button>
        </div>
      )}
      {action.error && (
        <div className="mt-2">
          <ErrorNote message={action.error} />
        </div>
      )}
    </article>
  );
}

export default function LibraryPage({ viewer }) {
  const canEdit = viewer.role === 'agriculturist';
  const res = useAsync(() => api.library(), []);
  const [editing, setEditing] = useState(null); // null | 'new' | entry
  const [f, setF] = useState({ pest: '', stage: '', level: '', status: 'all', q: '' });
  const [notice, setNotice] = useState('');
  const set = (key) => (value) => setF((prev) => ({ ...prev, [key]: value }));
  const entries = res.data || [];

  // Stage and level match the way farmers are matched: an empty list means "every".
  const q = f.q.trim().toLowerCase();
  const shown = entries.filter(
    (e) =>
      (!f.pest || e.pest === f.pest) &&
      (!f.stage || !e.crop_stages.length || e.crop_stages.includes(f.stage)) &&
      (!f.level || !e.levels.length || e.levels.includes(f.level)) &&
      (f.status === 'all' || e.status === f.status) &&
      (!q || `${e.title} ${e.recommendation} ${e.source_reference}`.toLowerCase().includes(q)),
  );
  const byPest = PEST_OPTIONS.map(([key]) => [key, shown.filter((e) => e.pest === key)]).filter(([, list]) => list.length);
  const drafts = entries.filter((e) => e.status === 'draft').length;

  const changed = (message) => {
    setNotice(message);
    res.reload();
  };

  return (
    <div>
      <PageHeader
        title="Treatment reference library"
        description={
          canEdit
            ? 'Options farmers see on a validated record, matched by pest, crop stage and infestation level and grouped by type. Only approved entries are shown to technicians and farmers.'
            : 'Approved options from the agriculturist. Farmers see the ones matching their validated record’s pest, crop stage and infestation level.'
        }
        actions={canEdit && <Button onClick={() => setEditing('new')}>Add entry</Button>}
      />
      {notice && (
        <div className="mb-4">
          <Notice>{notice}</Notice>
        </div>
      )}
      <Panel className="mb-6" bodyClassName="grid gap-3 p-5 sm:grid-cols-2 lg:grid-cols-5 lg:items-end">
        <Field label="Pest">
          <Select value={f.pest} onChange={set('pest')} placeholder="All pests" options={PEST_OPTIONS} />
        </Field>
        <Field label="Crop stage">
          <Select value={f.stage} onChange={set('stage')} placeholder="Any stage" options={CROP_STAGES} />
        </Field>
        <Field label="Infestation level">
          <Select value={f.level} onChange={set('level')} placeholder="Any level" options={LEVELS} />
        </Field>
        <Field label="Search" className="lg:col-span-2">
          <input className="input" value={f.q} onChange={(e) => set('q')(e.target.value)} placeholder="Title, text or source…" />
        </Field>
        {canEdit && (
          <div className="sm:col-span-2 lg:col-span-5">
            <Segmented
              value={f.status}
              onChange={set('status')}
              options={[
                ['all', 'All'],
                ['approved', 'Approved'],
                ['draft', `Drafts${drafts ? ` (${drafts})` : ''}`],
              ]}
            />
          </div>
        )}
      </Panel>
      {f.pest && f.stage && f.level && (
        <div className="mb-4">
          <Notice tone="gray">
            {canEdit && f.status !== 'approved' ? 'Approved entries here' : 'These'} are what a farmer sees for a validated {pestLabel(f.pest)} record at the{' '}
            {f.stage} stage with a {f.level} level.
          </Notice>
        </div>
      )}
      <ErrorNote message={res.error} onRetry={res.reload} />
      {!res.data && res.loading ? (
        <Loading />
      ) : byPest.length ? (
        <div className="space-y-8">
          {byPest.map(([pest, list]) => (
            <section key={pest}>
              <h2 className="mb-3 text-lg font-bold text-ink">
                {pestLabel(pest)} <span className="text-sm font-normal text-ink2">· {list.length}</span>
              </h2>
              <div className="space-y-5">
                {OPTION_TYPES.filter(([t]) => list.some((e) => e.option_type === t)).map(([t]) => (
                  <div key={t}>
                    <h3 className="mb-2 text-xs font-semibold uppercase tracking-wide text-ink2">{TYPE_LABEL[t]}</h3>
                    <div className="grid gap-4 md:grid-cols-2 2xl:grid-cols-3">
                      {list
                        .filter((e) => e.option_type === t)
                        .map((e) => (
                          <EntryCard key={e.id} entry={e} canEdit={canEdit} onEdit={setEditing} onChanged={changed} />
                        ))}
                    </div>
                  </div>
                ))}
              </div>
            </section>
          ))}
        </div>
      ) : (
        <Panel>
          <Empty title={entries.length ? 'No entries match' : 'The library is empty'}>
            {entries.length ? 'Try another pest, stage or level.' : canEdit ? 'Add the first entry, then approve it.' : 'No approved entries yet.'}
          </Empty>
        </Panel>
      )}
      <Drawer open={Boolean(editing)} onClose={() => setEditing(null)} title={editing === 'new' ? 'New library entry' : 'Edit library entry'} width="max-w-xl">
        {editing && (
          <EntryForm
            entry={editing === 'new' ? null : editing}
            onCancel={() => setEditing(null)}
            onSaved={(saved, created) => {
              setEditing(null);
              changed(created ? `"${saved.title}" was added as a draft. Approve it to show it to technicians and farmers.` : `"${saved.title}" was updated.`);
            }}
          />
        )}
      </Drawer>
    </div>
  );
}
