import { forwardRef, useCallback, useEffect, useId, useRef, useState } from 'react';
import { useT } from '../i18n/index.jsx';

// ---------------------------------------------------------------- layout

export function PageHeader({ title, description, actions, area }) {
  return (
    <div className="mb-6 flex flex-wrap items-end justify-between gap-4">
      <div className="min-w-0">
        <h1 className="text-2xl font-bold tracking-tight text-ink">{title}</h1>
        {description && <p className="mt-1 max-w-3xl text-sm text-ink2">{description}</p>}
        {area !== undefined && area !== null && <ScopeNote area={area} />}
      </div>
      {actions && <div className="flex flex-wrap items-center gap-2">{actions}</div>}
    </div>
  );
}

/** Shown to technicians: their data is limited to their coverage area. */
export function ScopeNote({ area }) {
  const t = useT();
  return (
    <div className="mt-2 inline-flex items-center gap-2 rounded-full bg-brand-100 px-3 py-1 text-xs font-semibold text-brand-900">
      <span className="h-1.5 w-1.5 rounded-full bg-brand-700" />
      {area ? t('Your coverage: {area}', { area }) : t('No coverage area on your account yet — ask an agriculturist to set one.')}
    </div>
  );
}

export function Panel({ title, subtitle, actions, children, className = '', bodyClassName = 'p-5' }) {
  return (
    <section className={`rounded-2xl border border-line bg-white shadow-sm ${className}`}>
      {(title || actions) && (
        <header className="flex flex-wrap items-start justify-between gap-3 border-b border-line px-5 py-4">
          <div>
            {title && <h2 className="text-base font-bold text-ink">{title}</h2>}
            {subtitle && <p className="mt-0.5 text-xs text-ink2">{subtitle}</p>}
          </div>
          {actions}
        </header>
      )}
      <div className={bodyClassName}>{children}</div>
    </section>
  );
}

const STAT_TONES = {
  default: 'text-ink',
  brand: 'text-brand-700',
  green: 'text-emerald-600',
  orange: 'text-orange-600',
  red: 'text-red-600',
  muted: 'text-ink2',
};

export function Stat({ label, value, tone = 'default', hint }) {
  return (
    <div className="rounded-2xl border border-line bg-white p-4 shadow-sm">
      <div className="text-xs font-semibold uppercase tracking-wide text-ink2">{label}</div>
      <div className={`mt-1 text-2xl font-bold tabular-nums ${STAT_TONES[tone]}`}>{value}</div>
      {hint && <div className="mt-1 text-xs text-muted">{hint}</div>}
    </div>
  );
}

// ---------------------------------------------------------------- badges

const BADGE_TONES = {
  gray: 'bg-gray-100 text-gray-700',
  green: 'bg-emerald-50 text-emerald-700 ring-emerald-200',
  orange: 'bg-orange-50 text-orange-700 ring-orange-200',
  red: 'bg-red-50 text-red-700 ring-red-200',
  brand: 'bg-brand-100 text-brand-900 ring-brand-200',
  blue: 'bg-sky-50 text-sky-700 ring-sky-200',
  purple: 'bg-violet-50 text-violet-700 ring-violet-200',
};

export function Badge({ tone = 'gray', children, title }) {
  return (
    <span
      title={title}
      className={`inline-flex items-center whitespace-nowrap rounded-full px-2 py-0.5 text-xs font-semibold ring-1 ring-inset ring-transparent ${BADGE_TONES[tone]}`}
    >
      {children}
    </span>
  );
}

export const LEVEL_TONE = { LOW: 'green', MEDIUM: 'orange', HIGH: 'red' };
export const LEVEL_COLOR = { LOW: '#10B981', MEDIUM: '#E67E22', HIGH: '#E63946' };

export function LevelBadge({ level }) {
  const t = useT();
  if (!level) return <span className="text-muted">—</span>;
  return <Badge tone={LEVEL_TONE[level]}>{t(level)}</Badge>;
}

// The two review queues are the statuses pending ("Not Validated", initial
// review) and escalated ("To Be Validated", agriculturist); no extra statuses.
const STATUS = {
  pending: ['orange', 'Not Validated'],
  validated: ['green', 'Validated'],
  returned: ['gray', 'Returned to farmer'],
  escalated: ['purple', 'To Be Validated'],
  // The model confidently found no insect on a clear photo (photo removed).
  no_pests: ['blue', 'No pests found'],
};
/** [value, English label] pairs; translate the label where it is shown. */
export const STATUS_OPTIONS = Object.entries(STATUS).map(([k, [, label]]) => [k, label]);

export function StatusBadge({ status }) {
  const t = useT();
  const [tone, label] = STATUS[status] || ['gray', status || '—'];
  return <Badge tone={tone}>{t(label)}</Badge>;
}

const PATTERN = {
  increasing: ['red', '↑ Increasing'],
  decreasing: ['green', '↓ Decreasing'],
  stable: ['gray', '→ Stable'],
};

export function PatternBadge({ status }) {
  const t = useT();
  const [tone, label] = PATTERN[status] || ['gray', status];
  return <Badge tone={tone}>{t(label)}</Badge>;
}

const OUTCOME = {
  improved: ['green', 'Improved'],
  'no change': ['gray', 'No change'],
  worsened: ['red', 'Worsened'],
  worse: ['red', 'Worsened'], // older API builds
  'not comparable': ['gray', 'Not comparable'],
  'awaiting follow-up': ['blue', 'Awaiting follow-up'],
  overdue: ['orange', 'Follow-up overdue'],
  'follow-up in review': ['purple', 'Follow-up in review'],
};

export function OutcomeBadge({ outcome }) {
  const t = useT();
  const [tone, label] = OUTCOME[outcome] || ['gray', outcome];
  return <Badge tone={tone}>{t(label)}</Badge>;
}

/** The relevance screen's flag: the photo may not show a crop (a technician checks it). */
export function RelevanceBadge({ relevance }) {
  const t = useT();
  if (relevance !== 'possibly_unrelated') return null;
  return (
    <span title={t('This photo may not show a rice plant or field. A technician will check it.')}>
      <Badge tone="orange">{t('Possibly unrelated photo')}</Badge>
    </span>
  );
}

export function ReportTypeBadge({ type }) {
  const t = useT();
  return type === 'disease' ? <Badge tone="purple">{t('Disease')}</Badge> : <Badge tone="brand">{t('Pest')}</Badge>;
}

/** Horizontal bar split into LOW / MEDIUM / HIGH shares. */
export function LevelBar({ LOW = 0, MEDIUM = 0, HIGH = 0, className = 'h-2' }) {
  const t = useT();
  const total = LOW + MEDIUM + HIGH;
  if (!total) return <div className={`w-full rounded-full bg-gray-100 ${className}`} />;
  return (
    <div
      className={`flex w-full overflow-hidden rounded-full bg-gray-100 ${className}`}
      title={`${t('LOW')} ${LOW} · ${t('MEDIUM')} ${MEDIUM} · ${t('HIGH')} ${HIGH}`}
    >
      {[['LOW', LOW], ['MEDIUM', MEDIUM], ['HIGH', HIGH]].map(([k, v]) =>
        v ? <div key={k} style={{ width: `${(v / total) * 100}%`, background: LEVEL_COLOR[k] }} /> : null,
      )}
    </div>
  );
}

// ---------------------------------------------------------------- controls

const BUTTONS = {
  primary: 'bg-brand-700 text-white hover:bg-brand-800 disabled:bg-brand-200',
  secondary: 'border border-line bg-white text-ink hover:bg-canvas disabled:text-muted',
  ghost: 'text-ink2 hover:bg-canvas hover:text-ink disabled:text-muted',
  danger: 'border border-red-200 bg-white text-red-700 hover:bg-red-50 disabled:text-red-300',
  destructive: 'bg-red-600 text-white hover:bg-red-700 disabled:bg-red-300',
};

const SIZES = {
  sm: 'px-3 py-1.5 text-xs',
  md: 'px-4 py-2 text-sm',
  lg: 'px-5 py-2.5 text-sm',
  xl: 'px-6 py-3.5 text-base',
};

export const Button = forwardRef(function Button(
  { variant = 'primary', size = 'md', busy = false, className = '', children, ...props },
  ref,
) {
  const sizing = SIZES[size] || SIZES.md;
  return (
    <button
      ref={ref}
      type="button"
      {...props}
      disabled={props.disabled || busy}
      className={`inline-flex items-center justify-center gap-2 whitespace-nowrap rounded-lg font-semibold transition-colors disabled:cursor-not-allowed ${sizing} ${BUTTONS[variant]} ${className}`}
    >
      {busy && <span className="h-3.5 w-3.5 animate-spin rounded-full border-2 border-current border-r-transparent" />}
      {children}
    </button>
  );
});

/** Use as="div" around groups of buttons (a <label> forwards clicks to its first button). */
export function Field({ label, hint, children, className = '', as: Tag = 'label' }) {
  return (
    <Tag className={`block ${className}`}>
      {label && <span className="label">{label}</span>}
      {children}
      {hint && <span className="mt-1 block text-xs text-muted">{hint}</span>}
    </Tag>
  );
}

export function Select({ value, onChange, options, placeholder, className = '', ...props }) {
  return (
    <select value={value} onChange={(e) => onChange(e.target.value)} className={`input ${className}`} {...props}>
      {placeholder !== undefined && <option value="">{placeholder}</option>}
      {options.map((o) => {
        const [v, l] = Array.isArray(o) ? o : [o, o];
        return (
          <option key={v} value={v}>
            {l}
          </option>
        );
      })}
    </select>
  );
}

/** Pill tabs used as a filter (e.g. All / Increasing / Decreasing). */
export function Segmented({ value, onChange, options }) {
  return (
    <div className="inline-flex flex-wrap gap-1 rounded-xl border border-line bg-white p-1">
      {options.map(([v, label]) => (
        <button
          key={v}
          type="button"
          onClick={() => onChange(v)}
          className={`rounded-lg px-3 py-1.5 text-xs font-semibold ${
            value === v ? 'bg-brand-700 text-white' : 'text-ink2 hover:bg-canvas'
          }`}
        >
          {label}
        </button>
      ))}
    </div>
  );
}

/** Multi-select as toggle chips. Nothing selected is shown with `noneLabel`. */
export function CheckChips({ value, onChange, options, noneLabel }) {
  const toggle = (v) => onChange(value.includes(v) ? value.filter((x) => x !== v) : [...value, v]);
  return (
    <div className="flex flex-wrap items-center gap-2">
      {options.map((o) => {
        const [v, label] = Array.isArray(o) ? o : [o, o];
        const on = value.includes(v);
        return (
          <button
            key={v}
            type="button"
            aria-pressed={on}
            onClick={() => toggle(v)}
            className={`rounded-full border px-3 py-1 text-xs font-semibold transition-colors ${
              on ? 'border-brand-700 bg-brand-700 text-white' : 'border-line bg-white text-ink2 hover:border-brand-600'
            }`}
          >
            {label}
          </button>
        );
      })}
      {noneLabel && !value.length && <span className="text-xs text-muted">{noneLabel}</span>}
    </div>
  );
}

/** Free-text tags (e.g. barangay names). Enter or comma adds one; paste a comma list. */
export function ChipsInput({ value, onChange, placeholder, disabled, suggestions = [] }) {
  const tr = useT();
  const [draft, setDraft] = useState('');
  const listId = useId();
  const add = (text) => {
    const seen = new Set(value.map((v) => v.toLowerCase()));
    const next = [...value];
    for (const part of text.split(',')) {
      const t = part.trim();
      if (t && !seen.has(t.toLowerCase())) {
        seen.add(t.toLowerCase());
        next.push(t);
      }
    }
    if (next.length !== value.length) onChange(next);
    setDraft('');
  };
  return (
    <div className={`flex min-h-[38px] flex-wrap items-center gap-1.5 rounded-lg border border-line bg-white px-2 py-1.5 focus-within:border-brand-600 focus-within:ring-2 focus-within:ring-brand-100 ${disabled ? 'bg-canvas' : ''}`}>
      {value.map((v) => (
        <span key={v} className="inline-flex items-center gap-1 rounded-full bg-brand-100 px-2 py-0.5 text-xs font-semibold text-brand-900">
          {v}
          {!disabled && (
            <button type="button" aria-label={tr('Remove {name}', { name: v })} className="text-brand-700 hover:text-red-600" onClick={() => onChange(value.filter((x) => x !== v))}>
              ×
            </button>
          )}
        </span>
      ))}
      <input
        className="min-w-[120px] flex-1 border-0 bg-transparent px-1 py-0.5 text-sm text-ink placeholder:text-muted focus:outline-none"
        list={suggestions.length ? listId : undefined}
        value={draft}
        disabled={disabled}
        placeholder={value.length ? '' : placeholder}
        onChange={(e) => (e.target.value.includes(',') ? add(e.target.value) : setDraft(e.target.value))}
        onKeyDown={(e) => {
          if (e.key === 'Enter') {
            e.preventDefault();
            add(draft);
          } else if (e.key === 'Backspace' && !draft && value.length) {
            onChange(value.slice(0, -1));
          }
        }}
        onBlur={() => draft.trim() && add(draft)}
      />
      {suggestions.length > 0 && (
        <datalist id={listId}>
          {suggestions.map((s) => (
            <option key={s} value={s} />
          ))}
        </datalist>
      )}
    </div>
  );
}

// ---------------------------------------------------------------- states

export function Loading({ label }) {
  const t = useT();
  return (
    <div className="flex items-center gap-3 p-8 text-sm text-ink2">
      <span className="h-4 w-4 animate-spin rounded-full border-2 border-brand-700 border-r-transparent" />
      {label ?? t('Loading…')}
    </div>
  );
}

/** Error box. Known server messages are shown in the chosen language. */
export function ErrorNote({ message, onRetry }) {
  const t = useT();
  if (!message) return null;
  return (
    <div className="flex flex-wrap items-center justify-between gap-3 rounded-xl border border-red-200 bg-red-50 px-4 py-3 text-sm text-red-700">
      <span>{t(message)}</span>
      {onRetry && (
        <Button variant="danger" size="sm" onClick={onRetry}>
          {t('Try again')}
        </Button>
      )}
    </div>
  );
}

export function Notice({ children, tone = 'brand' }) {
  const tones = {
    brand: 'border-brand-200 bg-brand-50 text-brand-900',
    orange: 'border-orange-200 bg-orange-50 text-orange-800',
    red: 'border-red-200 bg-red-50 text-red-800',
    gray: 'border-line bg-white text-ink2',
  };
  return <div className={`rounded-xl border px-4 py-3 text-sm ${tones[tone]}`}>{children}</div>;
}

export function Empty({ title, children }) {
  return (
    <div className="px-6 py-12 text-center">
      <div className="text-sm font-semibold text-ink">{title}</div>
      {children && <div className="mx-auto mt-1 max-w-md text-sm text-ink2">{children}</div>}
    </div>
  );
}

// ---------------------------------------------------------------- table

/**
 * columns: [{ key, label, render?(row), className?, align? }]
 * Rows are clickable when onRowClick is given.
 */
export function Table({ columns, rows, rowKey = 'id', onRowClick, empty }) {
  const t = useT();
  return (
    <div className="overflow-x-auto">
      <table className="w-full text-sm">
        <thead className="border-b border-line bg-canvas/60">
          <tr>
            {columns.map((c) => (
              <th key={c.key} className={`th ${c.align === 'right' ? 'text-right' : ''} ${c.headClassName || ''}`}>
                {c.label}
              </th>
            ))}
          </tr>
        </thead>
        <tbody>
          {rows.map((row) => (
            <tr
              key={row[rowKey]}
              onClick={onRowClick ? () => onRowClick(row) : undefined}
              className={`border-b border-line/70 last:border-0 ${onRowClick ? 'cursor-pointer hover:bg-brand-50/60' : ''}`}
            >
              {columns.map((c) => (
                <td key={c.key} className={`td ${c.align === 'right' ? 'text-right tabular-nums' : ''} ${c.className || ''}`}>
                  {c.render ? c.render(row) : row[c.key]}
                </td>
              ))}
            </tr>
          ))}
        </tbody>
      </table>
      {!rows.length && (empty || <Empty title={t('Nothing to show')} />)}
    </div>
  );
}

// ---------------------------------------------------------------- drawer

export function Drawer({ open, onClose, title, subtitle, children, width = 'max-w-2xl' }) {
  const t = useT();
  useEffect(() => {
    if (!open) return undefined;
    const onKey = (e) => e.key === 'Escape' && onClose();
    window.addEventListener('keydown', onKey);
    const prev = document.body.style.overflow;
    document.body.style.overflow = 'hidden';
    return () => {
      window.removeEventListener('keydown', onKey);
      document.body.style.overflow = prev;
    };
  }, [open, onClose]);
  if (!open) return null;
  return (
    <div className="fixed inset-0 z-[2000] flex justify-end">
      <div className="absolute inset-0 bg-ink/40" onClick={onClose} />
      <aside role="dialog" aria-modal="true" className={`relative flex h-full w-full ${width} flex-col bg-canvas shadow-2xl`}>
        <header className="flex items-start justify-between gap-4 border-b border-line bg-white px-6 py-4">
          <div className="min-w-0">
            <h2 className="truncate text-lg font-bold text-ink">{title}</h2>
            {subtitle && <div className="mt-0.5 text-sm text-ink2">{subtitle}</div>}
          </div>
          <button
            type="button"
            onClick={onClose}
            aria-label={t('Close')}
            className="rounded-lg p-2 text-ink2 hover:bg-canvas hover:text-ink"
          >
            <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round">
              <path d="M18 6 6 18M6 6l12 12" />
            </svg>
          </button>
        </header>
        <div className="flex-1 overflow-y-auto px-6 py-5">{children}</div>
      </aside>
    </div>
  );
}


// ---------------------------------------------------------------- confirmation dialog

/**
 * Asks before a destructive or consequential action. `danger` styles the
 * confirm button red. `children` can add details (e.g. what will be lost).
 * Escape or the backdrop cancels; focus starts on Cancel.
 */
export function ConfirmDialog({ open, title, message, confirmLabel, cancelLabel, danger = false, busy = false,
  onConfirm, onCancel, children }) {
  const t = useT();
  const cancelRef = useRef(null);
  useEffect(() => {
    if (!open) return undefined;
    cancelRef.current?.focus();
    const onKey = (e) => e.key === 'Escape' && !busy && onCancel();
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [open, busy, onCancel]);
  if (!open) return null;
  return (
    <div className="fixed inset-0 z-[3000] flex items-center justify-center p-4">
      <div className="absolute inset-0 bg-ink/40" onClick={() => !busy && onCancel()} />
      <div
        role="alertdialog"
        aria-modal="true"
        aria-labelledby="confirm-title"
        className="relative w-full max-w-md rounded-2xl bg-white p-6 shadow-2xl"
      >
        <h2 id="confirm-title" className="text-lg font-bold text-ink">{title}</h2>
        {message && <p className="mt-2 text-sm text-ink2">{message}</p>}
        {children && <div className="mt-3 text-sm text-ink2">{children}</div>}
        <div className="mt-6 flex flex-wrap justify-end gap-2">
          <Button ref={cancelRef} variant="secondary" onClick={onCancel} disabled={busy}>
            {cancelLabel || t('Cancel')}
          </Button>
          <Button variant={danger ? 'destructive' : 'primary'} onClick={onConfirm} disabled={busy}>
            {busy ? t('Please wait…') : confirmLabel || t('Confirm')}
          </Button>
        </div>
      </div>
    </div>
  );
}

/** `const [confirm, dialog] = useConfirm();  if (await confirm({title, message, danger})) ...` */
export function useConfirm() {
  const [state, setState] = useState(null);
  const confirm = useCallback(
    (opts) => new Promise((resolve) => setState({ ...opts, resolve })),
    [],
  );
  const close = (answer) => {
    state?.resolve(answer);
    setState(null);
  };
  const dialog = (
    <ConfirmDialog open={!!state} {...(state || {})} onConfirm={() => close(true)} onCancel={() => close(false)} />
  );
  return [confirm, dialog];
}

// ---------------------------------------------------------------- pager

/** Server-side paging controls: "1-50 of 230" with previous/next. */
export function Pager({ total, limit, offset, onChange, loading = false }) {
  const t = useT();
  if (!total || total <= limit) {
    return total ? <div className="px-4 py-3 text-xs text-muted">{t('{n} shown', { n: total })}</div> : null;
  }
  const first = offset + 1;
  const last = Math.min(offset + limit, total);
  return (
    <div className="flex flex-wrap items-center justify-between gap-2 border-t border-line px-4 py-3 text-sm">
      <span className="text-ink2">{t('{first}–{last} of {total}', { first, last, total })}</span>
      <div className="flex gap-2">
        <Button variant="secondary" size="sm" disabled={loading || offset === 0}
          onClick={() => onChange(Math.max(0, offset - limit))}>
          {t('Previous')}
        </Button>
        <Button variant="secondary" size="sm" disabled={loading || last >= total}
          onClick={() => onChange(offset + limit)}>
          {t('Next')}
        </Button>
      </div>
    </div>
  );
}
