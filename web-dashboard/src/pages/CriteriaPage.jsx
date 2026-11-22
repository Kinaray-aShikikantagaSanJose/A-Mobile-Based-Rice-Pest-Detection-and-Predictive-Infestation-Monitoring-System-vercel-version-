import { useState } from 'react';
import { api } from '../api.js';
import { useLevelSuggestion } from '../components/ReviewForm.jsx';
import { Badge, Button, Empty, ErrorNote, Field, LEVEL_COLOR, LevelBadge, Loading, Notice, Panel, PageHeader, Select } from '../components/ui.jsx';
import { useT } from '../i18n/index.jsx';
import { CROP_STAGES, fmtDate, fmtNum, PEST_OPTIONS, useAction, useAsync } from '../lib.js';

const isPlaceholder = (row) => row.updated_by === 'placeholder';
const stageLabel = (s) => s || 'Any stage';

/** LOW | MEDIUM | HIGH count ranges drawn to scale. */
function Scale({ medium, high }) {
  const t = useT();
  const max = high * 1.5;
  const seg = [
    ['LOW', 0, medium],
    ['MEDIUM', medium, high],
    ['HIGH', high, max],
  ];
  return (
    <div>
      <div className="flex h-2.5 overflow-hidden rounded-full">
        {seg.map(([k, a, b]) => (
          <div key={k} style={{ width: `${((b - a) / max) * 100}%`, background: LEVEL_COLOR[k] }} />
        ))}
      </div>
      <div className="mt-1.5 flex flex-wrap gap-x-4 gap-y-0.5 text-xs text-ink2">
        <span>
          <b className="text-ink">{t('LOW')}</b> {t('below {n}', { n: fmtNum(medium, 2) })}
        </span>
        <span>
          <b className="text-ink">{t('MEDIUM')}</b> {t('from {n}', { n: fmtNum(medium, 2) })}
        </span>
        <span>
          <b className="text-ink">{t('HIGH')}</b> {t('from {n}', { n: fmtNum(high, 2) })}
        </span>
      </div>
    </div>
  );
}

function ThresholdEditor({ pest, stage, stageOptions, initial, onSaved, onCancel }) {
  const t = useT();
  const [crop, setCrop] = useState(stage ?? stageOptions?.[0] ?? '');
  const [medium, setMedium] = useState(initial ? String(initial.medium_from) : '');
  const [high, setHigh] = useState(initial ? String(initial.high_from) : '');
  const action = useAction();
  const m = Number(medium);
  const h = Number(high);
  const filled = medium !== '' && high !== '';
  const invalid = !filled || Number.isNaN(m) || Number.isNaN(h) || m < 0 || h <= 0 || h <= m;
  const save = () =>
    action.run(async () => {
      await api.saveCriteria({ pest, crop_stage: crop, medium_from: m, high_from: h });
      onSaved(t('{stage} thresholds saved.', { stage: t(stageLabel(crop)) }));
    });
  return (
    <div className="space-y-3 rounded-xl border border-brand-200 bg-brand-50/50 p-4">
      <div className="grid gap-3 sm:grid-cols-3">
        {stageOptions ? (
          <Field label={t('Crop stage')}>
            <Select value={crop} onChange={setCrop} options={stageOptions.map((s) => [s, t(s)])} />
          </Field>
        ) : (
          <Field label={t('Crop stage')}>
            <input className="input" value={t(stageLabel(crop))} disabled />
          </Field>
        )}
        <Field label={t('MEDIUM from (count)')}>
          <input type="number" min="0" step="any" className="input" value={medium} onChange={(e) => setMedium(e.target.value)} />
        </Field>
        <Field label={t('HIGH from (count)')}>
          <input type="number" min="0" step="any" className="input" value={high} onChange={(e) => setHigh(e.target.value)} />
        </Field>
      </div>
      {!invalid && <Scale medium={m} high={h} />}
      {filled && h <= m && <p className="text-xs text-red-600">{t('HIGH must start above MEDIUM.')}</p>}
      <ErrorNote message={action.error} />
      <div className="flex justify-end gap-2">
        <Button variant="secondary" size="sm" onClick={onCancel}>
          {t('Cancel')}
        </Button>
        <Button size="sm" onClick={save} busy={action.busy} disabled={invalid}>
          {t('Save thresholds')}
        </Button>
      </div>
    </div>
  );
}

function ThresholdRow({ row, canEdit, editing, onEdit, onCancel, onSaved }) {
  const t = useT();
  const action = useAction();
  const remove = () => {
    if (!window.confirm(t('Remove the {stage} thresholds? That stage will use the any-stage thresholds again.', { stage: t(row.crop_stage) }))) return;
    action.run(async () => {
      await api.deleteCriteria(row.id);
      onSaved(t('{stage} thresholds removed.', { stage: t(row.crop_stage) }));
    });
  };
  if (editing) {
    return <ThresholdEditor pest={row.pest} stage={row.crop_stage} initial={row} onCancel={onCancel} onSaved={onSaved} />;
  }
  return (
    <div className="space-y-2 rounded-xl border border-line p-4">
      <div className="flex flex-wrap items-center justify-between gap-2">
        <div className="flex flex-wrap items-center gap-2">
          <span className="font-semibold text-ink">{t(stageLabel(row.crop_stage))}</span>
          {isPlaceholder(row) && <Badge tone="orange">{t('Placeholder')}</Badge>}
        </div>
        {canEdit && (
          <div className="flex gap-2">
            <Button size="sm" variant="secondary" onClick={onEdit}>
              {t('Edit')}
            </Button>
            {row.crop_stage && (
              <Button size="sm" variant="danger" onClick={remove} busy={action.busy}>
                {t('Remove')}
              </Button>
            )}
          </div>
        )}
      </div>
      <Scale medium={row.medium_from} high={row.high_from} />
      <div className="text-xs text-muted">
        {isPlaceholder(row) ? t('Seeded placeholder value') : t('Updated by {name} · {date}', { name: row.updated_by || '—', date: fmtDate(row.updated_at) })}
      </div>
      <ErrorNote message={action.error} />
    </div>
  );
}

function PestCriteria({ c, canEdit, onSaved }) {
  const t = useT();
  const [editing, setEditing] = useState(null); // null | row id | 'any' | 'stage'
  const anyStage = c.thresholds.find((r) => r.crop_stage === '');
  const unusedStages = CROP_STAGES.filter((s) => !c.thresholds.some((r) => r.crop_stage === s));
  const saved = (message) => {
    setEditing(null);
    onSaved(`${c.pest_name}: ${message}`);
  };
  return (
    <Panel
      title={c.pest_name}
      subtitle={
        anyStage
          ? t('Counts per observation (the insects in one photo or trap check).')
          : t('No thresholds yet: suggestions for this pest start at LOW and rest on the damage indicators.')
      }
      actions={
        canEdit &&
        !editing && (
          <div className="flex flex-wrap gap-2">
            {!anyStage && (
              <Button size="sm" onClick={() => setEditing('any')}>
                {t('Set any-stage thresholds')}
              </Button>
            )}
            {anyStage && unusedStages.length > 0 && (
              <Button size="sm" variant="secondary" onClick={() => setEditing('stage')}>
                {t('Add stage-specific thresholds')}
              </Button>
            )}
          </div>
        )
      }
    >
      <div className="grid gap-5 lg:grid-cols-[1.4fr_1fr]">
        <div className="space-y-3">
          {editing === 'any' && <ThresholdEditor pest={c.pest} stage="" onCancel={() => setEditing(null)} onSaved={saved} />}
          {c.thresholds.map((row) => (
            <ThresholdRow
              key={row.id}
              row={row}
              canEdit={canEdit}
              editing={editing === row.id}
              onEdit={() => setEditing(row.id)}
              onCancel={() => setEditing(null)}
              onSaved={saved}
            />
          ))}
          {editing === 'stage' && <ThresholdEditor pest={c.pest} stageOptions={unusedStages} onCancel={() => setEditing(null)} onSaved={saved} />}
          {!c.thresholds.length && editing !== 'any' && <p className="text-sm text-ink2">{t('No count thresholds set.')}</p>}
        </div>
        <div>
          <div className="label">{t('Damage indicators (+1 level each)')}</div>
          <ul className="list-disc space-y-1 pl-5 text-sm text-ink">
            {c.indicators.map((i) => (
              <li key={i}>{i}</li>
            ))}
          </ul>
        </div>
      </div>
    </Panel>
  );
}

function HowItWorks() {
  const t = useT();
  return (
    <Panel title={t('How the suggested level works')}>
      <ol className="list-decimal space-y-2 pl-5 text-sm text-ink">
        <li>
          <b>{t('Count thresholds.')}</b>{' '}
          {t(
            "When the reviewer's count is reliable, it's compared with the thresholds for that pest and crop stage (the stage-specific row if there is one, otherwise the any-stage row): below MEDIUM is LOW, from MEDIUM is MEDIUM, from HIGH is HIGH.",
          )}
        </li>
        <li>
          <b>{t('Damage indicators.')}</b> {t('Each visible damage indicator the reviewer ticks raises the suggestion by one level, up to HIGH.')}
        </li>
        <li>
          <b>{t('No count.')}</b>{' '}
          {t('If the photo is marked not countable (or the pest has no thresholds), the suggestion starts at LOW and rests on the damage indicators.')}
        </li>
        <li>
          <b>{t('The reviewer decides.')}</b>{' '}
          {t(
            'The technician (or agriculturist) sees the suggestion with its reasons and confirms or overrides it. Their level is the one recorded and shown on the map, records and summaries. The level is never taken from the count alone.',
          )}
        </li>
      </ol>
    </Panel>
  );
}

function TryIt() {
  const t = useT();
  const [pest, setPest] = useState(PEST_OPTIONS[0][0]);
  const [stage, setStage] = useState(CROP_STAGES[0]);
  const [count, setCount] = useState('');
  const [indicators, setIndicators] = useState([]);
  const n = count === '' ? null : Number(count);
  const valid = n === null || (Number.isInteger(n) && n >= 0);
  const s = useLevelSuggestion({ pest, crop_stage: stage, count: valid ? n : null, indicators, enabled: valid });
  const toggle = (i) => setIndicators((prev) => (prev.includes(i) ? prev.filter((x) => x !== i) : [...prev, i]));
  return (
    <Panel title={t('Try it')} subtitle={t('See what a reviewer would be offered for a given pest, stage, count and damage.')}>
      <div className="grid gap-5 lg:grid-cols-2">
        <div className="space-y-3">
          <div className="grid gap-3 sm:grid-cols-3">
            <Field label={t('Pest')}>
              <Select
                value={pest}
                onChange={(v) => {
                  setPest(v);
                  setIndicators([]);
                }}
                options={PEST_OPTIONS.map(([k, l]) => [k, t(l)])}
              />
            </Field>
            <Field label={t('Crop stage')}>
              <Select value={stage} onChange={setStage} options={CROP_STAGES.map((s) => [s, t(s)])} />
            </Field>
            <Field label={t('Count')} hint={t('Empty = not countable')}>
              <input type="number" min="0" step="1" className="input" value={count} onChange={(e) => setCount(e.target.value)} />
            </Field>
          </div>
          <div className="space-y-1.5">
            {(s.data?.available_indicators || []).map((i) => (
              <label key={i} className="flex cursor-pointer items-start gap-2 text-sm text-ink">
                <input type="checkbox" className="mt-0.5 h-4 w-4 accent-brand-700" checked={indicators.includes(i)} onChange={() => toggle(i)} />
                {i}
              </label>
            ))}
          </div>
        </div>
        <div className="rounded-xl border border-line bg-canvas/60 p-4">
          <div className="flex items-center gap-2 text-sm">
            <span className="font-semibold text-ink">{t('Suggested level:')}</span>
            {s.data ? <LevelBadge level={s.data.level} /> : <span className="text-muted">—</span>}
            {s.pending && <span className="h-3 w-3 animate-spin rounded-full border-2 border-brand-700 border-r-transparent" />}
          </div>
          <ul className="mt-2 list-disc space-y-0.5 pl-5 text-xs text-ink2">
            {(s.data?.reasons || []).map((r) => (
              <li key={r}>{r}</li>
            ))}
          </ul>
          {!valid && <p className="mt-2 text-xs text-red-600">{t('Enter a whole number.')}</p>}
          {s.error && <p className="mt-2 text-xs text-red-600">{s.error}</p>}
        </div>
      </div>
    </Panel>
  );
}

export default function CriteriaPage({ viewer }) {
  const t = useT();
  const canEdit = viewer.role === 'agriculturist';
  const res = useAsync(() => api.criteria(), []);
  const [notice, setNotice] = useState('');
  const pests = res.data || [];
  const placeholders = pests.flatMap((c) => c.thresholds.filter(isPlaceholder).map(() => c.pest_name));

  const saved = (message) => {
    setNotice(message);
    res.reload();
  };

  return (
    <div>
      <PageHeader
        title={t('Infestation criteria')}
        description={t(
          'Count thresholds per pest (and optionally per crop stage) and the damage indicators reviewers can tick. Together they produce the suggested level a reviewer confirms or overrides.',
        )}
      />
      {placeholders.length > 0 && (
        <div className="mb-4">
          <Notice tone="orange">
            <b>{t('Placeholder thresholds in use')}</b>{' '}
            {t("for {pests}. These were seeded with the system and aren't from an agronomic reference.", { pests: [...new Set(placeholders)].join(', ') })}{' '}
            {canEdit
              ? t('Set the real values from your reference (e.g. the economic thresholds your office uses) so the suggestions are meaningful.')
              : t('An agriculturist still needs to set the real values. Rely on what you see in the field when confirming a level.')}
          </Notice>
        </div>
      )}
      {!canEdit && (
        <div className="mb-4">
          <Notice tone="gray">{t('Only agriculturists can change these settings.')}</Notice>
        </div>
      )}
      {notice && (
        <div className="mb-4">
          <Notice>{notice}</Notice>
        </div>
      )}
      <div className="space-y-6">
        <HowItWorks />
        <ErrorNote message={res.error} onRetry={res.reload} />
        {!res.data && res.loading && <Loading />}
        {res.data && !pests.length && (
          <Panel>
            <Empty title={t('No criteria found')} />
          </Panel>
        )}
        {pests.map((c) => (
          <PestCriteria key={c.pest} c={c} canEdit={canEdit} onSaved={saved} />
        ))}
        {res.data && <TryIt />}
      </div>
    </div>
  );
}
