import { useEffect, useRef, useState } from 'react';
import { api } from '../api.js';
import { fmtConf, fmtCount, LEVELS, PEST_OPTIONS, pestLabel, useAction, useDebounced } from '../lib.js';
import Icon from './icons.jsx';
import { Button, ErrorNote, Field, LEVEL_COLOR, LevelBadge, Notice, Select, useConfirm } from './ui.jsx';
import { useT } from '../i18n/index.jsx';

const RETURN_REASONS = [
  'The photo is too blurry. Please take a new, closer photo.',
  "The pest isn't visible in the photo. Please photograph the insects up close.",
  'The photo is too dark. Please retake it in daylight.',
  "The photo doesn't show a rice crop.",
];

/** Same rule as the server (observations.meaningful): enough characters and two real words. */
export function meaningful(text, minChars = 10) {
  const s = (text || '').split(/\s+/).filter(Boolean).join(' ');
  const words = s.split(' ').filter((w) => /\p{L}/u.test(w));
  return s.length >= minChars && words.length >= 2 && new Set(s.replace(/ /g, '').toLowerCase()).size > 2;
}

/** The reviewer's own note (review history), separate from what the farmer reads. */
function ReviewerNoteField({ value, onChange, invalid }) {
  const t = useT();
  return (
    <Field
      label={t('Reviewer note *')}
      hint={t('What you checked and why you chose this level. Kept in the review history for technicians and agriculturists; it is not the guidance the farmer reads.')}
    >
      <textarea className={`input min-h-[64px] ${invalid ? 'border-red-400 ring-2 ring-red-100' : ''}`} value={value}
        onChange={(e) => onChange(e.target.value)} maxLength={2000}
        placeholder={t('e.g. Counted 6 rice bugs on two panicles; grains not yet damaged')} />
    </Field>
  );
}

/** Options from the APPROVED treatment library the reviewer recommends (not treatments applied). */
function RecommendationPicker({ pest, value, onChange }) {
  const t = useT();
  const [state, setState] = useState({ items: [], error: '', loading: true });
  useEffect(() => {
    let alive = true;
    api
      .library()
      .then((rows) => alive && setState({ items: rows.filter((r) => r.status === 'approved'), error: '', loading: false }))
      .catch((e) => alive && setState({ items: [], error: e.message, loading: false }));
    return () => {
      alive = false;
    };
  }, []);
  const options = state.items.filter((r) => r.pest === pest);
  useEffect(() => {
    onChange((prev) => prev.filter((id) => options.some((o) => o.id === id)));
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [pest, state.items]);
  const toggle = (id) => onChange((prev) => (prev.includes(id) ? prev.filter((x) => x !== id) : [...prev, id]));
  return (
    <Field as="div" label={`${t('Recommend treatment options')} (${t('optional')})`}
      hint={t('Picked from the approved treatment library. The farmer sees them as recommendations; what they actually apply is recorded separately.')}>
      {state.loading ? (
        <p className="text-xs text-muted">{t('Loading…')}</p>
      ) : state.error ? (
        <p className="text-xs text-red-600">{t(state.error)}</p>
      ) : options.length ? (
        <div className="space-y-1.5">
          {options.map((o) => (
            <label key={o.id} className="flex cursor-pointer items-start gap-2 text-sm text-ink">
              <input type="checkbox" className="mt-0.5 h-4 w-4 accent-brand-700" checked={value.includes(o.id)} onChange={() => toggle(o.id)} />
              <span>
                <span className="font-medium">{o.title}</span>{' '}
                <span className="text-xs text-ink2">· {t(o.option_type)}</span>
              </span>
            </label>
          ))}
        </div>
      ) : (
        <p className="text-xs text-muted">{t('No approved options for this pest yet.')}</p>
      )}
    </Field>
  );
}

/** Suggested level from the API (never computed here). Debounced as the reviewer edits. */
export function useLevelSuggestion({ pest, crop_stage, count, indicators, enabled = true }) {
  const key = JSON.stringify({ pest, crop_stage, count, indicators });
  const settled = useDebounced(key, 250);
  const [state, setState] = useState({ data: null, params: null, error: '', loading: false });
  useEffect(() => {
    if (!enabled || !pest) return undefined;
    let alive = true;
    const params = JSON.parse(settled);
    setState((s) => ({ ...s, loading: true, error: '' }));
    api
      .levelSuggestion(params)
      .then((data) => alive && setState({ data, params, error: '', loading: false }))
      .catch((e) => alive && setState((s) => ({ ...s, error: e.message, loading: false })));
    return () => {
      alive = false;
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [settled, enabled]);
  return { ...state, pending: state.loading || key !== settled };
}

function StepTitle({ n, children, hint, error }) {
  return (
    <div className="flex items-start gap-3">
      <span
        className={`mt-0.5 flex h-7 w-7 shrink-0 items-center justify-center rounded-full text-sm font-bold text-white transition-colors ${
          error ? 'bg-red-600' : 'bg-brand-700'
        }`}
      >
        {n}
      </span>
      <div>
        <h4 className="text-base font-bold text-ink">{children}</h4>
        {hint && <p className="text-sm text-ink2">{hint}</p>}
        {error && (
          <p role="alert" className="mt-1 flex items-center gap-1.5 text-sm font-semibold text-red-600">
            <Icon name="alert" className="h-4 w-4" />
            {error}
          </p>
        )}
      </div>
    </div>
  );
}

/** What still has to be filled in before the review can be sent. */
function MissingNote({ items }) {
  const t = useT();
  if (!items.length) return null;
  return (
    <div role="alert" className="animate-shake rounded-xl border-2 border-red-300 bg-red-50 px-4 py-3 text-sm text-red-800">
      <div className="flex items-center gap-2 font-bold">
        <Icon name="alert" className="h-4 w-4" />
        {items.length === 1 ? t('One thing is missing') : t('{n} things are missing', { n: items.length })}
      </div>
      <ul className="mt-1.5 list-disc space-y-0.5 pl-6">
        {items.map((i) => (
          <li key={i}>{i}</li>
        ))}
      </ul>
    </div>
  );
}

const fieldError = (on) => (on ? 'border-red-400 ring-2 ring-red-100' : '');

const MODE_TONES = {
  brand: ['border-brand-700 bg-brand-50 ring-2 ring-brand-200', 'bg-brand-700'],
  orange: ['border-orange-500 bg-orange-50 ring-2 ring-orange-200', 'bg-orange-500'],
  purple: ['border-violet-500 bg-violet-50 ring-2 ring-violet-200', 'bg-violet-600'],
};

function ModeButton({ active, onClick, title, hint, tone = 'brand', disabled }) {
  const [on, dot] = MODE_TONES[tone];
  return (
    <button
      type="button"
      onClick={onClick}
      disabled={disabled}
      aria-pressed={active}
      className={`rounded-2xl border-2 p-4 text-left transition-all disabled:cursor-not-allowed disabled:opacity-50 ${
        active ? on : 'border-line bg-white hover:-translate-y-0.5 hover:border-brand-600 hover:shadow-md'
      }`}
    >
      <span className="flex items-center gap-2 text-base font-bold text-ink">
        <span className={`h-3.5 w-3.5 rounded-full ${dot}`} />
        {title}
      </span>
      {hint && <span className="mt-1 block text-sm text-ink2">{hint}</span>}
    </button>
  );
}

/** Step 2: Return (photo unclear) · Validate (confirm the level) · Escalate (complex case, technicians only). */
function Decisions({ decision, choose, canEscalate }) {
  const t = useT();
  return (
    <div className={`grid gap-2 ${canEscalate ? 'sm:grid-cols-3' : 'sm:grid-cols-2'}`}>
      <ModeButton active={decision === 'return'} onClick={() => choose('return')} tone="orange" title={t('Return')} hint={t('Photo unclear: the farmer retakes it')} />
      <ModeButton active={decision === 'validate'} onClick={() => choose('validate')} title={t('Validate')} hint={t('Confirm the infestation level')} />
      {canEscalate && (
        <ModeButton active={decision === 'escalate'} onClick={() => choose('escalate')} tone="purple" title={t('Escalate')} hint={t('Complex case: an agriculturist diagnoses it')} />
      )}
    </div>
  );
}

function ReasonForm({ kind, busy, error, onSubmit }) {
  const t = useT();
  const [reason, setReason] = useState('');
  const [attempted, setAttempted] = useState(false);
  const isReturn = kind === 'return';
  const missing = !reason.trim()
    ? [isReturn ? t('Write what the farmer should fix, or pick one of the reasons below.') : t('Write why this case needs an agriculturist.')]
    : !meaningful(reason, isReturn ? 6 : 10)
      ? [isReturn ? t('Write a clear reason the farmer can act on.') : t('Explain the escalation in a sentence the agriculturist can use.')]
      : [];
  const send = () => {
    setAttempted(true);
    if (!missing.length) onSubmit({ action: kind, reason: reason.trim() });
  };
  return (
    <div className="space-y-3">
      <Field
        label={isReturn ? t('What should the farmer fix? *') : t('Why it needs an agriculturist *')}
        hint={
          isReturn
            ? t('The farmer sees this in the app and retakes the photo. The new photo goes through the review again.')
            : t('Only technicians and agriculturists see this. The farmer is told an agriculturist will review it.')
        }
      >
        <textarea className={`input min-h-[88px] ${fieldError(attempted && missing.length)}`} value={reason} onChange={(e) => setReason(e.target.value)} maxLength={1000} />
      </Field>
      {isReturn && (
        <div className="flex flex-wrap gap-2">
          {RETURN_REASONS.map((r) => (
            <button key={r} type="button" onClick={() => setReason(r)} className="rounded-full border border-line bg-white px-3 py-1.5 text-sm text-ink2 hover:border-brand-600">
              {t(r)}
            </button>
          ))}
        </div>
      )}
      {attempted && <MissingNote items={missing} />}
      <ErrorNote message={error} />
      <div className="flex justify-end">
        <Button size="xl" variant={isReturn ? 'secondary' : 'primary'} busy={busy} onClick={send}>
          {isReturn ? t('Return to the farmer') : t('Escalate to an agriculturist')}
        </Button>
      </div>
    </div>
  );
}

function CountEditor({ countable, setCountable, count, setCount, invalid }) {
  const t = useT();
  return (
    <div className="flex flex-wrap items-end gap-4">
      <Field label={t('Count')} className="w-40">
        <input
          type="number"
          min="0"
          max="100000"
          step="1"
          className={`input ${fieldError(invalid)}`}
          value={countable ? count : ''}
          disabled={!countable}
          placeholder={countable ? t('Number seen') : t('Not countable')}
          onChange={(e) => setCount(e.target.value)}
        />
      </Field>
      <label className="flex cursor-pointer items-center gap-2 pb-2 text-sm text-ink">
        <input type="checkbox" className="h-4 w-4 accent-brand-700" checked={!countable} onChange={(e) => setCountable(!e.target.checked)} />
        {t('Not countable (insects too close together or unclear)')}
      </label>
      {invalid && <span className="w-full text-sm font-semibold text-red-600">{t('Enter a whole number, or tick "Not countable".')}</span>}
    </div>
  );
}

const LEVEL_HINTS = { LOW: 'Low infestation', MEDIUM: 'Moderate infestation', HIGH: 'Severe infestation' };

/** The three levels as large colour cards (the colours used on the map and in every report). */
function LevelPicker({ level, suggested, onPick, error }) {
  const t = useT();
  return (
    <div className={`grid gap-3 rounded-2xl sm:grid-cols-3 ${error ? 'p-1 ring-2 ring-red-300' : ''}`}>
      {LEVELS.map((lv) => {
        const on = level === lv;
        const color = LEVEL_COLOR[lv];
        return (
          <button
            key={lv}
            type="button"
            aria-pressed={on}
            onClick={() => onPick(lv)}
            className={`rounded-2xl border-[3px] px-4 py-4 text-left transition-all ${on ? 'text-white shadow-lg' : 'bg-white text-ink hover:-translate-y-0.5 hover:shadow-md'}`}
            style={{ borderColor: color, background: on ? color : undefined }}
          >
            <span className="flex items-center gap-2.5">
              <span className="h-6 w-6 shrink-0 rounded-full ring-2 ring-white/70" style={{ background: on ? '#fff' : color }} />
              <span className="text-xl font-extrabold tracking-wide">{t(lv)}</span>
            </span>
            <span className={`mt-1 block text-sm ${on ? 'text-white/90' : 'text-ink2'}`}>{t(LEVEL_HINTS[lv])}</span>
            {lv === suggested && (
              <span className={`mt-2 inline-block rounded-full px-2 py-0.5 text-[11px] font-bold uppercase ${on ? 'bg-white/25 text-white' : 'bg-canvas text-ink2'}`}>
                {t('Suggested')}
              </span>
            )}
          </button>
        );
      })}
    </div>
  );
}

/** Diagnosis + guidance: required when an agriculturist resolves an escalated case, optional otherwise. */
function NotesFields({ required, isPest, diagnosis, setDiagnosis, guidance, setGuidance, showErrors }) {
  const t = useT();
  const opt = required ? ' *' : ` (${t('optional')})`;
  return (
    <>
      {(required || !isPest) && (
        <Field label={`${t('Diagnosis')}${opt}`}>
          <textarea
            className={`input min-h-[64px] ${fieldError(showErrors && required && !diagnosis.trim())}`}
            value={diagnosis}
            onChange={(e) => setDiagnosis(e.target.value)}
            maxLength={2000}
            placeholder={isPest ? t('e.g. Brown planthopper build-up at the base of the tillers') : t('e.g. Bacterial leaf blight')}
          />
        </Field>
      )}
      <Field
        label={`${isPest && !required ? t('Note to the farmer') : t('Guidance for the farmer')}${opt}`}
        hint={t("Shown on the farmer's record. Describe approaches; the app tells farmers to consult their technician before using any pesticide.")}
      >
        <textarea
          className={`input min-h-[88px] ${fieldError(showErrors && required && !guidance.trim())}`}
          value={guidance}
          onChange={(e) => setGuidance(e.target.value)}
          maxLength={4000}
        />
      </Field>
    </>
  );
}

/** Validate a pest report: damage indicators, the API's suggestion, the reviewer's level. */
function PestValidate({ scan, pest, count, countReady, escalated, busy, error, onSubmit, onAttempt }) {
  const t = useT();
  const [indicators, setIndicators] = useState([]);
  const [picked, setPicked] = useState(null); // null = follow the suggestion
  const [diagnosis, setDiagnosis] = useState('');
  const [guidance, setGuidance] = useState('');
  const [note, setNote] = useState('');
  const [recIds, setRecIds] = useState([]);
  const [attempted, setAttempted] = useState(false);
  const s = useLevelSuggestion({ pest, crop_stage: scan.crop_stage, count, indicators, enabled: countReady && Boolean(pest) });
  const fresh = s.data && s.params?.pest === pest; // not a leftover from the previously chosen pest
  const available = fresh ? s.data.available_indicators : [];
  const suggested = fresh ? s.data.level : null;
  const level = picked || suggested;

  // A different pest has different indicators and thresholds.
  useEffect(() => {
    setIndicators([]);
    setPicked(null);
  }, [pest]);
  useEffect(() => {
    if (s.data) setIndicators((prev) => prev.filter((i) => s.data.available_indicators.includes(i)));
  }, [s.data]);

  const toggle = (i) => setIndicators((prev) => (prev.includes(i) ? prev.filter((x) => x !== i) : [...prev, i]));
  const missing = [
    !pest && t('Step 1: choose the pest.'),
    !countReady && t('Step 1: enter the count, or tick "Not countable".'),
    !level && t('Pick the infestation level: LOW, MEDIUM or HIGH.'),
    escalated && !diagnosis.trim() && t('Write the diagnosis.'),
    escalated && !guidance.trim() && t('Write the guidance for the farmer.'),
    !meaningful(note) && t('Add a reviewer note: what you checked and why you chose this level.'),
    meaningful(note) && [diagnosis.trim(), guidance.trim()].some((x) => x && x.toLowerCase() === note.trim().toLowerCase())
      && t('The reviewer note must be your own note, not a copy of the diagnosis or guidance.'),
  ].filter(Boolean);
  const loadingSuggestion = s.pending && Boolean(pest) && countReady;
  const send = () => {
    setAttempted(true);
    onAttempt();
    if (missing.length || loadingSuggestion) return;
    onSubmit({
      action: 'validate',
      pest,
      countable: count !== null,
      count,
      level,
      damage_indicators: indicators,
      diagnosis: diagnosis.trim(),
      guidance: guidance.trim(),
      reviewer_note: note.trim(),
      recommended_library_ids: recIds,
    });
  };

  return (
    <div className="space-y-4 rounded-xl border border-brand-200 bg-brand-50/50 p-4">
      <p className="text-xs text-ink2">
        {pest ? t(pestLabel(pest)) : t('Pest not chosen')} · {countReady ? t(fmtCount(count)) : t('count missing')} ·{' '}
        {t('crop stage {stage}', { stage: scan.crop_stage ? t(scan.crop_stage) : t('not given') })}. {t('Tick the damage you can see; the suggestion updates as you go.')}
      </p>

      <Field as="div" label={t('Visible damage indicators')}>
        {available.length ? (
          <div className="space-y-1.5">
            {available.map((i) => (
              <label key={i} className="flex cursor-pointer items-start gap-2 text-sm text-ink">
                <input type="checkbox" className="mt-0.5 h-4 w-4 accent-brand-700" checked={indicators.includes(i)} onChange={() => toggle(i)} />
                {s.data?.indicator_labels?.[i] || t(i)}
              </label>
            ))}
          </div>
        ) : (
          <p className="text-xs text-muted">{!pest || !countReady ? t('Finish step 1 first.') : s.error ? t('Indicators unavailable.') : fresh ? t('None listed for this pest.') : t('Loading…')}</p>
        )}
      </Field>

      <div className={`rounded-lg border border-line bg-white p-3 ${countReady && pest ? '' : 'opacity-50'}`}>
        <div className="flex flex-wrap items-center gap-2 text-sm">
          <span className="font-semibold text-ink">{t('Suggested level:')}</span>
          {suggested ? <LevelBadge level={suggested} /> : <span className="text-muted">—</span>}
          {s.pending && pest && countReady && <span className="h-3 w-3 animate-spin rounded-full border-2 border-brand-700 border-r-transparent" />}
        </div>
        {fresh && s.data.reasons.length > 0 && (
          <ul className="mt-2 list-disc space-y-0.5 pl-5 text-xs text-ink2">
            {s.data.reasons.map((r) => (
              <li key={r}>{r}</li>
            ))}
          </ul>
        )}
        {fresh && s.data.provisional && (
          <p className="mt-2 text-xs font-semibold text-orange-700">
            {t('Provisional thresholds: not yet confirmed by an agriculturist. Rely on what you see in the field.')}
          </p>
        )}
        {s.error && <p className="mt-2 text-xs text-red-600">{t("Couldn't load the suggestion ({error}). You can still set the level yourself.", { error: s.error })}</p>}
      </div>

      <Field as="div" label={t('Your level *')}>
        <LevelPicker level={level} suggested={suggested} onPick={setPicked} error={attempted && !level} />
        {picked && suggested && picked !== suggested && (
          <p className="mt-2 text-sm text-orange-700">
            {t("You're overriding the suggestion ({level}). Your level is the one recorded and shown everywhere.", { level: t(suggested) })}{' '}
            <button type="button" className="font-semibold underline" onClick={() => setPicked(null)}>
              {t('Use the suggestion')}
            </button>
          </p>
        )}
      </Field>

      <NotesFields
        required={escalated}
        isPest
        diagnosis={diagnosis}
        setDiagnosis={setDiagnosis}
        guidance={guidance}
        setGuidance={setGuidance}
        showErrors={attempted}
      />
      <ReviewerNoteField value={note} onChange={setNote} invalid={attempted && !meaningful(note)} />
      {pest && pest !== 'other' && <RecommendationPicker pest={pest} value={recIds} onChange={setRecIds} />}

      {attempted && <MissingNote items={missing} />}
      <ErrorNote message={error} />
      <div className="flex flex-wrap items-center justify-end gap-3">
        {loadingSuggestion && <span className="text-sm text-ink2">{t('Updating the suggestion…')}</span>}
        <Button size="xl" busy={busy} disabled={loadingSuggestion} onClick={send}>
          {t('Validate as {level}', { level: level ? t(level) : '…' })}
        </Button>
      </div>
    </div>
  );
}

/** Validate a disease report: no model result; the reviewer sets the level, diagnosis optional unless escalated. */
function DiseaseValidate({ escalated, busy, error, onSubmit }) {
  const t = useT();
  const [level, setLevel] = useState(null);
  const [diagnosis, setDiagnosis] = useState('');
  const [guidance, setGuidance] = useState('');
  const [note, setNote] = useState('');
  const [attempted, setAttempted] = useState(false);
  const missing = [
    !level && t('Pick how bad it is in the field: LOW, MEDIUM or HIGH.'),
    escalated && !diagnosis.trim() && t('Write the diagnosis.'),
    escalated && !guidance.trim() && t('Write the guidance for the farmer.'),
    !meaningful(note) && t('Add a reviewer note: what you checked and why you chose this level.'),
    meaningful(note) && [diagnosis.trim(), guidance.trim()].some((x) => x && x.toLowerCase() === note.trim().toLowerCase())
      && t('The reviewer note must be your own note, not a copy of the diagnosis or guidance.'),
  ].filter(Boolean);
  const send = () => {
    setAttempted(true);
    if (!missing.length) {
      onSubmit({ action: 'validate', level, diagnosis: diagnosis.trim(), guidance: guidance.trim(), reviewer_note: note.trim() });
    }
  };
  return (
    <div className="space-y-4 rounded-xl border border-brand-200 bg-brand-50/50 p-4">
      <Field as="div" label={t('How bad is it in the field? *')}>
        <LevelPicker level={level} onPick={setLevel} error={attempted && !level} />
      </Field>
      <NotesFields
        required={escalated}
        isPest={false}
        diagnosis={diagnosis}
        setDiagnosis={setDiagnosis}
        guidance={guidance}
        setGuidance={setGuidance}
        showErrors={attempted}
      />
      <ReviewerNoteField value={note} onChange={setNote} invalid={attempted && !meaningful(note)} />
      {attempted && <MissingNote items={missing} />}
      <ErrorNote message={error} />
      <div className="flex flex-wrap items-center justify-end gap-3">
        <Button size="xl" busy={busy} onClick={send}>
          {t('Validate as {level}', { level: level ? t(level) : '…' })}
        </Button>
      </div>
    </div>
  );
}

/** Step 1 for a pest report: the model result's pest and count, confirmed or corrected. */
function PestCheck({ ai, pest, setPest, countable, setCountable, count, setCount, countOk, sameAsAi, resetToAi, showErrors }) {
  const t = useT();
  const aiCount = ai.count ?? null;
  const pestMissing = showErrors && !pest;
  return (
    <div className={`space-y-3 rounded-xl border bg-white p-4 transition-colors ${showErrors && (!pest || !countOk) ? 'border-red-300 ring-2 ring-red-100' : 'border-line'}`}>
      <p className="text-sm text-ink2">
        <span className="font-semibold text-orange-700">{t('Model result:')}</span>{' '}
        {ai.pest ? (
          <>
            <b className="text-ink">{ai.pest_name}</b>
            {ai.confidence != null && ` (${fmtConf(ai.confidence)})`} · {t(fmtCount(aiCount))}
          </>
        ) : (
          ai.message || t('No supported pest was named. Choose the pest and enter the count.')
        )}
      </p>
      <div className="flex flex-wrap items-end gap-4">
        <Field label={t('Pest *')} className="w-64">
          <Select value={pest} onChange={setPest} placeholder={t('Choose the pest…')} options={PEST_OPTIONS.map(([v, l]) => [v, t(l)])} className={fieldError(pestMissing)} />
          {pestMissing && <span className="mt-1 block text-sm font-semibold text-red-600">{t('Choose the pest.')}</span>}
        </Field>
        <CountEditor
          countable={countable}
          setCountable={setCountable}
          count={count}
          setCount={setCount}
          invalid={!countOk && (count !== '' || showErrors)}
        />
      </div>
      {sameAsAi ? (
        <p className="text-xs font-semibold text-brand-700">✓ {t('Confirming the model result')}</p>
      ) : (
        pest && (
          <p className="text-xs font-semibold text-orange-700">
            {t('Corrected by you')}
            {ai.pest && (
              <>
                {' · '}
                <button type="button" className="underline" onClick={resetToAi}>
                  {t('Use the model result')}
                </button>
              </>
            )}
          </p>
        )
      )}
    </div>
  );
}

function PestReview({ scan, canEscalate, escalated, action, submit }) {
  const t = useT();
  const ai = scan.ai || {};
  const aiCount = ai.count ?? null;
  const initialCountable = aiCount !== null || !ai.pest;
  const [pest, setPest] = useState(ai.pest || '');
  const [countable, setCountable] = useState(initialCountable);
  const [count, setCount] = useState(aiCount !== null ? String(aiCount) : '');
  const [decision, setDecision] = useState(null);
  // Set once the reviewer tries to validate: step 1 then shows what's missing.
  const [attempted, setAttempted] = useState(false);
  const step1Ref = useRef(null);

  const n = Number(count);
  const countOk = !countable || (count !== '' && Number.isInteger(n) && n >= 0 && n <= 100000);
  const effCount = countable && countOk ? n : null;
  const sameAsAi = Boolean(ai.pest) && pest === ai.pest && countable === (aiCount !== null) && (!countable || n === aiCount);
  const step1Done = Boolean(pest) && countOk;
  const showStep1 = !step1Done && (attempted || decision === 'validate');
  const resetToAi = () => {
    setPest(ai.pest || '');
    setCountable(initialCountable);
    setCount(aiCount !== null ? String(aiCount) : '');
  };
  const choose = (d) => {
    action.setError('');
    setDecision(d);
  };
  const onAttempt = () => {
    setAttempted(true);
    if (!step1Done) step1Ref.current?.scrollIntoView({ behavior: 'smooth', block: 'center' });
  };

  return (
    <div className="space-y-4">
      <div ref={step1Ref}>
        <StepTitle
          n={1}
          hint={t("Confirm the model result's pest and count, or correct them.")}
          error={showStep1 ? (!pest ? t('You skipped this step: choose the pest first.') : t('Enter the count, or tick "Not countable".')) : null}
        >
          {t('Check the result')}
        </StepTitle>
      </div>
      <PestCheck
        ai={ai}
        pest={pest}
        setPest={setPest}
        countable={countable}
        setCountable={setCountable}
        count={count}
        setCount={setCount}
        countOk={countOk}
        sameAsAi={sameAsAi}
        resetToAi={resetToAi}
        showErrors={showStep1}
      />
      <StepTitle n={2}>{t('Decision')}</StepTitle>
      <Decisions decision={decision} choose={choose} canEscalate={canEscalate} />
      {decision === 'validate' && (
        <PestValidate
          scan={scan}
          pest={pest}
          count={effCount}
          countReady={countOk}
          escalated={escalated}
          busy={action.busy}
          error={action.error}
          onSubmit={submit}
          onAttempt={onAttempt}
        />
      )}
      {(decision === 'return' || decision === 'escalate') && <ReasonForm key={decision} kind={decision} busy={action.busy} error={action.error} onSubmit={submit} />}
    </div>
  );
}

function DiseaseReview({ canEscalate, escalated, action, submit }) {
  const t = useT();
  const [decision, setDecision] = useState(null);
  const choose = (d) => {
    action.setError('');
    setDecision(d);
  };
  return (
    <div className="space-y-4">
      <StepTitle n={1} hint={t('There is no model result for disease reports. Look at the photo and the symptoms the farmer described.')}>
        {t('Check the report')}
      </StepTitle>
      <StepTitle n={2}>{t('Decision')}</StepTitle>
      <Decisions decision={decision} choose={choose} canEscalate={canEscalate} />
      {decision === 'validate' && <DiseaseValidate escalated={escalated} busy={action.busy} error={action.error} onSubmit={submit} />}
      {(decision === 'return' || decision === 'escalate') && <ReasonForm key={decision} kind={decision} busy={action.busy} error={action.error} onSubmit={submit} />}
    </div>
  );
}

const DONE = {
  validate: (r, t) =>
    r.report_type === 'pest'
      ? t('Observation #{id} validated: {pest}, {level} infestation.', { id: r.id, pest: r.confirmed?.pest_name || t('pest'), level: r.confirmed?.level || '' })
      : t('Disease report #{id} validated: {level} level.', { id: r.id, level: r.level || '' }),
  return: (r, t) => t('Observation #{id} was returned. The farmer will retake the photo.', { id: r.id }),
  escalate: (r, t) => t('Observation #{id} was escalated to an agriculturist.', { id: r.id }),
};

/**
 * Review of one observation, following the process flow: check the result
 * (confirm or correct), then decide Return / Validate / Escalate. An
 * agriculturist resolving an escalated case records the diagnosis and guidance.
 */
export default function ReviewForm({ scan, viewer, onDone }) {
  const t = useT();
  const action = useAction();
  const canEscalate = viewer.role === 'technician';
  const escalated = scan.status === 'escalated';
  const [confirm, dialog] = useConfirm();
  // A decision notifies the farmer and can't be undone here: ask first.
  const QUESTIONS = {
    validate: ['Validate this observation?', 'The level becomes the official record and the farmer is notified.'],
    return: ['Return it to the farmer?', 'The farmer is asked to take a new photo. This observation stays in the records as returned.'],
    escalate: ['Escalate to an agriculturist?', 'It leaves your queue and goes to the To Be Validated queue.'],
  };
  const submit = async (body) => {
    const [title, message] = QUESTIONS[body.action];
    if (!(await confirm({ title: t(title), message: t(message), confirmLabel: t('Yes, continue') }))) return;
    await action.run(async () => {
      const updated = await api.review(scan.id, body);
      onDone(DONE[body.action](updated, t), updated);
    });
  };
  return (
    <>
      {scan.image_relevance === 'possibly_unrelated' && (
        <div className="mb-4">
          <Notice tone="orange">
            {t('This photo may not show a rice plant or field. Check it before validating, and return it if it is not a photo of the field.')}
          </Notice>
        </div>
      )}
      {scan.report_type === 'pest' ? (
        <PestReview scan={scan} canEscalate={canEscalate} escalated={escalated} action={action} submit={submit} />
      ) : (
        <DiseaseReview canEscalate={canEscalate} escalated={escalated} action={action} submit={submit} />
      )}
      {dialog}
    </>
  );
}
