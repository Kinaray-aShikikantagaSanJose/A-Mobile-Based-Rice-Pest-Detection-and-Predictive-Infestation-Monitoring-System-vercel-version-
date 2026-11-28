import { useState } from 'react';
import { api } from '../api.js';
import { useT } from '../i18n/index.jsx';
import { fmtDateTime, ROLE_LABELS, todayIso, useAction, useAsync, useDebounced } from '../lib.js';
import { Badge, Button, Empty, ErrorNote, Field, Loading, PageHeader, Pager, Panel, Segmented, Select, Table } from '../components/ui.jsx';

const PAGE = 30;

/** English labels for the action types the API records (app/activity.py). */
export const ACTION_LABELS = {
  login: 'Signed in',
  login_failed: 'Sign-in failed',
  logout: 'Signed out',
  session_resumed: 'Session resumed',
  account_registered: 'Registered',
  email_verified: 'Email verification',
  otp_resent: 'Code sent again',
  account_deleted: 'Account deleted',
  profile_updated: 'Profile updated',
  password_changed: 'Password changed',
  avatar_changed: 'Profile picture changed',
  language_changed: 'Language changed',
  location_updated: 'Location updated',
  observation_submitted: 'Observation sent',
  observation_no_pests: 'Observation: no pests found',
  observation_reviewed: 'Observation reviewed',
  observation_deleted: 'Observation deleted',
  treatment_logged: 'Treatment logged',
  treatment_updated: 'Treatment follow-up changed',
  user_created: 'Account created',
  user_updated: 'Account updated',
  user_deleted: 'Account removed',
  library_changed: 'Treatment library changed',
  criteria_changed: 'Criteria changed',
  report_exported: 'Report exported',
};

const REASONS = {
  wrong_password: 'Wrong password',
  unknown_account: 'No account with this email',
  email_not_verified: 'Email not verified yet',
  wrong_code: 'Wrong code',
  wrong_current_password: 'Wrong current password',
};

const SESSION_TONE = { active: 'green', ended: 'gray', expired: 'orange' };
const SESSION_LABELS = { active: 'Active', ended: 'Ended', expired: 'Expired' };
const CLIENT_LABELS = { mobile: 'Mobile app', web: 'Web browser', dashboard: 'Dashboard' };
const LANG_LABELS = { en: 'English', fil: 'Filipino', krj: 'Kinaray-a' };
const NO_FILTERS = { email: '', role: '', action: '', outcome: '', session_status: '', start: '', end: '' };

/** One short line about what happened, from the action's details. */
function summary(item, t) {
  const d = item.details || {};
  switch (item.action) {
    case 'login_failed':
    case 'email_verified':
    case 'password_changed':
      return d.reason ? t(REASONS[d.reason] || d.reason) : '';
    case 'observation_reviewed':
      return [`#${item.target_id}`, d.decision && t(d.decision === 'validated' ? 'Validated' : d.decision === 'returned' ? 'Returned' : 'Escalated'), d.level && t(d.level)]
        .filter(Boolean)
        .join(' · ');
    case 'observation_deleted':
      return [`#${item.target_id}`, [d.barangay, d.municipality].filter(Boolean).join(', '), d.reason].filter(Boolean).join(' · ');
    case 'observation_submitted':
    case 'observation_no_pests':
      return [`#${item.target_id}`, d.report_type && t(d.report_type === 'disease' ? 'Disease' : 'Pest'), d.location_status === 'outside_antique' && t('GPS outside Antique')]
        .filter(Boolean)
        .join(' · ');
    case 'language_changed':
      return `${t(LANG_LABELS[d.from] || d.from || '')} → ${t(LANG_LABELS[d.to] || d.to || '')}`;
    case 'location_updated':
      return [d.barangay, d.municipality].filter(Boolean).join(', ') + (d.source === 'gps' ? ` (${t('from GPS')})` : '');
    case 'profile_updated':
      return (d.fields || []).map((f) => t(f === 'full_name' ? 'name' : f === 'phone' ? 'mobile number' : f)).join(', ');
    case 'user_created':
    case 'user_updated':
    case 'user_deleted':
      return [d.email, d.role && t(ROLE_LABELS[d.role] || d.role), (d.changed || []).map((c) => t(c)).join(', ')].filter(Boolean).join(' · ');
    case 'report_exported':
      return item.target_id;
    default:
      return item.target_id ? `${item.target_type} #${item.target_id}` : '';
  }
}

function SessionBadge({ status }) {
  const t = useT();
  if (!status) return <span className="text-xs text-muted">{t('No session')}</span>;
  return <Badge tone={SESSION_TONE[status] || 'gray'}>{t(SESSION_LABELS[status] || status)}</Badge>;
}

function Filters({ f, set, search, setSearch, users, actions, showActivityFilters, t }) {
  return (
    <div className="grid gap-3 border-b border-line p-5 sm:grid-cols-2 lg:grid-cols-4">
      <Field label={t('Search name or email')} className="sm:col-span-2">
        <input className="input" value={search} onChange={(e) => setSearch(e.target.value)} placeholder={t('Name or email…')} />
      </Field>
      <Field label={t('User')}>
        <Select
          value={f.email}
          onChange={set('email')}
          placeholder={t('All users')}
          options={users.map((u) => [u.email, `${u.full_name} (${t(ROLE_LABELS[u.role] || u.role)})`])}
        />
      </Field>
      <Field label={t('Role')}>
        <Select
          value={f.role}
          onChange={set('role')}
          placeholder={t('All roles')}
          options={[...Object.entries(ROLE_LABELS).map(([v, l]) => [v, t(l)]), ['none', t('No account')]]}
        />
      </Field>
      {showActivityFilters && (
        <>
          <Field label={t('Action type')}>
            <Select value={f.action} onChange={set('action')} placeholder={t('All actions')} options={actions.map((a) => [a, t(ACTION_LABELS[a] || a)])} />
          </Field>
          <Field label={t('Outcome')}>
            <Select value={f.outcome} onChange={set('outcome')} placeholder={t('All')} options={[['success', t('Success')], ['failure', t('Failed')]]} />
          </Field>
        </>
      )}
      <Field label={t('Session status')}>
        <Select
          value={f.session_status}
          onChange={set('session_status')}
          placeholder={t('All')}
          options={[
            ['active', t('Active')],
            ['ended', t('Ended')],
            ['expired', t('Expired')],
            ...(showActivityFilters ? [['none', t('No session')]] : []),
          ]}
        />
      </Field>
      <div className="grid grid-cols-2 gap-3">
        <Field label={t('From')}>
          <input type="date" className="input" value={f.start} max={f.end || undefined} onChange={(e) => set('start')(e.target.value)} />
        </Field>
        <Field label={t('To')}>
          <input type="date" className="input" value={f.end} min={f.start || undefined} onChange={(e) => set('end')(e.target.value)} />
        </Field>
      </div>
    </div>
  );
}

/**
 * Activity logs (agriculturists): sign-ins, sign-outs, session activity and
 * important actions of farmers, technicians and agriculturists.
 */
export default function ActivityPage() {
  const t = useT();
  const [tab, setTab] = useState('activity');
  const [search, setSearch] = useState('');
  const [f, setF] = useState(NO_FILTERS);
  const [offset, setOffset] = useState(0);
  const q = useDebounced(search);
  const set = (key) => (value) => {
    setOffset(0);
    setF((prev) => ({ ...prev, [key]: value }));
  };
  const params = { ...f, q, limit: PAGE, offset };
  const sessionParams = { q, email: f.email, role: f.role, session_status: f.session_status === 'none' ? '' : f.session_status, start: f.start, end: f.end, limit: PAGE, offset };
  const res = useAsync(() => (tab === 'activity' ? api.activity(params) : api.activitySessions(sessionParams)), [tab, JSON.stringify(params)]);
  const users = useAsync(() => api.users(), []);
  const exporting = useAction();
  const filtered = search || JSON.stringify(f) !== JSON.stringify(NO_FILTERS);
  const items = res.data?.items || [];
  const total = res.data?.total ?? 0;

  const activityColumns = [
    { key: 'time', label: t('Time'), render: (r) => <span className="whitespace-nowrap text-ink2">{fmtDateTime(r.created_at)}</span> },
    {
      key: 'user',
      label: t('User'),
      render: (r) => (
        <div className="max-w-[220px]">
          <div className="truncate font-medium text-ink">{r.user_name || r.user_email || '—'}</div>
          {r.user_name && <div className="truncate text-xs text-ink2">{r.user_email}</div>}
        </div>
      ),
    },
    { key: 'role', label: t('Role'), render: (r) => (r.user_role ? t(ROLE_LABELS[r.user_role] || r.user_role) : <span className="text-muted">—</span>) },
    {
      key: 'action',
      label: t('Action'),
      render: (r) => (
        <div className="flex flex-wrap items-center gap-1.5">
          <span className="font-medium text-ink">{t(ACTION_LABELS[r.action] || r.action)}</span>
          {r.outcome === 'failure' && <Badge tone="red">{t('Failed')}</Badge>}
        </div>
      ),
    },
    { key: 'details', label: t('Details'), render: (r) => <span className="block max-w-[260px] truncate text-ink2" title={summary(r, t)}>{summary(r, t) || '—'}</span> },
    {
      key: 'client',
      label: t('App / IP'),
      render: (r) => (
        <div className="text-xs text-ink2">
          <div>{t(CLIENT_LABELS[r.client] || r.client || '—')}</div>
          <div className="text-muted">{r.ip_address}</div>
        </div>
      ),
    },
    {
      key: 'session',
      label: t('Session'),
      render: (r) => (
        <div>
          <SessionBadge status={r.session_status} />
          {r.session_started && <div className="mt-0.5 text-xs text-muted">{t('since {date}', { date: fmtDateTime(r.session_started) })}</div>}
        </div>
      ),
    },
  ];

  const sessionColumns = [
    {
      key: 'user',
      label: t('User'),
      render: (s) => (
        <div className="max-w-[220px]">
          <div className="truncate font-medium text-ink">{s.user_name || s.user_email}</div>
          {s.user_name && <div className="truncate text-xs text-ink2">{s.user_email}</div>}
        </div>
      ),
    },
    { key: 'role', label: t('Role'), render: (s) => (s.user_role ? t(ROLE_LABELS[s.user_role] || s.user_role) : '—') },
    { key: 'status', label: t('Status'), render: (s) => <SessionBadge status={s.status} /> },
    { key: 'client', label: t('App'), render: (s) => <span className="text-ink2">{t(CLIENT_LABELS[s.client] || s.client || '—')}</span> },
    { key: 'started', label: t('Signed in'), render: (s) => <span className="whitespace-nowrap text-ink2">{fmtDateTime(s.started_at)}</span> },
    { key: 'seen', label: t('Last active'), render: (s) => <span className="whitespace-nowrap text-ink2">{fmtDateTime(s.last_seen_at)}</span> },
    {
      key: 'ended',
      label: t('Signed out'),
      render: (s) =>
        s.ended_at ? (
          <span className="whitespace-nowrap text-ink2">
            {fmtDateTime(s.ended_at)}
            {s.end_reason && s.end_reason !== 'logout' && <span className="text-xs text-muted"> · {t(s.end_reason === 'account_deleted' ? 'account removed' : s.end_reason)}</span>}
          </span>
        ) : (
          <span className="text-muted">—</span>
        ),
    },
    { key: 'actions', label: t('Actions'), align: 'right', render: (s) => s.actions },
  ];

  const exportCsv = () =>
    exporting.run(() => api.downloadActivity({ ...f, q }, `activity-log-${todayIso()}.csv`));

  return (
    <div>
      <PageHeader
        title={t('Activity logs')}
        description={t('Sign-ins, sign-outs, sessions and important actions of farmers, technicians and agriculturists. Filter by person, role, dates, action type and session status.')}
        actions={
          tab === 'activity' && (
            <Button variant="secondary" busy={exporting.busy} onClick={exportCsv}>
              {t('Export CSV')}
            </Button>
          )
        }
      />
      <div className="mb-4">
        <Segmented
          value={tab}
          onChange={(v) => {
            setOffset(0);
            setTab(v);
          }}
          options={[
            ['activity', t('Activity')],
            ['sessions', t('Sessions')],
          ]}
        />
      </div>
      <ErrorNote message={exporting.error} />
      <Panel bodyClassName="">
        <Filters
          f={f}
          set={set}
          search={search}
          setSearch={(v) => {
            setOffset(0);
            setSearch(v);
          }}
          users={users.data || []}
          actions={res.data?.facets?.actions || Object.keys(ACTION_LABELS)}
          showActivityFilters={tab === 'activity'}
          t={t}
        />
        <div className="flex items-center justify-between px-5 py-3 text-xs text-ink2">
          <span>
            {res.data
              ? t(tab === 'activity' ? '{shown} of {total} entries' : '{shown} of {total} sessions', {
                  shown: Math.min(offset + items.length, total).toLocaleString('en-PH'),
                  total: total.toLocaleString('en-PH'),
                })
              : ' '}
          </span>
          <span className="flex items-center gap-3">
            {res.loading && res.data && <span>{t('Updating…')}</span>}
            {filtered && (
              <Button
                variant="ghost"
                size="sm"
                onClick={() => {
                  setSearch('');
                  setF(NO_FILTERS);
                  setOffset(0);
                }}
              >
                {t('Clear filters')}
              </Button>
            )}
          </span>
        </div>
        <ErrorNote message={res.error} onRetry={res.reload} />
        {!res.data && res.loading ? (
          <Loading />
        ) : (
          <Table
            rows={items}
            columns={tab === 'activity' ? activityColumns : sessionColumns}
            empty={<Empty title={t('Nothing recorded yet')}>{t('Try clearing a filter or widening the date range.')}</Empty>}
          />
        )}
        <Pager total={total} limit={PAGE} offset={offset} onChange={setOffset} loading={res.loading} />
      </Panel>
      <p className="mt-3 text-xs text-muted">
        {t('A session is active until the person signs out, or expired after {days} days without use.', { days: res.data?.session_lifetime_days ?? 90 })}
      </p>
    </div>
  );
}
