import { fmtNum, quarterLabel } from '../lib.js';

/** Past quarters as bars (validated observations or pests counted); the selected one is highlighted and bars are clickable. */
export function QuarterBars({ quarters, selected, onSelect, metric = 'records' }) {
  if (!quarters.length) return null;
  const max = Math.max(...quarters.map((q) => q[metric]), 1);
  return (
    <div className="flex h-44 items-end gap-3">
      {quarters.map((q) => {
        const active = q.quarter === selected;
        return (
          <button
            key={q.quarter}
            type="button"
            onClick={() => onSelect(q.quarter)}
            className="group flex h-full min-w-0 flex-1 flex-col items-center justify-end gap-1"
            title={`${quarterLabel(q.quarter)}: ${q.records} validated observations, ${q.pests} pests counted`}
          >
            <span className={`text-xs font-semibold tabular-nums ${active ? 'text-brand-900' : 'text-ink2'}`}>{fmtNum(q[metric])}</span>
            <span
              className={`w-full max-w-[56px] rounded-t-md transition-colors ${active ? 'bg-brand-700' : 'bg-brand-200 group-hover:bg-brand-600'}`}
              style={{ height: `${Math.max((q[metric] / max) * 100, 2)}%` }}
            />
            <span className={`truncate text-[11px] ${active ? 'font-bold text-ink' : 'text-muted'}`}>{quarterLabel(q.quarter)}</span>
          </button>
        );
      })}
    </div>
  );
}
