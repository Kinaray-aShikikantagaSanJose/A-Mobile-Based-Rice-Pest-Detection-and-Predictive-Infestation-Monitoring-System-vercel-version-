import { useEffect, useRef, useState } from 'react';
import Icon from './icons.jsx';

const countLabel = (n) => (n > 99 ? '99+' : String(n));

/**
 * Bell in the top bar. A pulsing red bullet shows when new observations
 * arrived since the person last looked; the panel lists what's waiting.
 * `items`: [{ id, icon, tone, text, page }] (page = where "Open" goes).
 */
export default function NotificationBell({ fresh, items, onOpenPage, onMarkSeen }) {
  const [open, setOpen] = useState(false);
  const ref = useRef(null);
  const waiting = items.filter((i) => i.count > 0);
  const total = fresh + waiting.reduce((a, i) => a + (i.alert ? i.count : 0), 0);

  useEffect(() => {
    if (!open) return undefined;
    const onDown = (e) => ref.current && !ref.current.contains(e.target) && setOpen(false);
    const onKey = (e) => e.key === 'Escape' && setOpen(false);
    window.addEventListener('mousedown', onDown);
    window.addEventListener('keydown', onKey);
    return () => {
      window.removeEventListener('mousedown', onDown);
      window.removeEventListener('keydown', onKey);
    };
  }, [open]);

  const go = (page) => {
    setOpen(false);
    onOpenPage(page);
  };

  return (
    <div className="relative" ref={ref}>
      <button
        type="button"
        onClick={() => setOpen((o) => !o)}
        aria-label={fresh ? `${fresh} new submission${fresh === 1 ? '' : 's'}` : 'Notifications'}
        aria-expanded={open}
        className="relative rounded-full p-2 text-ink2 transition hover:bg-canvas hover:text-ink focus:outline-none focus-visible:ring-2 focus-visible:ring-brand-600"
      >
        <Icon name="bell" className="h-[22px] w-[22px]" />
        {total > 0 && (
          <span className="absolute right-1 top-1 flex h-3 w-3">
            {fresh > 0 && <span className="absolute inline-flex h-full w-full animate-ping rounded-full bg-red-500 opacity-75" />}
            <span className="relative inline-flex h-3 w-3 rounded-full bg-red-600 ring-2 ring-white" />
          </span>
        )}
      </button>

      {open && (
        <div className="absolute right-0 top-12 z-[1700] w-[330px] max-w-[calc(100vw-2rem)] animate-fade-in overflow-hidden rounded-2xl border border-line bg-white shadow-2xl">
          <div className="flex items-center justify-between border-b border-line px-4 py-3">
            <span className="text-sm font-bold text-ink">Notifications</span>
            {fresh > 0 && (
              <button type="button" onClick={onMarkSeen} className="text-xs font-semibold text-brand-700 hover:underline">
                Mark as seen
              </button>
            )}
          </div>
          <ul className="max-h-[360px] divide-y divide-line overflow-y-auto">
            {fresh > 0 && (
              <li className="flex items-start gap-3 bg-red-50/60 px-4 py-3">
                <span className="mt-1.5 h-2.5 w-2.5 shrink-0 rounded-full bg-red-600" />
                <div className="min-w-0 flex-1">
                  <div className="text-sm font-semibold text-ink">
                    {countLabel(fresh)} new submission{fresh === 1 ? '' : 's'}
                  </div>
                  <div className="text-xs text-ink2">Sent from the field since you last checked.</div>
                </div>
              </li>
            )}
            {waiting.map((i) => (
              <li key={i.id}>
                <button type="button" onClick={() => go(i.page)} className="flex w-full items-start gap-3 px-4 py-3 text-left hover:bg-canvas">
                  <span className={`mt-1.5 h-2.5 w-2.5 shrink-0 rounded-full ${i.tone}`} />
                  <span className="min-w-0 flex-1 text-sm text-ink">{i.text}</span>
                  <Icon name="chevronRight" className="mt-0.5 h-4 w-4 text-muted" />
                </button>
              </li>
            ))}
            {!fresh && !waiting.length && <li className="px-4 py-8 text-center text-sm text-ink2">You're all caught up.</li>}
          </ul>
        </div>
      )}
    </div>
  );
}

/** Small message in the corner when a new submission arrives while the dashboard is open. */
export function Toast({ toast, onClose, onAction }) {
  useEffect(() => {
    if (!toast) return undefined;
    const t = setTimeout(onClose, 8000);
    return () => clearTimeout(t);
  }, [toast, onClose]);
  if (!toast) return null;
  return (
    <div role="status" className="fixed bottom-5 right-5 z-[2300] w-[340px] max-w-[calc(100vw-2.5rem)] animate-fade-up">
      <div className="flex items-start gap-3 rounded-2xl border border-line bg-white p-4 shadow-2xl ring-1 ring-black/5">
        <span className="relative mt-0.5 flex h-9 w-9 shrink-0 items-center justify-center rounded-full bg-red-50 text-red-600">
          <Icon name="bell" className="h-[18px] w-[18px]" />
          <span className="absolute right-0 top-0 h-2.5 w-2.5 rounded-full bg-red-600 ring-2 ring-white" />
        </span>
        <div className="min-w-0 flex-1">
          <div className="text-sm font-bold text-ink">{toast.title}</div>
          <div className="text-xs text-ink2">{toast.text}</div>
          {toast.page && (
            <button type="button" onClick={onAction} className="mt-2 text-xs font-bold text-brand-700 hover:underline">
              {toast.action || 'Open'}
            </button>
          )}
        </div>
        <button type="button" onClick={onClose} aria-label="Dismiss" className="rounded-lg p-1 text-muted hover:bg-canvas hover:text-ink">
          <Icon name="x" className="h-4 w-4" />
        </button>
      </div>
    </div>
  );
}
