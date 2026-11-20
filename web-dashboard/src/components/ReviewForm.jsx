import { useEffect, useRef, useState } from 'react';
import { api } from '../api.js';
import { fmtConf, fmtCount, LEVELS, PEST_OPTIONS, pestLabel, useAction, useDebounced } from '../lib.js';
import Icon from './icons.jsx';
import { Button, ErrorNote, Field, LEVEL_COLOR, LevelBadge, Select } from './ui.jsx';

const RETURN_REASONS = [
  'The photo is too blurry. Please take a new, closer photo.',
  "The pest isn't visible in the photo. Please photograph the insects up close.",
  'The photo is too dark. Please retake it in daylight.',
  "The photo doesn't show a rice crop.",
];

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
  if (!items.length) return null;
  return (
    <div role="alert" className="animate-shake rounded-xl border-2 border-red-300 bg-red-50 px-4 py-3 text-sm text-red-800">
      <div className="flex items-center gap-2 font-bold">
        <Icon name="alert" className="h-4 w-4" />
        {items.length === 1 ? 'One thing is missing' : `${items.length} things are missing`}
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
  return (
    <div className={`grid gap-2 ${canEscalate ? 'sm:grid-cols-3' : 'sm:grid-cols-2'}`}>
      <ModeButton active={decision === 'return'} onClick={() => choose('return')} tone="orange" title="Return" hint="Photo unclear: the farmer retakes it" />
      <ModeButton active={decision === 'validate'} onClick={() => choose('validate')} title="Validate" hint="Confirm the infestation level" />
      {canEscalate && (
        <ModeButton active={decision === 'escalate'} onClick={() => choose('escalate')} tone="purple" title="Escalate" hint="Complex case: an agriculturist diagnoses it" />
      )}
    </div>
  );
}

function ReasonForm({ kind, busy, error, onSubmit }) {
  const [reason, setReason] = useState('');
  const [attempted, setAttempted] = useState(false);
  const isReturn = kind === 'return';
  const missing = reason.trim() ? [] : [isReturn ? 'Write what the farmer should fix, or pick one of the reasons below.' : 'Write why this case needs an agriculturist.'];
  const send = () => {
    setAttempted(true);
    if (!missing.length) onSubmit({ action: kind, reason: reason.trim() });
  };
  return (
    <div className="space-y-3">
      <Field
        label={isReturn ? 'What should the farmer fix? *' : 'Why it needs an agriculturist *'}
        hint={
          isReturn
            ? 'The farmer sees this in the app and retakes the photo. The new photo goes through the review again.'
            : 'Only technicians and agriculturists see this. The farmer is told an agriculturist will review it.'
        }
      >
        <textarea className={`input min-h-[88px] ${fieldError(attempted && missing.length)}`} value={reason} onChange={(e) => setReason(e.target.value)} maxLength={1000} />
      </Field>
      {isReturn && (
        <div className="flex flex-wrap gap-2">
          {RETURN_REASONS.map((r) => (
            <button key={r} type="button" onClick={() => setReason(r)} className="rounded-full border border-line bg-white px-3 py-1.5 text-sm text-ink2 hover:border-brand-600">
              {r}
            </button>
          ))}
        </div>
      )}
      {attempted && <MissingNote items={missing} />}
      <ErrorNote message={error} />
      <div className="flex justify-end">
        <Button size="xl" variant={isReturn ? 'secondary' : 'primary'} busy={busy} onClick={send}>
          {isReturn ? 'Return to the farmer' : 'Escalate to an agriculturist'}
        </Button>
      </div>
    </div>
  );
}

function CountEditor({ countable, setCountable, count, setCount, invalid }) {
  return (
    <div className="flex flex-wrap items-end gap-4">
      <Field label="Count" className="w-40">
        <input
          type="number"
          min="0"
          max="100000"
          step="1"
          className={`input ${fieldError(invalid)}`}
          value={countable ? count : ''}
          disabled={!countable}
          placeholder={countable ? 'Number seen' : 'Not countable'}
          onChange={(e) => setCount(e.target.value)}
        />
      </Field>
      <label className="flex cursor-pointer items-center gap-2 pb-2 text-sm text-ink">
        <input type="checkbox" className="h-4 w-4 accent-brand-700" checked={!countable} onChange={(e) => setCountable(!e.target.checked)} />
        Not countable (insects too close together or unclear)
      </label>
      {invalid && <span className="w-full text-sm font-semibold text-red-600">Enter a whole number, or tick "Not countable".</span>}
    </div>
  );
}

const LEVEL_HINTS = { LOW: 'Low infestation', MEDIUM: 'Moderate infestation', HIGH: 'Severe infestation' };

/** The three levels as large colour cards (the colours used on the map and in every report). */
function LevelPicker({ level, suggested, onPick, error }) {
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
              <span className="text-xl font-extrabold tracking-wide">{lv}</span>
            </span>
            <span className={`mt-1 block text-sm ${on ? 'text-white/90' : 'text-ink2'}`}>{LEVEL_HINTS[lv]}</span>
            {lv === suggested && (
              <span className={`mt-2 inline-block rounded-full px-2 py-0.5 text-[11px] font-bold uppercase ${on ? 'bg-white/25 text-white' : 'bg-canvas text-ink2'}`}>
                Suggested
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
  const opt = required ? ' *' : ' (optional)';
  return (
    <>
      {(required || !isPest) && (
        <Field label={`Diagnosis${opt}`}>
          <textarea
            className={`input min-h-[64px] ${fieldError(showErrors && required && !diagnosis.trim())}`}
            value={diagnosis}
            onChange={(e) => setDiagnosis(e.target.value)}
            maxLength={2000}
            placeholder={isPest ? 'e.g. Brown planthopper build-up at the base of the tillers' : 'e.g. Bacterial leaf blight'}
          />
        </Field>
      )}
      <Field
        label={`${isPest && !required ? 'Note to the farmer' : 'Guidance for the farmer'}${opt}`}
        hint="Shown on the farmer's record. Describe approaches; the app tells farmers to consult their technician before using any pesticide."
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
  const [indicators, setIndicators] = useState([]);
  const [picked, setPicked] = useState(null); // null = follow the suggestion
  const [diagnosis, setDiagnosis] = useState('');
  const [guidance, setGuidance] = useState('');
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
    !pest && 'Step 1: choose the pest.',
    !countReady && 'Step 1: enter the count, or tick "Not countable".',
    !level && 'Pick the infestation level: LOW, MEDIUM or HIGH.',
    escalated && !diagnosis.trim() && 'Write the diagnosis.',
    escalated && !guidance.trim() && 'Write the guidance for the farmer.',
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
    });
  };

  return (
    <div className="space-y-4 rounded-xl border border-brand-200 bg-brand-50/50 p-4">
      <p className="text-xs text-ink2">
        {pest ? pestLabel(pest) : 'Pest not chosen'} · {countReady ? fmtCount(count) : 'count missing'} · crop stage {scan.crop_stage || 'not given'}. Tick
        the damage you can see; the suggestion updates as you go.
      </p>

      <Field as="div" label="Visible damage indicators">
        {available.length ? (
          <div className="space-y-1.5">
            {available.map((i) => (
              <label key={i} className="flex cursor-pointer items-start gap-2 text-sm text-ink">
                <input type="checkbox" className="mt-0.5 h-4 w-4 accent-brand-700" checked={indicators.includes(i)} onChange={() => toggle(i)} />
                {i}
              </label>
            ))}
          </div>
        ) : (
          <p className="text-xs text-muted">{!pest || !countReady ? 'Finish step 1 first.' : s.error ? 'Indicators unavailable.' : fresh ? 'None listed for this pest.' : 'Loading…'}</p>
        )}
      </Field>

      <div className={`rounded-lg border border-line bg-white p-3 ${countReady && pest ? '' : 'opacity-50'}`}>
        <div className="flex flex-wrap items-center gap-2 text-sm">
          <span className="font-semibold text-ink">Suggested level:</span>
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
        {s.error && <p className="mt-2 text-xs text-red-600">Couldn't load the suggestion ({s.error}). You can still set the level yourself.</p>}
      </div>

      <Field as="div" label="Your level *">
        <LevelPicker level={level} suggested={suggested} onPick={setPicked} error={attempted && !level} />
        {picked && suggested && picked !== suggested && (
          <p className="mt-2 text-sm text-orange-700">
            You're overriding the suggestion ({suggested}). Your level is the one recorded and shown everywhere.{' '}
            <button type="button" className="font-semibold underline" onClick={() => setPicked(null)}>
              Use the suggestion
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

      {attempted && <MissingNote items={missing} />}
      <ErrorNote message={error} />
      <div className="flex flex-wrap items-center justify-end gap-3">
        {loadingSuggestion && <span className="text-sm text-ink2">Updating the suggestion…</span>}
        <Button size="xl" busy={busy} disabled={loadingSuggestion} onClick={send}>
          Validate as {level || '…'}
        </Button>
      </div>
    </div>
  );
}

/** Validate a disease report: no model result; the reviewer sets the level, diagnosis optional unless escalated. */
function DiseaseValidate({ escalated, busy, error, onSubmit }) {
  const [level, setLevel] = useState(null);
  const [diagnosis, setDiagnosis] = useState('');
  const [guidance, setGuidance] = useState('');
  const [attempted, setAttempted] = useState(false);
  const missing = [
    !level && 'Pick how bad it is in the field: LOW, MEDIUM or HIGH.',
    escalated && !diagnosis.trim() && 'Write the diagnosis.',
    escalated && !guidance.trim() && 'Write the guidance for the farmer.',
  ].filter(Boolean);
  const send = () => {
    setAttempted(true);
    if (!missing.length) onSubmit({ action: 'validate', level, diagnosis: diagnosis.trim(), guidance: guidance.trim() });
  };
  return (
    <div className="space-y-4 rounded-xl border border-brand-200 bg-brand-50/50 p-4">
      <Field as="div" label="How bad is it in the field? *">
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
      {attempted && <MissingNote items={missing} />}
      <ErrorNote message={error} />
      <div className="flex flex-wrap items-center justify-end gap-3">
        <Button size="xl" busy={busy} onClick={send}>
          Validate as {level || '…'}
        </Button>
      </div>
    </div>
  );
}

/** Step 1 for a pest report: the model result's pest and count, confirmed or corrected. */
function PestCheck({ ai, pest, setPest, countable, setCountable, count, setCount, countOk, sameAsAi, resetToAi, showErrors }) {
  const aiCount = ai.count ?? null;
  const pestMissing = showErrors && !pest;
  return (
    <div className={`space-y-3 rounded-xl border bg-white p-4 transition-colors ${showErrors && (!pest || !countOk) ? 'border-red-300 ring-2 ring-red-100' : 'border-line'}`}>
      <p className="text-sm text-ink2">
        <span className="font-semibold text-orange-700">Model result:</span>{' '}
        {ai.pest ? (
          <>
            <b className="text-ink">{ai.pest_name}</b>
            {ai.confidence != null && ` (${fmtConf(ai.confidence)})`} · {fmtCount(aiCount)}
          </>
        ) : (
          ai.message || 'No supported pest was named. Choose the pest and enter the count.'
        )}
      </p>
      <div className="flex flex-wrap items-end gap-4">
        <Field label="Pest *" className="w-64">
          <Select value={pest} onChange={setPest} placeholder="Choose the pest…" options={PEST_OPTIONS} className={fieldError(pestMissing)} />
          {pestMissing && <span className="mt-1 block text-sm font-semibold text-red-600">Choose the pest.</span>}
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
        <p className="text-xs font-semibold text-brand-700">✓ Confirming the model result</p>
      ) : (
        pest && (
          <p className="text-xs font-semibold text-orange-700">
            Corrected by you
            {ai.pest && (
              <>
                {' · '}
                <button type="button" className="underline" onClick={resetToAi}>
                  Use the model result
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
          hint="Confirm the model result's pest and count, or correct them."
          error={showStep1 ? (!pest ? 'You skipped this step: choose the pest first.' : 'Enter the count, or tick "Not countable".') : null}
        >
          Check the result
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
      <StepTitle n={2}>Decision</StepTitle>
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
  const [decision, setDecision] = useState(null);
  const choose = (d) => {
    action.setError('');
    setDecision(d);
  };
  return (
    <div className="space-y-4">
      <StepTitle n={1} hint="There is no model result for disease reports. Look at the photo and the symptoms the farmer described.">
        Check the report
      </StepTitle>
      <StepTitle n={2}>Decision</StepTitle>
      <Decisions decision={decision} choose={choose} canEscalate={canEscalate} />
      {decision === 'validate' && <DiseaseValidate escalated={escalated} busy={action.busy} error={action.error} onSubmit={submit} />}
      {(decision === 'return' || decision === 'escalate') && <ReasonForm key={decision} kind={decision} busy={action.busy} error={action.error} onSubmit={submit} />}
    </div>
  );
}

const DONE = {
  validate: (r) =>
    r.report_type === 'pest'
      ? `Observation #${r.id} validated: ${r.confirmed?.pest_name || 'pest'}, ${r.confirmed?.level || ''} infestation.`
      : `Disease report #${r.id} validated: ${r.level || ''} level.`,
  return: (r) => `Observation #${r.id} was returned. The farmer will retake the photo.`,
  escalate: (r) => `Observation #${r.id} was escalated to an agriculturist.`,
};

/**
 * Review of one observation, following the process flow: check the result
 * (confirm or correct), then decide Return / Validate / Escalate. An
 * agriculturist resolving an escalated case records the diagnosis and guidance.
 */
export default function ReviewForm({ scan, viewer, onDone }) {
  const action = useAction();
  const canEscalate = viewer.role === 'technician';
  const escalated = scan.status === 'escalated';
  const submit = (body) =>
    action.run(async () => {
      const updated = await api.review(scan.id, body);
      onDone(DONE[body.action](updated), updated);
    });
  return scan.report_type === 'pest' ? (
    <PestReview scan={scan} canEscalate={canEscalate} escalated={escalated} action={action} submit={submit} />
  ) : (
    <DiseaseReview canEscalate={canEscalate} escalated={escalated} action={action} submit={submit} />
  );
}
