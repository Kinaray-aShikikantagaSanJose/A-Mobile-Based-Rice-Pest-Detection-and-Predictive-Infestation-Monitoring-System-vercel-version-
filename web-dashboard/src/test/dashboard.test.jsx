// @vitest-environment jsdom
import fs from 'node:fs';
import path from 'node:path';
import { act, cleanup, fireEvent, render, screen } from '@testing-library/react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { api, clearSession, LIVE_DATA, SAVED_DATA, setToken } from '../api.js';
import { meaningful } from '../components/ReviewForm.jsx';
import Sidebar from '../components/Sidebar.jsx';
import { ConfirmDialog, Pager, RelevanceBadge, StatusBadge, Table, useConfirm } from '../components/ui.jsx';
import { I18nProvider, setLanguage, translate } from '../i18n/index.jsx';
import { TRANSLATIONS } from '../i18n/strings.js';

afterEach(() => {
  cleanup();
  vi.restoreAllMocks();
});

const wrap = (ui) => render(<I18nProvider>{ui}</I18nProvider>);

// ---------------------------------------------------------------- translations

describe('translations', () => {
  const placeholders = (s) => [...s.matchAll(/\{(\w+)\}/g)].map((m) => m[1]).sort().join(',');

  it('every entry has Filipino and Kinaray-a with the same placeholders', () => {
    for (const [key, entry] of Object.entries(TRANSLATIONS)) {
      expect(entry.fil, key).toBeTruthy();
      expect(entry.krj, key).toBeTruthy();
      expect(placeholders(entry.fil), `${key} (fil)`).toBe(placeholders(key));
      expect(placeholders(entry.krj), `${key} (krj)`).toBe(placeholders(key));
    }
  });

  it('every literal t() key in the source has a translation', () => {
    const files = [];
    const walk = (d) => {
      for (const f of fs.readdirSync(d)) {
        const p = path.join(d, f);
        if (fs.statSync(p).isDirectory()) {
          if (!['i18n', 'test'].includes(f)) walk(p);
        } else if (/\.(jsx?)$/.test(f)) files.push(p);
      }
    };
    walk(path.resolve(__dirname, '..'));
    const re = /\b(?:t|tr|translate)\(\s*(['"])((?:\\.|(?!\1).)*)\1/g;
    const missing = [];
    for (const f of files) {
      for (const m of fs.readFileSync(f, 'utf8').matchAll(re)) {
        const key = m[2].replace(/\\(['"\\])/g, '$1');
        if (!TRANSLATIONS[key]) missing.push(`${path.basename(f)}: ${key}`);
      }
    }
    expect(missing).toEqual([]);
  });

  it('queue statuses use the unified names in every language', () => {
    expect(translate('Not Validated', null, 'fil')).toBe('Hindi pa Na-validate');
    expect(translate('To Be Validated', null, 'krj')).toBe('Pagavalidaron pa');
    wrap(<StatusBadge status="escalated" />);
    expect(screen.getByText('To Be Validated')).toBeTruthy();
  });
});

// ---------------------------------------------------------------- dialogs

describe('ConfirmDialog', () => {
  it('confirms, cancels, and closes with Escape', () => {
    const onConfirm = vi.fn();
    const onCancel = vi.fn();
    wrap(<ConfirmDialog open title="Sign out?" message="Really?" confirmLabel="Sign out" onConfirm={onConfirm} onCancel={onCancel} />);
    expect(screen.getByRole('alertdialog')).toBeTruthy();
    fireEvent.click(screen.getByText('Sign out'));
    expect(onConfirm).toHaveBeenCalledTimes(1);
    fireEvent.click(screen.getByText('Cancel'));
    fireEvent.keyDown(window, { key: 'Escape' });
    expect(onCancel).toHaveBeenCalledTimes(2);
  });

  it('renders nothing when closed', () => {
    wrap(<ConfirmDialog open={false} title="x" onConfirm={() => {}} onCancel={() => {}} />);
    expect(screen.queryByRole('alertdialog')).toBeNull();
  });

  it('useConfirm resolves with the answer', async () => {
    let ask;
    function Probe() {
      const [confirm, dialog] = useConfirm();
      ask = confirm;
      return dialog;
    }
    wrap(<Probe />);
    let answer;
    await act(async () => {
      ask({ title: 'Delete this option?' }).then((a) => {
        answer = a;
      });
    });
    fireEvent.click(screen.getByText('Confirm'));
    await act(async () => {});
    expect(answer).toBe(true);
  });
});

describe('sign-out and sidebar', () => {
  const groups = [{ group: 'Field work', items: [{ id: 'queue', label: 'Validation queue', icon: 'queue' }] }];
  const viewer = { role: 'technician', full_name: 'Tech', email: 't@x.ph' };

  it('the sidebar sign-out button only asks the shell (no direct sign-out)', () => {
    const onSignOut = vi.fn();
    wrap(<Sidebar groups={groups} currentId="queue" badges={{}} viewer={viewer} collapsed={false} onNavigate={() => {}} onSignOut={onSignOut} mobileOpen={false} onCloseMobile={() => {}} />);
    fireEvent.click(screen.getAllByLabelText('Sign out')[0]);
    expect(onSignOut).toHaveBeenCalledTimes(1);
  });

  it('nothing in the sidebar toggles the collapsed panel', () => {
    wrap(<Sidebar groups={groups} currentId="queue" badges={{}} viewer={viewer} collapsed onNavigate={() => {}} onSignOut={() => {}} mobileOpen={false} onCloseMobile={() => {}} />);
    expect(screen.queryByLabelText(/collapse sidebar|expand sidebar/i)).toBeNull();
  });
});

// ---------------------------------------------------------------- paging, flags

describe('Pager', () => {
  it('shows the range and moves by one page', () => {
    const onChange = vi.fn();
    wrap(<Pager total={120} limit={50} offset={50} onChange={onChange} />);
    expect(screen.getByText('51–100 of 120')).toBeTruthy();
    fireEvent.click(screen.getByText('Next'));
    fireEvent.click(screen.getByText('Previous'));
    expect(onChange.mock.calls).toEqual([[100], [0]]);
  });

  it('disables Next on the last page', () => {
    wrap(<Pager total={120} limit={50} offset={100} onChange={() => {}} />);
    expect(screen.getByText('Next').closest('button').disabled).toBe(true);
  });
});

describe('table pagination', () => {
  it('shows 30 rows per page and advances to the next page', () => {
    const rows = Array.from({ length: 31 }, (_, id) => ({ id, name: `Row ${id + 1}` }));
    wrap(<Table rows={rows} columns={[{ key: 'name', label: 'Name' }]} />);

    expect(screen.getAllByRole('row')).toHaveLength(31);
    expect(screen.getByText('1–30 of 31')).toBeTruthy();

    fireEvent.click(screen.getByText('Next'));
    expect(screen.getAllByRole('row')).toHaveLength(2);
    expect(screen.getByText('Row 31')).toBeTruthy();
    expect(screen.getByText('31–31 of 31')).toBeTruthy();
  });
});

describe('relevance flag', () => {
  it('only shows for possibly unrelated photos', () => {
    const { container } = wrap(<RelevanceBadge relevance="relevant" />);
    expect(container.textContent).toBe('');
    wrap(<RelevanceBadge relevance="possibly_unrelated" />);
    expect(screen.getByText('Possibly unrelated photo')).toBeTruthy();
  });
});

describe('reviewer note rule (same as the server)', () => {
  it('rejects empty and filler notes, accepts real ones', () => {
    for (const bad of ['', 'ok', '..........', 'aaaaaaaaaaaa', 'good']) expect(meaningful(bad), bad).toBe(false);
    expect(meaningful('Counted 6 bugs on two panicles')).toBe(true);
    expect(meaningful('Malabo ang litrato', 6)).toBe(true);
  });
});

// ---------------------------------------------------------------- network: saved data

describe('saved data when the network drops', () => {
  beforeEach(() => {
    localStorage.clear();
    localStorage.setItem('rp_last_email', 'agri@x.ph');
    setToken('token-1', 'refresh-1', true);
    setLanguage('en');
  });

  const ok = (body, headers = {}) =>
    Promise.resolve(new Response(JSON.stringify(body), { status: 200, headers: { 'Content-Type': 'application/json', ...headers } }));

  it('returns the last saved answer instead of failing, and says so', async () => {
    const fetchMock = vi.spyOn(globalThis, 'fetch').mockImplementationOnce(() => ok({ rows: [{ id: 1 }], total: 1 }));
    const live = vi.fn();
    window.addEventListener(LIVE_DATA, live);
    expect((await api.records({ status: 'all' })).total).toBe(1);
    expect(live).toHaveBeenCalled();
    expect(fetchMock.mock.calls[0][1].headers['X-Palay-Language']).toBe('en');

    fetchMock.mockImplementationOnce(() => Promise.reject(new TypeError('Failed to fetch')));
    const saved = vi.fn();
    window.addEventListener(SAVED_DATA, saved);
    const again = await api.records({ status: 'all' });
    expect(again.rows).toEqual([{ id: 1 }]);
    expect(saved).toHaveBeenCalledTimes(1);
    expect(saved.mock.calls[0][0].detail.savedAt).toBeTruthy();
  });

  it('fails normally when nothing was saved, and sign-out clears saved data', async () => {
    vi.spyOn(globalThis, 'fetch').mockImplementation(() => Promise.reject(new TypeError('Failed to fetch')));
    await expect(api.records({ status: 'validated' })).rejects.toMatchObject({ kind: 'network' });
    localStorage.setItem('rp_cache:agri@x.ph|en|/x', '{"savedAt":"2026-11-27","data":1}');
    clearSession();
    expect(Object.keys(localStorage).filter((k) => k.startsWith('rp_cache:'))).toEqual([]);
  });

  it('paged lists read the total from X-Total-Count', async () => {
    vi.spyOn(globalThis, 'fetch').mockImplementationOnce(() => ok([{ id: 7 }], { 'X-Total-Count': '42' }));
    const page = await api.usersPage({ limit: 1 });
    expect(page).toEqual({ items: [{ id: 7 }], total: 42 });
  });

  it('exports ask for every matching row in the chosen language', async () => {
    setLanguage('krj');
    const fetchMock = vi.spyOn(globalThis, 'fetch').mockImplementationOnce(() =>
      Promise.resolve(new Response('a,b\n', { status: 200 })),
    );
    globalThis.URL.createObjectURL = vi.fn(() => 'blob:x');
    globalThis.URL.revokeObjectURL = vi.fn();
    await api.downloadReport('records', { status: 'all', pest: 'Rice Bug', limit: undefined }, 'x.csv');
    const url = fetchMock.mock.calls[0][0];
    expect(url).toContain('/dashboard/reports/records?');
    expect(url).toContain('lang=krj');
    expect(url).toContain('pest=Rice+Bug');
    expect(url).not.toContain('limit=');
    setLanguage('en');
  });
});
