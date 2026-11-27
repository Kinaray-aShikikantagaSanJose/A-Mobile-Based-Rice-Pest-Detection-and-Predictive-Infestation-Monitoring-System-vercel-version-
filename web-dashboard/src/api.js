// Local dev (vite / vite preview): requests go to /api on the dashboard's own
// server, which forwards them to the API on this laptop (see
// vite.config.js). Works from this laptop or another device on the network
// without editing an IP address.
// On Vercel set VITE_API_URL to the deployed API (e.g.
// https://palay-patrol-api.vercel.app) in Project → Settings → Environment
// Variables, then redeploy. No trailing slash. The API must list this
// dashboard's address in CORS_ALLOWED_ORIGINS.
export const API = (import.meta.env.VITE_API_URL || `${window.location.origin}/api`).replace(/\/$/, '');
if (window.location.protocol === 'https:' && new URL(API).protocol !== 'https:') {
  throw new Error('The dashboard requires an HTTPS API when the page itself is served over HTTPS.');
}

import { currentLanguage } from './i18n/index.jsx';

const TOKEN_KEY = 'rp_token';
const REFRESH_KEY = 'rp_refresh';
const EMAIL_KEY = 'rp_last_email';
export const SESSION_EXPIRED = 'rp:session-expired';
/** Fired with {detail: {path, savedAt}} when a page shows saved data because the server can't be reached. */
export const SAVED_DATA = 'rp:saved-data';
/** Fired when a request reached the server again (the "saved data" note can go). */
export const LIVE_DATA = 'rp:live-data';

// ---------------------------------------------------------------- saved data (unstable network)
// The latest answer to each GET is kept in localStorage, per signed-in
// account. When the network drops, the page shows that copy (with a note
// saying when it was saved) instead of an error or an endless spinner.
// Photos and CSV downloads are not kept. Cleared on sign-out.
const CACHE_PREFIX = 'rp_cache:';
const CACHE_MAX_CHARS = 400000; // skip very large answers (localStorage is ~5 MB)

function cacheKey(path) {
  let who = '';
  try {
    who = window.localStorage.getItem(EMAIL_KEY) || '';
  } catch {
    /* ignore */
  }
  return `${CACHE_PREFIX}${who}|${currentLanguage()}|${path}`;
}

function saveCopy(path, data) {
  try {
    const text = JSON.stringify({ savedAt: new Date().toISOString(), data });
    if (text.length <= CACHE_MAX_CHARS) window.localStorage.setItem(cacheKey(path), text);
  } catch {
    /* quota or private mode: just don't keep a copy */
  }
}

function readCopy(path) {
  try {
    const text = window.localStorage.getItem(cacheKey(path));
    return text ? JSON.parse(text) : null;
  } catch {
    return null;
  }
}

/** Removes every saved answer (sign-out, account change). */
export function clearSavedData() {
  try {
    const keys = [];
    for (let i = 0; i < window.localStorage.length; i += 1) {
      const k = window.localStorage.key(i);
      if (k && k.startsWith(CACHE_PREFIX)) keys.push(k);
    }
    keys.forEach((k) => window.localStorage.removeItem(k));
  } catch {
    /* ignore */
  }
}

/**
 * Every failed request throws this. `kind` says what went wrong so screens
 * can react: 'network' (server unreachable or too slow), 'session' (signed
 * out), or 'http' (the server refused; `status` holds the code).
 */
export class ApiError extends Error {
  constructor(message, { kind = 'http', status = null } = {}) {
    super(message);
    this.name = 'ApiError';
    this.kind = kind;
    this.status = status;
  }
}

function storage(persistent) {
  try {
    return persistent ? window.localStorage : window.sessionStorage;
  } catch {
    return null; // storage blocked: keep the session in memory only
  }
}

// "Remember me" keeps the session in localStorage (survives closing the
// browser); otherwise sessionStorage (ends with the tab).
let store = (() => {
  try {
    return storage(true)?.getItem(TOKEN_KEY) ? storage(true) : storage(false);
  } catch {
    return storage(false);
  }
})();

function read(key) {
  try {
    return store?.getItem(key) || '';
  } catch {
    return '';
  }
}

// The access token lasts 60 minutes; the refresh token renews it, so a long
// task (e.g. writing a library entry) isn't lost to a sign-out.
let token = read(TOKEN_KEY);
let refreshToken = read(REFRESH_KEY);

export const hasToken = () => Boolean(token);

/** `remember` picks where a new session is kept; renewals keep the current place. */
export function setToken(value, refresh, remember) {
  token = value;
  if (refresh) refreshToken = refresh;
  if (remember !== undefined) {
    clearStored();
    store = storage(remember);
  }
  try {
    store?.setItem(TOKEN_KEY, value);
    if (refresh) store?.setItem(REFRESH_KEY, refresh);
  } catch {
    /* private mode: keep the session in memory only */
  }
}

function clearStored() {
  for (const s of [storage(true), storage(false)]) {
    try {
      s?.removeItem(TOKEN_KEY);
      s?.removeItem(REFRESH_KEY);
      s?.removeItem('rp_role'); // left over from the old dashboard
    } catch {
      /* ignore */
    }
  }
}

export function clearSession() {
  token = '';
  refreshToken = '';
  clearStored();
  clearSavedData();
}

/** The email of the last "Remember me" sign-in, to prefill the form. */
export function rememberedEmail() {
  try {
    return localStorage.getItem(EMAIL_KEY) || '';
  } catch {
    return '';
  }
}

export function rememberEmail(email) {
  try {
    if (email) localStorage.setItem(EMAIL_KEY, email);
    else localStorage.removeItem(EMAIL_KEY);
  } catch {
    /* ignore */
  }
}

const TIMEOUT_MS = 30000;

/** fetch that gives up after `ms` (a stalled server otherwise hangs the page). */
async function fetchWithTimeout(url, init, ms = TIMEOUT_MS) {
  const ctrl = new AbortController();
  const timer = setTimeout(() => ctrl.abort(), ms);
  try {
    return await fetch(url, { ...init, signal: ctrl.signal });
  } catch (e) {
    throw new ApiError(
      e?.name === 'AbortError'
        ? 'The server took too long to respond. Check your connection and try again.'
        : "Can't reach the server. Check your connection and that the API is running.",
      { kind: 'network' },
    );
  } finally {
    clearTimeout(timer);
  }
}

let refreshing = null;

/** Swaps the refresh token for new tokens: 'ok', 'expired' or 'offline'. Concurrent callers share one call. */
function renewSession() {
  if (!refreshToken) return Promise.resolve('expired');
  if (!refreshing) {
    refreshing = (async () => {
      let res;
      try {
        res = await fetchWithTimeout(`${API}/auth/refresh`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ refresh_token: refreshToken }),
        });
      } catch {
        return 'offline';
      }
      if (!res.ok) return 'expired';
      try {
        const data = await res.json();
        if (!data.access_token) return 'expired';
        setToken(data.access_token, data.refresh_token);
        return 'ok';
      } catch {
        return 'expired';
      }
    })().finally(() => {
      refreshing = null;
    });
  }
  return refreshing;
}

function query(params) {
  if (!params) return '';
  const entries = Object.entries(params).filter(([, v]) => v !== '' && v !== null && v !== undefined && v !== false);
  return entries.length ? `?${new URLSearchParams(entries)}` : '';
}

async function errorMessage(res) {
  try {
    const data = await res.json();
    if (typeof data.detail === 'string') return data.detail;
    if (Array.isArray(data.detail)) {
      return data.detail.map((d) => String(d.msg || '').replace(/^Value error, /, '')).join(' ');
    }
  } catch {
    /* not JSON */
  }
  if (res.status === 403) return "Your account doesn't have access to this.";
  if (res.status === 429) return 'Too many attempts. Please wait a moment and try again.';
  if (res.status >= 500) return 'The server had a problem. Please try again in a moment.';
  return 'The request failed. Please try again.';
}

/**
 * GET requests (not raw) keep a saved copy; when the server can't be reached
 * the copy is returned instead and SAVED_DATA is fired. `cache: false` opts out.
 */
async function request(path, options = {}, retried = false) {
  const { method = 'GET', raw = false, cache = true } = options;
  const keep = method === 'GET' && !raw && cache;
  const full = `${path}${query(options.params)}`;
  try {
    const data = await send(path, options, retried);
    if (keep) {
      saveCopy(full, data);
      window.dispatchEvent(new Event(LIVE_DATA));
    }
    return data;
  } catch (e) {
    if (keep && e instanceof ApiError && e.kind === 'network') {
      const copy = readCopy(full);
      if (copy) {
        window.dispatchEvent(new CustomEvent(SAVED_DATA, { detail: { path: full, savedAt: copy.savedAt } }));
        return copy.data;
      }
    }
    throw e;
  }
}

async function send(path, options = {}, retried = false) {
  // `form` (FormData) is sent as multipart; the browser sets its boundary.
  const { method = 'GET', body, form, params, raw = false, timeout } = options;
  // X-Palay-Client: shown as the app in the activity log.
  // X-Palay-Language: texts the server computes (spread, guide, level reasons) come back in it.
  const headers = { 'X-Palay-Client': 'dashboard', 'X-Palay-Language': currentLanguage() };
  if (token) headers.Authorization = `Bearer ${token}`;
  if (body !== undefined) headers['Content-Type'] = 'application/json';
  const res = await fetchWithTimeout(
    `${API}${path}${query(params)}`,
    { method, headers, body: form ?? (body === undefined ? undefined : JSON.stringify(body)) },
    timeout,
  );
  if (res.status === 401 && token) {
    if (!retried) {
      const renewed = await renewSession();
      if (renewed === 'ok') return send(path, options, true);
      if (renewed === 'offline') {
        throw new ApiError("Can't reach the server. Check your connection and that the API is running.", {
          kind: 'network',
        });
      }
    }
    clearSession();
    window.dispatchEvent(new Event(SESSION_EXPIRED));
    throw new ApiError('Your session expired. Please sign in again.', { kind: 'session', status: 401 });
  }
  if (!res.ok) throw new ApiError(await errorMessage(res), { status: res.status });
  if (raw) return res;
  if (res.status === 204) return null;
  try {
    return await res.json();
  } catch {
    throw new ApiError('The server sent a response the dashboard could not read.', { status: res.status });
  }
}

/** A paged list: the JSON array plus X-Total-Count, saved for offline use like request(). */
async function requestList(path, params) {
  const full = `${path}${query(params)}`;
  try {
    const res = await send(path, { params, raw: true });
    const items = await res.json();
    const header = res.headers.get('X-Total-Count');
    const data = { items, total: header === null ? items.length : Number(header) };
    saveCopy(full, data);
    window.dispatchEvent(new Event(LIVE_DATA));
    return data;
  } catch (e) {
    if (e instanceof ApiError && e.kind === 'network') {
      const copy = readCopy(full);
      if (copy) {
        window.dispatchEvent(new CustomEvent(SAVED_DATA, { detail: { path: full, savedAt: copy.savedAt } }));
        return copy.data;
      }
    }
    throw e;
  }
}

function saveBlob(blob, filename) {
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = filename;
  document.body.appendChild(a);
  a.click();
  a.remove();
  setTimeout(() => URL.revokeObjectURL(url), 1000);
}

// Photos need the Authorization header, so they're fetched as blobs.
// Cached per scan so the table thumbnail and the drawer share one download.
const imageCache = new Map();

/** Fetches an authorized image once per path and hands out an object URL. */
function cachedBlobUrl(key, path) {
  if (!imageCache.has(key)) {
    const pending = request(path, { raw: true, timeout: 60000 })
      .then((res) => res.blob())
      .then((blob) => URL.createObjectURL(blob));
    pending.catch(() => imageCache.delete(key));
    imageCache.set(key, pending);
  }
  return imageCache.get(key);
}

function photoForm(file) {
  const form = new FormData();
  form.append('image', file);
  return form;
}

/**
 * Ends the sign-in session on the server (its tokens stop working), then
 * forgets it here. Never throws: signing out works offline too.
 */
export async function logout() {
  const access = token;
  const refresh = refreshToken;
  clearSession();
  if (!access && !refresh) return;
  try {
    await fetchWithTimeout(
      `${API}/auth/logout`,
      {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-Palay-Client': 'dashboard',
          ...(access ? { Authorization: `Bearer ${access}` } : {}),
        },
        body: JSON.stringify({ refresh_token: refresh || null }),
      },
      8000,
    );
  } catch {
    /* offline: the session simply expires */
  }
}

export const api = {
  login: (email, password) => request('/auth/login', { method: 'POST', body: { email, password } }),
  me: () => request('/dashboard/me'),
  // en | fil | krj, saved on the account (also used for its notifications).
  setLanguage: (code) => request('/auth/me', { method: 'PUT', body: { preferred_language: code } }),

  overview: () => request('/analytics/overview'),
  hotspots: (params) => request('/analytics/hotspots', { params }),
  // Directional spread: where validated cases moved between two consecutive windows.
  spread: (params) => request('/analytics/spread', { params }),
  records: (params) => request('/analytics/records', { params }),
  monthly: (month) => request('/analytics/monthly', { params: { month } }),
  quarterly: (quarter) => request('/analytics/quarterly', { params: { quarter } }),
  trendPrediction: (weeks = 26, ahead = 4) => request('/analytics/trends/prediction', { params: { weeks, ahead } }),
  // Treatments with before/after follow-ups; params: outcome, limit, offset.
  treatments: (params) => request('/analytics/treatments', { params }),
  // Staff: follow-up (feedback) date and re-allowing an already-tried option.
  updateTreatment: (id, body) => request(`/dashboard/treatments/${id}`, { method: 'PATCH', body }),

  // 'What to look for' pest and symptom guide (same content as the mobile app).
  guide: () => request('/guide'),
  guidePhotoUrl: (path) => cachedBlobUrl(`guide:${path}`, path),

  // Review queue (technicians: pending in their area; agriculturists: escalations)
  // queue: '' (both) | 'not_validated' (pending) | 'to_be_validated' (escalated)
  queue: (kind, extra = {}) => request('/sync/queue', { params: { kind, ...extra } }),
  scan: (id) => request(`/sync/scans/${id}`),
  // Agriculturists and technicians (their area). The database checks it too.
  deleteRecord: (id, reason = '') => request(`/sync/scans/${id}`, { method: 'DELETE', params: { reason } }),
  review: (id, body) => request(`/sync/scans/${id}/review`, { method: 'POST', body }),
  // Technicians (their area) and agriculturists correct the land type; kept in the history.
  setLandType: (id, landType, reason = '') =>
    request(`/sync/scans/${id}/land-type`, { method: 'PATCH', body: { land_type: landType, reason } }),
  // Built by hand: crop_stage is required even when empty ('' = the any-stage thresholds).
  levelSuggestion: ({ pest, crop_stage, count, indicators = [] }) => {
    const q = new URLSearchParams({ pest, crop_stage: crop_stage || '' });
    if (count !== null && count !== undefined) q.set('count', count);
    if (indicators.length) q.set('indicators', indicators.join('|'));
    return request(`/sync/level-suggestion?${q}`);
  },
  // Paged on the server: {items, total}.
  myReviews: (params) => requestList('/dashboard/my-reviews', params),

  library: () => request('/dashboard/library'),
  createEntry: (body) => request('/dashboard/library', { method: 'POST', body }),
  updateEntry: (id, body) => request(`/dashboard/library/${id}`, { method: 'PUT', body }),
  setEntryStatus: (id, status) => request(`/dashboard/library/${id}/status`, { method: 'POST', body: { status } }),
  deleteEntry: (id) => request(`/dashboard/library/${id}`, { method: 'DELETE' }),

  criteria: () => request('/dashboard/criteria'),
  saveCriteria: (body) => request('/dashboard/criteria', { method: 'PUT', body }),
  deleteCriteria: (id) => request(`/dashboard/criteria/${id}`, { method: 'DELETE' }),
  // Agriculturists: mark thresholds as checked against a source (or provisional again).
  confirmCriteria: (id, sourceReference, confirmed = true) =>
    request(`/dashboard/criteria/${id}/confirm`, {
      method: 'POST',
      body: { source_reference: sourceReference, confirmed },
    }),

  areas: () => request('/dashboard/areas'),
  users: () => request('/dashboard/users'),
  // Filtered and paged on the server: {items, total}. params: q, role, status, municipality, limit, offset.
  usersPage: (params) => requestList('/dashboard/users', params),
  createUser: (body) => request('/dashboard/users', { method: 'POST', body }),
  updateUser: (id, body) => request(`/dashboard/users/${id}`, { method: 'PATCH', body }),
  deleteUser: (id) => request(`/dashboard/users/${id}`, { method: 'DELETE' }),
  setUserAvatar: (id, file) => request(`/dashboard/users/${id}/avatar`, { method: 'POST', form: photoForm(file), timeout: 60000 }),
  clearUserAvatar: (id) => request(`/dashboard/users/${id}/avatar`, { method: 'DELETE' }),

  // Activity logs (agriculturists): sign-ins, sign-outs and important actions.
  activity: (params) => request('/dashboard/activity', { params }),
  activitySessions: (params) => request('/dashboard/activity/sessions', { params }),
  async downloadActivity(params, filename) {
    const res = await request('/dashboard/activity/export', { params, raw: true, timeout: 120000 });
    saveBlob(await res.blob(), filename);
  },

  async downloadReport(kind, params, filename) {
    // Headers and labels in the dashboard language; every matching row (no paging).
    const res = await request(`/dashboard/reports/${kind}`, {
      params: { ...params, lang: currentLanguage() },
      raw: true,
      timeout: 120000,
    });
    saveBlob(await res.blob(), filename);
  },

  imageUrl: (id) => cachedBlobUrl(id, `/sync/scans/${id}/image`),

  /** `avatarPath` is the `avatar_url` the API returns (it changes with each upload). */
  avatarUrl: (avatarPath) => cachedBlobUrl(`avatar:${avatarPath}`, avatarPath),
};
