import { useCallback, useEffect, useRef, useState } from 'react';
import { currentLocale, translate } from './i18n/index.jsx';

// ---------------------------------------------------------------- data hooks

/** Runs `fn` whenever `deps` change. Keeps the last data while reloading. */
export function useAsync(fn, deps = []) {
  const [state, setState] = useState({ data: null, error: '', loading: true });
  const [tick, setTick] = useState(0);
  useEffect(() => {
    let alive = true;
    setState((s) => ({ ...s, loading: true, error: '' }));
    fn()
      .then((data) => alive && setState({ data, error: '', loading: false }))
      .catch((e) => alive && setState((s) => ({ data: s.data, error: e.message, loading: false })));
    return () => {
      alive = false;
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [...deps, tick]);
  const reload = useCallback(() => setTick((t) => t + 1), []);
  return { ...state, reload };
}

export function useDebounced(value, ms = 300) {
  const [debounced, setDebounced] = useState(value);
  useEffect(() => {
    const t = setTimeout(() => setDebounced(value), ms);
    return () => clearTimeout(t);
  }, [value, ms]);
  return debounced;
}

/** Calls `fn` every `ms` while the tab is visible. */
export function useInterval(fn, ms) {
  const ref = useRef(fn);
  ref.current = fn;
  useEffect(() => {
    const t = setInterval(() => document.visibilityState === 'visible' && ref.current(), ms);
    return () => clearInterval(t);
  }, [ms]);
}

/** False while the browser reports no network connection. */
export function useOnline() {
  const [online, setOnline] = useState(() => (typeof navigator === 'undefined' ? true : navigator.onLine !== false));
  useEffect(() => {
    const up = () => setOnline(true);
    const down = () => setOnline(false);
    window.addEventListener('online', up);
    window.addEventListener('offline', down);
    return () => {
      window.removeEventListener('online', up);
      window.removeEventListener('offline', down);
    };
  }, []);
  return online;
}

/** Wraps an async action with busy/error state for buttons and forms. */
export function useAction() {
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  const alive = useRef(true);
  useEffect(() => {
    alive.current = true; // StrictMode mounts twice in dev
    return () => {
      alive.current = false;
    };
  }, []);
  const run = useCallback(async (fn) => {
    setBusy(true);
    setError('');
    try {
      return await fn();
    } catch (e) {
      if (alive.current) setError(e.message);
      return undefined;
    } finally {
      if (alive.current) setBusy(false);
    }
  }, []);
  return { busy, error, setError, run };
}

// ---------------------------------------------------------------- formatting

// Dates follow the chosen language (Filipino month names for Filipino and
// Kinaray-a). Formatters are made once per language.
const formatters = new Map();
function fmt(kind) {
  const key = `${currentLocale()}:${kind}`;
  if (!formatters.has(key)) {
    const options =
      kind === 'date'
        ? { month: 'short', day: 'numeric', year: 'numeric' }
        : { month: 'short', day: 'numeric', year: 'numeric', hour: 'numeric', minute: '2-digit' };
    let f;
    try {
      f = new Intl.DateTimeFormat(currentLocale(), options);
    } catch {
      f = new Intl.DateTimeFormat('en-PH', options);
    }
    formatters.set(key, f);
  }
  return formatters.get(key);
}

export const fmtDate = (iso) => (iso ? fmt('date').format(new Date(iso)) : '—');
export const fmtDateTime = (iso) => (iso ? fmt('datetime').format(new Date(iso)) : '—');
export const fmtNum = (n, digits = 0) =>
  n === null || n === undefined ? '—' : Number(n).toLocaleString('en-PH', { maximumFractionDigits: digits });
export const fmtPct = (n) => (n === null || n === undefined ? '—' : `${n > 0 ? '+' : ''}${fmtNum(n, 1)}%`);
export const fmtConf = (c) => (c === null || c === undefined ? '' : `${Math.round(c * 100)}%`);
/** A count of null means the reviewer (or the model result) marked it not countable. */
export const fmtCount = (n) => (n === null || n === undefined ? translate('Not countable') : fmtNum(n));

export const monthLabel = (ym) =>
  ym ? new Date(`${ym}-01T00:00:00`).toLocaleDateString(currentLocale(), { month: 'long', year: 'numeric' }) : '—';
export const quarterLabel = (q) => (q ? `${q.slice(5)} ${q.slice(0, 4)}` : '—');

export const daysSince = (iso) => (iso ? Math.max(0, Math.floor((Date.now() - new Date(iso)) / 86400000)) : null);

/** "35 min", "5 h", "3 days" since the given time. */
export function waitingLabel(iso) {
  if (!iso) return '—';
  const mins = Math.max(0, Math.floor((Date.now() - new Date(iso)) / 60000));
  if (mins < 60) return translate('{n} min', { n: mins });
  const hours = Math.floor(mins / 60);
  if (hours < 24) return translate('{n} h', { n: hours });
  const days = Math.floor(hours / 24);
  return translate(days === 1 ? '{n} day' : '{n} days', { n: days });
}

export const todayIso = () => {
  const d = new Date();
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
};

// ---------------------------------------------------------------- domain

export const ROLE_LABELS = { farmer: 'Farmer', technician: 'Technician', agriculturist: 'Agriculturist' };
export const LEVELS = ['LOW', 'MEDIUM', 'HIGH'];
export const CROP_STAGES = ['Vegetative', 'Reproductive', 'Ripening'];
// Same keys as the API (app/land.py). '' = recorded before the field existed.
export const LAND_TYPES = [
  ['upland', 'Upland'],
  ['rainfed_lowland', 'Rainfed lowland'],
  ['irrigated_lowland', 'Irrigated lowland'],
];
const LAND_LABELS = Object.fromEntries(LAND_TYPES);
export const landTypeLabel = (key) => LAND_LABELS[key] || 'Not recorded';

// Keys match the backend (levels.py); "other" = outside the four the model knows.
export const PEST_OPTIONS = [
  ['brown_planthopper', 'Brown Planthopper'],
  ['green_leafhopper', 'Green Leafhopper'],
  ['rice_bug', 'Rice Bug'],
  ['rice_stem_borer', 'Rice Stem Borer'],
  ['other', 'Outside the supported set'],
];
const PEST_LABELS = Object.fromEntries(PEST_OPTIONS);
export const pestLabel = (key) => (key ? PEST_LABELS[key] || key.replace(/_/g, ' ') : '—');

export const OPTION_TYPES = [
  ['cultural', 'Cultural'],
  ['biological', 'Biological'],
  ['ecological', 'Ecological'],
  ['chemical', 'Chemical'],
];

export const REVIEW_ACTIONS = {
  validated: 'Validated',
  returned: 'Returned to farmer',
  escalated: 'Escalated to To Be Validated',
  diagnosis: 'Diagnosis recorded',
  land_type_changed: 'Land type corrected',
};

// Same list as the mobile registration screen.
export const MUNICIPALITIES = [
  'Anini-y', 'Barbaza', 'Belison', 'Bugasong', 'Caluya', 'Culasi', 'Hamtic',
  'Laua-an', 'Libertad', 'Pandan', 'Patnongon', 'San Jose de Buenavista',
  'San Remigio', 'Sebaste', 'Sibalom', 'Tibiao', 'Tobias Fornier', 'Valderrama',
];

export const osmLink = (lat, lng) => `https://www.openstreetmap.org/?mlat=${lat}&mlon=${lng}#map=17/${lat}/${lng}`;
