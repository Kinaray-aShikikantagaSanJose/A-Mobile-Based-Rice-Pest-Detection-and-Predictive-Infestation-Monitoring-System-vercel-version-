import { useCallback, useEffect, useRef, useState } from 'react';
import { api, clearSession, hasToken, SESSION_EXPIRED } from './api.js';
import Avatar from './components/Avatar.jsx';
import { Logo } from './components/Brand.jsx';
import ErrorBoundary from './components/ErrorBoundary.jsx';
import Icon from './components/icons.jsx';
import LoadingScreen from './components/LoadingScreen.jsx';
import LoginScreen, { accessProblem, STAFF } from './components/LoginScreen.jsx';

import Sidebar from './components/Sidebar.jsx';
import { useInterval, useOnline } from './lib.js';
import CriteriaPage from './pages/CriteriaPage.jsx';
import GuidePage from './pages/GuidePage.jsx';
import HistoryPage from './pages/HistoryPage.jsx';
import HomePage from './pages/HomePage.jsx';
import LibraryPage from './pages/LibraryPage.jsx';
import MapPage from './pages/MapPage.jsx';
import MonthlyPage from './pages/MonthlyPage.jsx';
import QuarterlyPage from './pages/QuarterlyPage.jsx';
import QueuePage from './pages/QueuePage.jsx';
import RecordsPage from './pages/RecordsPage.jsx';
import ReportsPage from './pages/ReportsPage.jsx';
import TreatmentsPage from './pages/TreatmentsPage.jsx';
import UsersPage from './pages/UsersPage.jsx';

// Who sees what. The first item is the page shown after sign-in.
const NAV = {
  technician: [
    {
      group: 'Field work',
      items: [
        { id: 'queue', label: 'Validation queue', icon: 'queue', Page: QueuePage, badge: 'pending' },
        { id: 'map', label: 'Hotspot map', icon: 'map', Page: MapPage },
        { id: 'treatments', label: 'Treatments & follow-ups', icon: 'pill', Page: TreatmentsPage },
        { id: 'history', label: 'My validation history', icon: 'history', Page: HistoryPage },
      ],
    },
    {
      group: 'Reference',
      items: [
        { id: 'library', label: 'Treatment library', icon: 'book', Page: LibraryPage },
        { id: 'criteria', label: 'Infestation criteria', icon: 'gauge', Page: CriteriaPage },
        { id: 'guide', label: 'What to look for', icon: 'bug', Page: GuidePage },
      ],
    },
  ],
  agriculturist: [
    {
      group: 'Monitoring',
      items: [
        { id: 'home', label: 'Home', icon: 'dashboard', Page: HomePage },
        { id: 'map', label: 'Hotspot map', icon: 'map', Page: MapPage },
        { id: 'escalations', label: 'For your review', icon: 'inbox', Page: QueuePage, badge: 'escalated' },
        { id: 'records', label: 'Validated records', icon: 'fileCheck', Page: RecordsPage },
      ],
    },
    {
      group: 'Analysis',
      items: [
        { id: 'monthly', label: 'Monthly summaries', icon: 'calendar', Page: MonthlyPage },
        { id: 'quarterly', label: 'Quarterly patterns', icon: 'trend', Page: QuarterlyPage },
        { id: 'effectiveness', label: 'Treatment effectiveness', icon: 'chart', Page: TreatmentsPage },
      ],
    },
    {
      group: 'Reference',
      items: [
        { id: 'library', label: 'Treatment library', icon: 'book', Page: LibraryPage },
        { id: 'criteria', label: 'Infestation criteria', icon: 'gauge', Page: CriteriaPage },
        { id: 'guide', label: 'What to look for', icon: 'bug', Page: GuidePage },
      ],
    },
    {
      group: 'Administration',
      items: [
        { id: 'reports', label: 'Report export', icon: 'fileDown', Page: ReportsPage },
        { id: 'users', label: 'User management', icon: 'users', Page: UsersPage, badge: 'approvals' },
      ],
    },
  ],
};

const LOAD_STEPS = ['Verifying your account', 'Loading your workspace', 'Preparing your dashboard'];
const COLLAPSE_KEY = 'rp_sidebar_collapsed';
// How often the counts (and the "new submission" bullet) are refreshed.
const POLL_MS = 30000;
// Where new submissions are worked on.
const INBOX = { technician: 'queue', agriculturist: 'escalations' };

/** Observations count the person had seen, per account (null = never stored). */
const seenKey = (email) => `rp_seen_total:${email}`;
function readSeen(email) {
  try {
    const v = localStorage.getItem(seenKey(email));
    return v === null ? null : Number(v);
  } catch {
    return null;
  }
}
function writeSeen(email, n) {
  try {
    localStorage.setItem(seenKey(email), String(n));
  } catch {
    /* ignore */
  }
}

const plural = (n, word) => `${n} ${word}${n === 1 ? '' : 's'}`;

/** What the bell lists for this role, from the sidebar counts. */
function bellItems(role, b) {
  if (role === 'technician') {
    return [{ id: 'pending', count: b.pending || 0, alert: true, tone: 'bg-orange-500', page: 'queue', text: `${plural(b.pending || 0, 'observation')} waiting in your validation queue` }];
  }
  return [
    { id: 'escalated', count: b.escalated || 0, alert: true, tone: 'bg-violet-600', page: 'escalations', text: `${plural(b.escalated || 0, 'case')} waiting for your review` },
    { id: 'approvals', count: b.approvals || 0, alert: true, tone: 'bg-orange-500', page: 'users', text: `${plural(b.approvals || 0, 'account')} waiting for approval` },
  ];
}

const pageFromHash = () => window.location.hash.replace(/^#\/?/, '');
const wait = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
const loginRole = () => (window.location.pathname.replace(/\/+$/, '') === '/technician-login' ? 'technician' : 'agriculturist');
/** Resolves with `promise`, but not sooner than `ms`, so each loading step is seen. */
const atLeast = (promise, ms) => Promise.all([promise, wait(ms)]).then(([value]) => value);
const today = () => new Intl.DateTimeFormat('en-PH', { weekday: 'short', month: 'short', day: 'numeric' }).format(new Date());

function readCollapsed() {
  try {
    return localStorage.getItem(COLLAPSE_KEY) === '1';
  } catch {
    return false;
  }
}

/** Sidebar counts: the technician's queue, the agriculturist's escalations and approvals. Never rejects. */
async function fetchBadges(viewer) {
  const [overview, users] = await Promise.allSettled([
    api.overview(),
    viewer.role === 'agriculturist' ? api.users() : Promise.resolve(null),
  ]);
  const counts = {};
  if (overview.status === 'fulfilled') {
    const o = overview.value;
    counts.pending = o.pending;
    counts.escalated = o.waiting_for_agriculturist ?? o.escalations_waiting;
    counts.total = o.total_observations;
  }
  if (users.status === 'fulfilled' && users.value) {
    counts.approvals = users.value.filter((u) => u.status === 'pending' && u.is_verified).length;
  }
  return counts;
}

export default function App() {
  // login â†’ loading (animated checks) â†’ ready. A saved session starts at loading.
  const [phase, setPhase] = useState(() => (hasToken() ? 'loading' : 'login'));
  const [justSignedIn, setJustSignedIn] = useState(false);
  const [attempt, setAttempt] = useState(0);
  const [load, setLoad] = useState({ step: 0, name: '', error: null });
  const [viewer, setViewer] = useState(null);
  const [loginMessage, setLoginMessage] = useState('');
  const [page, setPage] = useState(pageFromHash);
  const [badges, setBadges] = useState({});
  const [collapsed, setCollapsed] = useState(readCollapsed);
  const [menuOpen, setMenuOpen] = useState(false);
  const badgesFresh = useRef(false);
  const online = useOnline();
  // "New submission" tracking: the total the person last looked at, and the
  // total at the previous poll (an increase shows a toast).
  const [seen, setSeen] = useState(null);
  const [toast, setToast] = useState(null);
  const lastTotal = useRef(null);

  const toLogin = useCallback((message = '') => {
    clearSession();
    setViewer(null);
    setBadges({});
    setSeen(null);
    setToast(null);
    lastTotal.current = null;
    setLoginMessage(message);
    setMenuOpen(false);
    setPhase('login');
  }, []);

  useEffect(() => {
    const onExpired = () => toLogin('Your session expired. Please sign in again.');
    const onHash = () => setPage(pageFromHash());
    window.addEventListener(SESSION_EXPIRED, onExpired);
    window.addEventListener('hashchange', onHash);
    return () => {
      window.removeEventListener(SESSION_EXPIRED, onExpired);
      window.removeEventListener('hashchange', onHash);
    };
  }, [toLogin]);

  // The loading screen's work: check the account, fetch the sidebar counts,
  // then open the dashboard. Paced a little after a fresh sign-in so the
  // steps are readable; quick when resuming a saved session.
  useEffect(() => {
    if (phase !== 'loading') return undefined;
    let alive = true;
    const pace = justSignedIn ? 550 : 200;
    setLoad({ step: 0, name: '', error: null });
    (async () => {
      try {
        const me = await atLeast(api.me(), pace);
        if (!alive) return;
        if (!STAFF.includes(me.role) || me.role !== loginRole()) {
          toLogin(accessProblem('approved', me.role, loginRole()));
          return;
        }
        setLoad((l) => ({ ...l, step: 1, name: (me.full_name || '').trim().split(/\s+/)[0] || '' }));

        const counts = await atLeast(fetchBadges(me), pace);
        if (!alive) return;
        setBadges(counts);
        setLoad((l) => ({ ...l, step: 2 }));

        await wait(pace);
        if (!alive) return;
        badgesFresh.current = true;
        setViewer(me);
        setPhase('ready');
      } catch (err) {
        if (!alive) return;
        // An expired session already went back to sign-in (SESSION_EXPIRED).
        if (err.kind === 'session') return;
        // Signed in, but the account can't use the dashboard (pending, rejected, wrong role).
        if (err.status === 403) {
          toLogin(err.message);
          return;
        }
        setLoad((l) => ({
          ...l,
          error: {
            title: err.kind === 'network' ? "Can't reach the server" : "We couldn't open the dashboard",
            text: err.message || 'Something went wrong. Please try again.',
            offline: err.kind === 'network',
          },
        }));
      }
    })();
    return () => {
      alive = false;
    };
  }, [phase, attempt, justSignedIn, toLogin]);

  useEffect(() => {
    try {
      localStorage.setItem(COLLAPSE_KEY, collapsed ? '1' : '0');
    } catch {
      /* ignore */
    }
  }, [collapsed]);

  const refreshBadges = useCallback(() => {
    if (!viewer) return;
    fetchBadges(viewer).then((counts) => setBadges((b) => ({ ...b, ...counts })));
  }, [viewer]);

  // Refresh the counts on every page change (the loading screen just fetched them for the first one).
  useEffect(() => {
    if (badgesFresh.current) {
      badgesFresh.current = false;
      return;
    }
    refreshBadges();
  }, [refreshBadges, page]);
  useInterval(refreshBadges, POLL_MS);

  // New observations since the last look (and a toast when one arrives).
  const total = badges.total;
  useEffect(() => {
    if (!viewer || total === undefined || total === null) return;
    let s = readSeen(viewer.email);
    // First sign-in on this browser, or records were removed: start from now.
    if (s === null || s > total) {
      s = total;
      writeSeen(viewer.email, s);
    }
    setSeen(s);
    if (lastTotal.current !== null && total > lastTotal.current) {
      const n = total - lastTotal.current;
      setToast({
        title: n === 1 ? 'New submission received' : `${n} new submissions received`,
        text: 'A farmer sent an observation from the field.',
        page: INBOX[viewer.role],
        action: viewer.role === 'technician' ? 'Open the validation queue' : 'Open',
      });
    }
    lastTotal.current = total;
  }, [total, viewer]);

  const closeToast = useCallback(() => setToast(null), []);

  const markSeen = useCallback(() => {
    if (!viewer || total === undefined || total === null) return;
    writeSeen(viewer.email, total);
    setSeen(total);
  }, [viewer, total]);

  // Opening the inbox counts as having seen the new submissions.
  const inbox = viewer ? INBOX[viewer.role] : null;
  useEffect(() => {
    if (inbox && page === inbox) markSeen();
  }, [page, inbox, markSeen]);
  // Back online: catch up on anything missed.
  const wasOnline = useRef(online);
  useEffect(() => {
    if (online && !wasOnline.current) refreshBadges();
    wasOnline.current = online;
  }, [online, refreshBadges]);

  if (phase === 'login') {
    return (
      <LoginScreen
        message={loginMessage}
        requiredRole={loginRole()}
        onAuthenticated={() => {
          setLoginMessage('');
          setJustSignedIn(true);
          setPhase('loading');
        }}
      />
    );
  }

  if (phase === 'loading' || !viewer) {
    return (
      <LoadingScreen
        steps={LOAD_STEPS}
        current={load.step}
        name={load.name}
        error={load.error}
        onRetry={() => setAttempt((a) => a + 1)}
        onSignOut={() => toLogin('')}
      />
    );
  }

  const groups = NAV[viewer.role] || [];
  const items = groups.flatMap((g) => g.items.map((i) => ({ ...i, group: g.group })));
  const current = items.find((i) => i.id === page) || items[0];
  const go = (id) => {
    window.location.hash = id;
    setPage(id);
    window.scrollTo({ top: 0 });
  };
  const name = viewer.full_name || viewer.email;
  const { Page } = current;
  const fresh = seen === null || total === undefined ? 0 : Math.max(0, total - seen);

  return (
    <div className="flex min-h-full bg-canvas">
      <Sidebar
        groups={groups}
        currentId={current.id}
        badges={badges}
        viewer={viewer}
        collapsed={collapsed}
        onToggle={() => setCollapsed((c) => !c)}
        onNavigate={go}
        onSignOut={() => toLogin('')}
        mobileOpen={menuOpen}
        onCloseMobile={() => setMenuOpen(false)}
        freshId={fresh > 0 ? inbox : null}
      />

      <div className="flex min-w-0 flex-1 flex-col">
        <header className="sticky top-0 z-[1500] flex h-16 items-center gap-3 border-b border-line bg-white/90 px-4 backdrop-blur sm:px-6">
          <button
            type="button"
            onClick={() => setMenuOpen(true)}
            aria-label="Open menu"
            className="rounded-lg p-2 text-ink hover:bg-canvas focus:outline-none focus-visible:ring-2 focus-visible:ring-brand-600 lg:hidden"
          >
            <Icon name="menu" />
          </button>
          <button
            type="button"
            onClick={() => setCollapsed((c) => !c)}
            aria-label={collapsed ? 'Expand sidebar' : 'Collapse sidebar'}
            title={collapsed ? 'Expand sidebar' : 'Collapse sidebar'}
            className="hidden rounded-lg p-2 text-ink2 hover:bg-canvas hover:text-ink focus:outline-none focus-visible:ring-2 focus-visible:ring-brand-600 lg:inline-flex"
          >
            <Icon name={collapsed ? 'panelOpen' : 'panelClose'} />
          </button>
          <Logo className="h-8 w-8 lg:hidden" />
          <nav aria-label="Breadcrumb" className="flex min-w-0 items-center gap-2 text-sm">
            <span className="hidden shrink-0 text-ink2 sm:inline">{current.group}</span>
            <Icon name="chevronRight" className="hidden h-4 w-4 text-muted sm:block" />
            <span className="flex min-w-0 items-center gap-2 font-semibold text-ink">
              <Icon name={current.icon} className="h-4 w-4 text-brand-700" />
              <span className="truncate">{current.label}</span>
            </span>
          </nav>
          <div className="ml-auto flex shrink-0 items-center gap-3">
            {!online && (
              <span className="inline-flex items-center gap-1.5 rounded-full bg-red-50 px-2.5 py-1 text-xs font-semibold text-red-700 ring-1 ring-red-200">
                <Icon name="wifiOff" className="h-3.5 w-3.5" />
                Offline
              </span>
            )}
            <span className="hidden text-sm text-ink2 md:inline">{today()}</span>

            <Avatar path={viewer.avatar_url} name={name} size="sm" />
          </div>
        </header>

        {!online && (
          <div className="flex items-center justify-center gap-2 border-b border-red-200 bg-red-50 px-4 py-2 text-center text-sm text-red-700">
            <Icon name="wifiOff" className="h-4 w-4" />
            You're offline. Data can't load or be saved until the connection is back.
          </div>
        )}

        <main className="mx-auto w-full max-w-[1400px] flex-1 p-4 sm:p-6 lg:p-8">
          <ErrorBoundary resetKey={current.id}>
            <Page key={current.id} viewer={viewer} onChanged={refreshBadges} />
          </ErrorBoundary>
        </main>
      </div>
      </div>
  );
}
