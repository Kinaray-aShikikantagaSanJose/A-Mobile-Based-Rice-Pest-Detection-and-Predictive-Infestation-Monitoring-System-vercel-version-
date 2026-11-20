import { useEffect, useMemo, useState } from 'react';
import { api } from '../api.js';
import Avatar from '../components/Avatar.jsx';
import Icon from '../components/icons.jsx';
import { Badge, Button, ChipsInput, Drawer, Empty, ErrorNote, Field, Loading, Notice, Panel, PageHeader, Segmented, Select } from '../components/ui.jsx';
import { fmtDate, fmtNum, MUNICIPALITIES, ROLE_LABELS, useAction, useAsync } from '../lib.js';

const ROLE_TONE = { farmer: 'gray', technician: 'blue', agriculturist: 'purple' };
const STATUS_LABELS = { pending: 'Pending', approved: 'Approved', rejected: 'Rejected' };
const STATUS_TONE = { pending: 'orange', approved: 'green', rejected: 'red' };
const ROLE_OPTIONS = Object.entries(ROLE_LABELS);
const UNASSIGNED = 'Unassigned';

const sameList = (a, b) => a.length === b.length && a.every((x, i) => x === b[i]);
const muniOptions = (current) => [...new Set([...MUNICIPALITIES, ...(current ? [current] : [])])];

/** Barangay names people registered with, per municipality, so coverage matches their spelling. */
function useBarangays(users) {
  return useMemo(() => {
    const out = {};
    for (const u of users) {
      if (!u.barangay || !u.municipality) continue;
      const key = u.municipality.toLowerCase();
      (out[key] ||= new Set()).add(u.barangay);
    }
    return (muni) => [...(out[(muni || '').toLowerCase()] || [])].sort();
  }, [users]);
}

function CoverageHint() {
  return (
    <p className="text-xs text-muted">
      Coverage = municipality + barangays. Leave barangays empty to cover the whole municipality. Observations reach the queue of each technician whose coverage
      includes the farmer's barangay.
    </p>
  );
}

// ---------------------------------------------------------------- approval queue

function ApprovalRow({ u, barangaysOf, onDone }) {
  // Starts at the role the person asked for when registering.
  const [role, setRole] = useState(u.role || 'farmer');
  const [municipality, setMunicipality] = useState(u.municipality || '');
  const [coverage, setCoverage] = useState([]);
  const action = useAction();
  const approve = () =>
    action.run(async () => {
      const body = { status: 'approved', role };
      if (municipality && municipality !== u.municipality) body.municipality = municipality;
      if (role === 'technician') body.coverage_barangays = coverage;
      await api.updateUser(u.id, body);
      onDone(`${u.full_name} approved as ${ROLE_LABELS[role].toLowerCase()}.`);
    });
  const reject = () => {
    if (!window.confirm(`Reject ${u.full_name}'s account? They won't be able to use the app or dashboard.`)) return;
    action.run(async () => {
      await api.updateUser(u.id, { status: 'rejected' });
      onDone(`${u.full_name}'s account was rejected.`);
    });
  };
  return (
    <li className="grid gap-4 px-5 py-4 lg:grid-cols-[1.2fr_1.6fr_auto] lg:items-start">
      <div className="min-w-0">
        <div className="flex flex-wrap items-center gap-2">
          <span className="font-semibold text-ink">{u.full_name}</span>
          <Badge tone={ROLE_TONE[u.role] || 'gray'}>Requested: {ROLE_LABELS[u.role] || u.role}</Badge>
        </div>
        <div className="truncate text-sm text-ink2">{u.email}</div>
        <div className="mt-1 text-xs text-ink2">
          {u.phone ? (
            <a href={`tel:${u.phone}`} className="font-semibold text-brand-700">
              {u.phone}
            </a>
          ) : (
            'No phone'
          )}{' '}
          · {[u.barangay, u.municipality].filter(Boolean).join(', ') || 'No area given'}
        </div>
        <div className="text-xs text-muted">Requested {fmtDate(u.created_at)}</div>
      </div>
      <div className="grid gap-3 sm:grid-cols-2">
        <Field label="Approve as">
          <Select value={role} onChange={setRole} options={ROLE_OPTIONS} />
        </Field>
        <Field label="Municipality">
          <Select value={municipality} onChange={setMunicipality} placeholder={municipality ? undefined : 'Not set'} options={muniOptions(u.municipality)} />
        </Field>
        {role === 'technician' && (
          <Field as="div" label="Coverage barangays" className="sm:col-span-2">
            <ChipsInput value={coverage} onChange={setCoverage} placeholder="Whole municipality" suggestions={barangaysOf(municipality)} />
          </Field>
        )}
      </div>
      <div className="flex gap-2 lg:flex-col lg:items-stretch lg:pt-5">
        <Button onClick={approve} busy={action.busy} disabled={!municipality}>
          Approve
        </Button>
        <Button variant="danger" onClick={reject} disabled={action.busy}>
          Reject
        </Button>
      </div>
      {action.error && (
        <div className="lg:col-span-3">
          <ErrorNote message={action.error} />
        </div>
      )}
    </li>
  );
}

function ApprovalQueue({ users, barangaysOf, onDone }) {
  const waiting = users.filter((u) => u.status === 'pending' && u.is_verified);
  const unverified = users.filter((u) => u.status === 'pending' && !u.is_verified).length;
  return (
    <Panel
      className={waiting.length ? 'border-orange-300 ring-1 ring-orange-200' : ''}
      title={`Approval queue (${waiting.length})`}
      subtitle="New accounts can't use the app or dashboard until you approve them. Each person picks a role when registering; confirm it or change it here before approving."
      bodyClassName=""
    >
      {waiting.length ? (
        <ul className="divide-y divide-line">
          {waiting.map((u) => (
            <ApprovalRow key={u.id} u={u} barangaysOf={barangaysOf} onDone={onDone} />
          ))}
        </ul>
      ) : (
        <Empty title="No accounts waiting for approval" />
      )}
      {unverified > 0 && (
        <div className="border-t border-line px-5 py-3 text-xs text-ink2">
          {unverified} more account{unverified === 1 ? ' hasn’t' : 's haven’t'} verified their email yet. They appear here once they do.
        </div>
      )}
    </Panel>
  );
}

// ---------------------------------------------------------------- add / edit an account

const EMAIL_RE = /^[^@\s]+@[^@\s]+\.[^@\s]+$/;
const PHONE_RE = /^\+?[0-9][0-9 -]{5,28}$/;
const MAX_PICTURE = 8 * 1024 * 1024;

function FieldError({ message }) {
  if (!message) return null;
  return <span className="mt-1 block text-xs font-semibold text-red-600">{message}</span>;
}

const invalid = (err) => (err ? 'border-red-400 ring-2 ring-red-100' : '');

/**
 * Drawer to add an account (`u` null) or edit one: picture, name, contact,
 * role, approval, area, coverage, password. Editing also offers Delete.
 */
function UserEditor({ u, barangaysOf, onClose, onDone }) {
  const adding = !u;
  const self = Boolean(u?.is_you);
  const [form, setForm] = useState(() => ({
    full_name: u?.full_name || '',
    email: u?.email || '',
    phone: u?.phone || '',
    role: u?.role || 'farmer',
    status: u?.status || 'approved',
    municipality: u?.municipality || '',
    barangay: u?.barangay || '',
    coverage: u?.coverage_barangays || [],
    password: '',
  }));
  const [errors, setErrors] = useState({});
  const [picture, setPicture] = useState(null); // { file, url } chosen, not uploaded yet
  const [removePicture, setRemovePicture] = useState(false);
  const [confirmDelete, setConfirmDelete] = useState(false);
  const action = useAction();
  const del = useAction();

  useEffect(() => () => picture && URL.revokeObjectURL(picture.url), [picture]);

  const set = (key) => (value) => {
    setForm((f) => ({ ...f, [key]: value }));
    if (errors[key]) setErrors((e) => ({ ...e, [key]: undefined }));
  };

  const choosePicture = (e) => {
    const file = e.target.files?.[0];
    e.target.value = '';
    if (!file) return;
    if (!file.type.startsWith('image/')) {
      setErrors((x) => ({ ...x, picture: 'Choose a picture file (JPG or PNG).' }));
      return;
    }
    if (file.size > MAX_PICTURE) {
      setErrors((x) => ({ ...x, picture: 'That picture is larger than 8 MB.' }));
      return;
    }
    setErrors((x) => ({ ...x, picture: undefined }));
    setRemovePicture(false);
    setPicture({ file, url: URL.createObjectURL(file) });
  };

  const validate = () => {
    const e = {};
    const name = form.full_name.trim();
    const phone = form.phone.trim();
    if (name.length < 2) e.full_name = 'Enter the full name.';
    if (adding && !EMAIL_RE.test(form.email.trim())) e.email = 'Enter a valid email address.';
    if (adding && !phone) e.phone = 'Enter the mobile number.';
    else if (phone && !PHONE_RE.test(phone)) e.phone = 'Enter a valid mobile number, e.g. 0917 123 4567.';
    if (!form.municipality) e.municipality = 'Choose the municipality.';
    if (adding && !form.barangay.trim()) e.barangay = 'Enter the barangay.';
    if (adding && form.password.length < 8) e.password = 'The password needs at least 8 characters.';
    if (!adding && form.password && form.password.length < 8) e.password = 'The new password needs at least 8 characters.';
    return e;
  };

  const save = () => {
    const e = validate();
    setErrors(e);
    if (Object.keys(e).length) {
      action.setError(`Please fix ${Object.keys(e).length === 1 ? 'the highlighted field' : `the ${Object.keys(e).length} highlighted fields`} before saving.`);
      return;
    }
    action.run(async () => {
      let id = u?.id;
      const name = form.full_name.trim();
      if (adding) {
        const created = await api.createUser({
          full_name: name,
          email: form.email.trim(),
          phone: form.phone.trim(),
          password: form.password,
          role: form.role,
          municipality: form.municipality,
          barangay: form.barangay.trim(),
          coverage_barangays: form.role === 'technician' ? form.coverage : [],
        });
        id = created.id;
      } else {
        const changes = {};
        if (name !== u.full_name) changes.full_name = name;
        if (form.phone.trim() !== (u.phone || '')) changes.phone = form.phone.trim();
        if (form.role !== u.role) changes.role = form.role;
        if (form.status !== u.status) changes.status = form.status;
        if (form.municipality !== u.municipality) changes.municipality = form.municipality;
        if (form.barangay.trim() !== u.barangay) changes.barangay = form.barangay.trim();
        if (!sameList(form.coverage, u.coverage_barangays)) changes.coverage_barangays = form.coverage;
        if (form.password) changes.new_password = form.password;
        if (Object.keys(changes).length) await api.updateUser(u.id, changes);
      }
      if (picture) await api.setUserAvatar(id, picture.file);
      else if (removePicture && u?.avatar_url) await api.clearUserAvatar(id);
      onDone(adding ? `${name}'s account was created.` : `${name || u.email} updated.`);
    });
  };

  const remove = () =>
    del.run(async () => {
      await api.deleteUser(u.id);
      onDone(`${u.full_name || u.email}'s account was deleted.`);
    });

  const selfTitle = self ? "You can't change your own role or approval" : undefined;
  const shownPicture = removePicture ? null : u?.avatar_url;

  return (
    <Drawer open onClose={onClose} title={adding ? 'Add an account' : 'Edit account'} subtitle={adding ? 'Active right away: no email code needed.' : u.email} width="max-w-xl">
      <form
        noValidate
        className="space-y-5"
        onSubmit={(e) => {
          e.preventDefault();
          save();
        }}
      >
        <section className="flex items-center gap-4 rounded-2xl border border-line bg-white p-4">
          <Avatar path={shownPicture} preview={picture?.url} name={form.full_name || form.email} size="lg" />
          <div className="min-w-0 space-y-2">
            <div className="text-sm font-semibold text-ink">Profile picture</div>
            <div className="flex flex-wrap gap-2">
              <label className="inline-flex cursor-pointer items-center gap-2 rounded-lg bg-brand-700 px-4 py-2 text-sm font-semibold text-white transition-colors hover:bg-brand-800">
                <Icon name="camera" className="h-4 w-4" />
                {shownPicture || picture ? 'Change picture' : 'Upload picture'}
                <input type="file" accept="image/*" className="sr-only" onChange={choosePicture} />
              </label>
              {(picture || shownPicture) && (
                <Button
                  variant="secondary"
                  onClick={() => {
                    setPicture(null);
                    if (u?.avatar_url) setRemovePicture(true);
                  }}
                >
                  Remove
                </Button>
              )}
            </div>
            <FieldError message={errors.picture} />
            <p className="text-xs text-muted">JPG or PNG, up to 8 MB. Cropped to a square.</p>
          </div>
        </section>

        <section className="grid gap-4 rounded-2xl border border-line bg-white p-4 sm:grid-cols-2">
          <Field label="Full name *" className="sm:col-span-2">
            <input className={`input ${invalid(errors.full_name)}`} value={form.full_name} onChange={(e) => set('full_name')(e.target.value)} maxLength={100} />
            <FieldError message={errors.full_name} />
          </Field>
          <Field label={adding ? 'Email *' : 'Email'} hint={adding ? undefined : "The email is the sign-in name and links the person's records, so it can't be changed."}>
            <input
              className={`input ${invalid(errors.email)}`}
              type="email"
              value={form.email}
              disabled={!adding}
              onChange={(e) => set('email')(e.target.value)}
              maxLength={255}
              autoComplete="off"
            />
            <FieldError message={errors.email} />
          </Field>
          <Field label={adding ? 'Mobile number *' : 'Mobile number'}>
            <input className={`input ${invalid(errors.phone)}`} value={form.phone} onChange={(e) => set('phone')(e.target.value)} maxLength={30} placeholder="0917 123 4567" />
            <FieldError message={errors.phone} />
          </Field>
          <Field label="Role">
            <Select value={form.role} onChange={set('role')} options={ROLE_OPTIONS} disabled={self} title={selfTitle} />
          </Field>
          {!adding && (
            <Field label="Status">
              <Select value={form.status} onChange={set('status')} options={Object.entries(STATUS_LABELS)} disabled={self} title={selfTitle} />
            </Field>
          )}
          <Field label="Municipality *">
            <Select
              value={form.municipality}
              onChange={set('municipality')}
              placeholder={form.municipality ? undefined : 'Choose…'}
              options={muniOptions(u?.municipality)}
              className={invalid(errors.municipality)}
            />
            <FieldError message={errors.municipality} />
          </Field>
          <Field label={adding ? 'Barangay *' : 'Barangay'}>
            <input className={`input ${invalid(errors.barangay)}`} value={form.barangay} onChange={(e) => set('barangay')(e.target.value)} maxLength={100} />
            <FieldError message={errors.barangay} />
          </Field>
          {form.role === 'technician' && (
            <Field as="div" label="Coverage barangays" className="sm:col-span-2">
              <ChipsInput value={form.coverage} onChange={set('coverage')} placeholder="Whole municipality" suggestions={barangaysOf(form.municipality)} />
              <div className="mt-1">
                <CoverageHint />
              </div>
            </Field>
          )}
          <Field
            label={adding ? 'Password *' : 'New password'}
            hint={adding ? 'Give it to the person; they sign in with it in the app or here.' : 'Leave empty to keep the current password.'}
            className="sm:col-span-2"
          >
            <input
              className={`input ${invalid(errors.password)}`}
              type="password"
              value={form.password}
              onChange={(e) => set('password')(e.target.value)}
              maxLength={72}
              autoComplete="new-password"
              placeholder={adding ? 'At least 8 characters' : '••••••••'}
            />
            <FieldError message={errors.password} />
          </Field>
        </section>

        <ErrorNote message={action.error} />

        <div className="flex flex-wrap items-center justify-between gap-3 border-t border-line pt-4">
          {!adding && !self ? (
            <Button variant="danger" size="lg" onClick={() => setConfirmDelete(true)} disabled={action.busy || del.busy}>
              <Icon name="trash" className="h-4 w-4" />
              Delete account
            </Button>
          ) : (
            <span />
          )}
          <div className="flex gap-2">
            <Button variant="secondary" size="lg" onClick={onClose}>
              Cancel
            </Button>
            <Button type="submit" size="lg" busy={action.busy}>
              {adding ? 'Create account' : 'Save changes'}
            </Button>
          </div>
        </div>

        {confirmDelete && (
          <div role="alertdialog" className="animate-fade-in space-y-3 rounded-2xl border border-red-200 bg-red-50 p-4 text-sm text-red-800">
            <p>
              <b>Delete {u.full_name || u.email}?</b> They can no longer sign in to the app or the dashboard. Their {fmtNum(u.observations)} observation
              {u.observations === 1 ? '' : 's'} stay in the records and reports. This can't be undone.
            </p>
            <ErrorNote message={del.error} />
            <div className="flex justify-end gap-2">
              <Button variant="secondary" onClick={() => setConfirmDelete(false)} disabled={del.busy}>
                Keep the account
              </Button>
              <Button variant="destructive" onClick={remove} busy={del.busy}>
                Yes, delete it
              </Button>
            </div>
          </div>
        )}
      </form>
    </Drawer>
  );
}

// ---------------------------------------------------------------- accounts table

function UserRow({ u, onEdit, onDelete }) {
  const area = [u.barangay, u.municipality].filter(Boolean).join(', ');
  return (
    <tr className="border-b border-line/70 align-middle last:border-0 hover:bg-brand-50/40">
      <td className="td">
        <div className="flex items-center gap-3">
          <Avatar path={u.avatar_url} name={u.full_name || u.email} />
          <div className="min-w-0">
            <div className="font-medium text-ink">
              {u.full_name}
              {u.is_you && <span className="ml-2 text-xs font-normal text-ink2">(you)</span>}
            </div>
            <div className="text-xs text-ink2">{u.email}</div>
            <div className="text-xs text-ink2">{u.phone || 'No phone'}</div>
            <div className="text-xs text-muted">
              Joined {fmtDate(u.created_at)} · {fmtNum(u.observations)} observation{u.observations === 1 ? '' : 's'}
            </div>
          </div>
        </div>
      </td>
      <td className="td">
        <Badge tone={ROLE_TONE[u.role] || 'gray'}>{ROLE_LABELS[u.role] || u.role}</Badge>
      </td>
      <td className="td">
        <Badge tone={STATUS_TONE[u.status] || 'gray'}>{STATUS_LABELS[u.status] || u.status}</Badge>
        {!u.is_verified && (
          <div className="mt-1">
            <Badge tone="orange">Email not verified</Badge>
          </div>
        )}
      </td>
      <td className="td text-ink2">{area || <span className="text-muted">Not set</span>}</td>
      <td className="td max-w-[220px] text-xs text-ink2">
        {u.role === 'technician' ? (u.coverage_barangays.length ? u.coverage_barangays.join(', ') : 'Whole municipality') : <span className="text-muted">—</span>}
      </td>
      <td className="td">
        <div className="flex justify-end gap-2">
          <Button variant="secondary" onClick={() => onEdit(u)} aria-label={`Edit ${u.full_name}`}>
            <Icon name="edit" className="h-4 w-4" />
            Edit
          </Button>
          {!u.is_you && (
            <Button variant="danger" onClick={() => onDelete(u)} aria-label={`Delete ${u.full_name}`} title="Delete account">
              <Icon name="trash" className="h-4 w-4" />
            </Button>
          )}
        </div>
      </td>
    </tr>
  );
}

function AccountsTable({ users, barangaysOf, onSaved }) {
  const [search, setSearch] = useState('');
  const [role, setRole] = useState('');
  const [status, setStatus] = useState('');
  const [muni, setMuni] = useState('');
  const [editing, setEditing] = useState(null); // null | 'new' | user
  const [deleting, setDeleting] = useState(null);
  const s = search.trim().toLowerCase();
  const shown = users.filter(
    (u) =>
      (!role || u.role === role) &&
      (!status || u.status === status) &&
      (!muni || u.municipality === muni) &&
      (!s || `${u.full_name} ${u.email} ${u.phone} ${u.barangay}`.toLowerCase().includes(s)),
  );
  const counts = users.reduce((acc, u) => ({ ...acc, [u.role]: (acc[u.role] || 0) + 1 }), {});
  const done = (message) => {
    setEditing(null);
    setDeleting(null);
    onSaved(message);
  };
  return (
    <Panel bodyClassName="">
      <div className="grid gap-3 border-b border-line p-5 md:grid-cols-[1fr_180px_160px_200px_auto] md:items-end">
        <Field label="Search">
          <input className="input" value={search} onChange={(e) => setSearch(e.target.value)} placeholder="Name, email, phone, barangay…" />
        </Field>
        <Field label="Role">
          <Select value={role} onChange={setRole} placeholder="All roles" options={ROLE_OPTIONS.map(([v, l]) => [v, `${l} (${counts[v] || 0})`])} />
        </Field>
        <Field label="Status">
          <Select value={status} onChange={setStatus} placeholder="All" options={Object.entries(STATUS_LABELS)} />
        </Field>
        <Field label="Municipality">
          <Select value={muni} onChange={setMuni} placeholder="All" options={[...new Set(users.map((u) => u.municipality).filter(Boolean))].sort()} />
        </Field>
        <Button size="lg" onClick={() => setEditing('new')}>
          <Icon name="userPlus" className="h-4 w-4" />
          Add account
        </Button>
      </div>
      <div className="overflow-x-auto">
        <table className="w-full text-sm">
          <thead className="border-b border-line bg-canvas/60">
            <tr>
              {['Account', 'Role', 'Status', 'Area', 'Coverage barangays', ''].map((h, i) => (
                <th key={h || i} className="th">
                  {h}
                </th>
              ))}
            </tr>
          </thead>
          <tbody>
            {shown.map((u) => (
              <UserRow key={u.id} u={u} onEdit={setEditing} onDelete={setDeleting} />
            ))}
          </tbody>
        </table>
        {!shown.length && <Empty title="No accounts match" />}
      </div>
      <div className="border-t border-line px-5 py-3 text-xs text-muted">
        <Badge tone={ROLE_TONE.technician}>Technician</Badge> validates observations in their coverage ·{' '}
        <Badge tone={ROLE_TONE.agriculturist}>Agriculturist</Badge> sees every area, resolves escalations and manages this dashboard.
      </div>
      {editing && <UserEditor u={editing === 'new' ? null : editing} barangaysOf={barangaysOf} onClose={() => setEditing(null)} onDone={done} />}
      {deleting && <DeleteDialog u={deleting} onClose={() => setDeleting(null)} onDone={done} />}
    </Panel>
  );
}

/** Confirmation for the trash button in a table row. */
function DeleteDialog({ u, onClose, onDone }) {
  const del = useAction();
  useEffect(() => {
    const onKey = (e) => e.key === 'Escape' && onClose();
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [onClose]);
  const remove = () =>
    del.run(async () => {
      await api.deleteUser(u.id);
      onDone(`${u.full_name || u.email}'s account was deleted.`);
    });
  return (
    <div className="fixed inset-0 z-[2000] flex items-center justify-center p-4">
      <div className="absolute inset-0 animate-fade-in bg-ink/40" onClick={onClose} />
      <div role="alertdialog" aria-modal="true" className="relative w-full max-w-md animate-fade-up rounded-2xl bg-white p-6 shadow-2xl">
        <div className="flex items-start gap-4">
          <span className="flex h-12 w-12 shrink-0 items-center justify-center rounded-full bg-red-50 text-red-600">
            <Icon name="trash" className="h-6 w-6" />
          </span>
          <div className="min-w-0">
            <h2 className="text-lg font-bold text-ink">Delete this account?</h2>
            <div className="mt-2 flex items-center gap-2">
              <Avatar path={u.avatar_url} name={u.full_name || u.email} size="sm" />
              <div className="min-w-0">
                <div className="truncate text-sm font-semibold text-ink">{u.full_name}</div>
                <div className="truncate text-xs text-ink2">{u.email}</div>
              </div>
            </div>
            <p className="mt-3 text-sm text-ink2">
              They can no longer sign in to the app or the dashboard. Their {fmtNum(u.observations)} observation{u.observations === 1 ? '' : 's'} stay in the
              records and reports. This can't be undone.
            </p>
          </div>
        </div>
        <div className="mt-4">
          <ErrorNote message={del.error} />
        </div>
        <div className="mt-5 flex justify-end gap-2">
          <Button variant="secondary" size="lg" onClick={onClose} disabled={del.busy}>
            Cancel
          </Button>
          <Button variant="destructive" size="lg" onClick={remove} busy={del.busy}>
            Delete account
          </Button>
        </div>
      </div>
    </div>
  );
}

// ---------------------------------------------------------------- coverage grid

function AreaCard({ a }) {
  const covered = a.technicians.length > 0;
  const unassigned = a.area === UNASSIGNED;
  return (
    <div className={`rounded-2xl border bg-white p-4 shadow-sm ${covered || unassigned ? 'border-line' : 'border-orange-300'}`}>
      <div className="flex items-start justify-between gap-2">
        <h3 className="font-bold text-ink">{a.area}</h3>
        {!unassigned && (covered ? <Badge tone="green">Covered</Badge> : <Badge tone="orange">No technician</Badge>)}
      </div>
      <ul className="mt-2 space-y-1.5 text-sm">
        {a.technicians.map((t) => (
          <li key={t.email} title={t.email}>
            <div className="truncate font-medium text-ink">{t.full_name || t.email}</div>
            <div className="flex flex-wrap gap-1">
              {t.coverage.length ? (
                t.coverage.map((b) => (
                  <span key={b} className="rounded-full bg-brand-100 px-2 py-0.5 text-[11px] font-semibold text-brand-900">
                    {b}
                  </span>
                ))
              ) : (
                <span className="text-xs text-ink2">Whole municipality</span>
              )}
            </div>
          </li>
        ))}
        {a.agriculturists.map((t) => (
          <li key={t.email} className="truncate text-ink2" title={t.email}>
            {t.full_name || t.email} <span className="text-xs">(agriculturist)</span>
          </li>
        ))}
      </ul>
      <div className="mt-3 grid grid-cols-4 gap-2 border-t border-line pt-3 text-center">
        {[
          ['Farmers', a.farmers, ''],
          ['Obs.', a.observations, ''],
          ['Pending', a.pending, 'text-orange-600'],
          ['Escalated', a.escalated, 'text-violet-700'],
        ].map(([label, n, tone]) => (
          <div key={label}>
            <div className={`text-base font-bold tabular-nums ${n ? tone || 'text-ink' : 'text-ink'}`}>{fmtNum(n)}</div>
            <div className="text-[10px] uppercase tracking-wide text-muted">{label}</div>
          </div>
        ))}
      </div>
    </div>
  );
}

function CoverageGrid() {
  const areas = useAsync(() => api.areas(), []);
  const list = areas.data || [];
  const uncovered = list.filter((a) => a.area !== UNASSIGNED && !a.technicians.length);
  return (
    <div>
      <ErrorNote message={areas.error} onRetry={areas.reload} />
      {!areas.data && areas.loading && <Loading />}
      {areas.data && (
        <>
          <div className="mb-4 space-y-3">
            {uncovered.length > 0 && (
              <Notice tone="orange">
                {uncovered.length} municipalit{uncovered.length === 1 ? 'y has' : 'ies have'} no technician: {uncovered.map((a) => a.area).join(', ')}. Observations
                from there wait in no one's queue. Assign a technician under Accounts.
              </Notice>
            )}
            <CoverageHint />
          </div>
          <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3 2xl:grid-cols-4">
            {list.map((a) => (
              <AreaCard key={a.area} a={a} />
            ))}
          </div>
        </>
      )}
    </div>
  );
}

export default function UsersPage({ onChanged }) {
  const [tab, setTab] = useState('accounts');
  const [coverageKey, setCoverageKey] = useState(0);
  const users = useAsync(() => api.users(), []);
  const [notice, setNotice] = useState('');
  const list = users.data || [];
  const barangaysOf = useBarangays(list);

  const done = (message) => {
    setNotice(`${message} Changes apply right away, in the app and on the dashboard.`);
    users.reload();
    setCoverageKey((k) => k + 1);
    onChanged?.();
  };

  return (
    <div>
      <PageHeader
        title="User management"
        description="Approve new accounts; add, edit or delete accounts (details, role, profile picture, password); and set the municipality and barangays a technician covers. Coverage decides whose queue an observation lands in."
      />
      {notice && (
        <div className="mb-4">
          <Notice>{notice}</Notice>
        </div>
      )}
      <ErrorNote message={users.error} onRetry={users.reload} />
      {!users.data && users.loading && <Loading />}
      {users.data && (
        <div className="space-y-6">
          <ApprovalQueue users={list} barangaysOf={barangaysOf} onDone={done} />
          <Segmented
            value={tab}
            onChange={setTab}
            options={[
              ['accounts', `Accounts (${list.length})`],
              ['coverage', 'Coverage by municipality'],
            ]}
          />
          {tab === 'accounts' ? <AccountsTable users={list} barangaysOf={barangaysOf} onSaved={done} /> : <CoverageGrid key={coverageKey} />}
        </div>
      )}
    </div>
  );
}
