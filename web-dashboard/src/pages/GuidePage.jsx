import { useEffect, useState } from 'react';
import { api } from '../api.js';
import { Badge, ErrorNote, Loading, Notice, PageHeader } from '../components/ui.jsx';
import { useAsync } from '../lib.js';

const STAGE_TONE = { Vegetative: 'green', Reproductive: 'orange', Ripening: 'gray' };

/** Example photo from the API, or a placeholder until the group adds one. */
function GuidePhoto({ path, alt }) {
  const [url, setUrl] = useState(null);
  const [failed, setFailed] = useState(false);
  useEffect(() => {
    let alive = true;
    setUrl(null);
    setFailed(false);
    if (path) {
      api
        .guidePhotoUrl(path)
        .then((u) => alive && setUrl(u))
        .catch(() => alive && setFailed(true));
    }
    return () => {
      alive = false;
    };
  }, [path]);
  if (path && url) {
    return (
      <div className="relative aspect-square w-full overflow-hidden rounded-xl border border-line">
        <img src={url} alt={alt} className="absolute inset-0 h-full w-full object-cover" />
      </div>
    );
  }
  return (
    <div className="flex aspect-square w-full items-center justify-center rounded-xl border border-dashed border-line bg-canvas px-4 text-center text-xs text-muted">
      {path && !failed ? 'Loading photo…' : 'Example photo not added yet'}
    </div>
  );
}

function Stages({ stages }) {
  return (
    <div className="flex flex-wrap gap-1.5">
      {stages.map((s) => (
        <Badge key={s} tone={STAGE_TONE[s] || 'gray'}>
          {s}
        </Badge>
      ))}
    </div>
  );
}

/** "What to look for": the four pests the model detects and every damage symptom reviewers check. */
export default function GuidePage() {
  const res = useAsync(() => api.guide(), []);
  const g = res.data;
  return (
    <div>
      <PageHeader
        title="What to look for"
        description="The four pests the system handles and the damage symptoms reviewers tick, with the crop stage when each appears. Farmers see the same guide in the mobile app."
      />
      <ErrorNote message={res.error} onRetry={res.reload} />
      {!g && res.loading && <Loading />}
      {g && (
        <div className="space-y-8">
          <Notice>{g.model_note}</Notice>
          {g.pests.map((p) => (
            <section key={p.key} className="rounded-2xl border border-line bg-white p-5 shadow-sm">
              <div className="grid gap-5 md:grid-cols-[240px_1fr]">
                <GuidePhoto path={p.photo} alt={p.name} />
                <div>
                  <div className="flex flex-wrap items-center gap-2">
                    <h2 className="text-lg font-bold text-ink">{p.name}</h2>
                    <span className="rounded-full bg-canvas px-2 py-0.5 font-mono text-[11px] text-ink2">model class: {p.model_label}</span>
                  </div>
                  <ul className="mt-2 list-disc space-y-1 pl-5 text-sm text-ink">
                    {p.signs.map((s) => (
                      <li key={s}>{s}</li>
                    ))}
                  </ul>
                  <div className="mt-3 text-xs font-semibold uppercase tracking-wide text-ink2">Crop stage when it appears</div>
                  <div className="mt-1">
                    <Stages stages={p.stages} />
                  </div>
                  <p className="mt-1 text-xs text-ink2">{p.stage_note}</p>
                </div>
              </div>
              <div className="mt-5 text-xs font-semibold uppercase tracking-wide text-ink2">Symptoms to check</div>
              <div className="mt-2 grid gap-4 sm:grid-cols-2 xl:grid-cols-3">
                {g.symptoms
                  .filter((s) => s.pest === p.key)
                  .map((s) => (
                    <div key={s.key} className="rounded-xl border border-line p-3">
                      <GuidePhoto path={s.photo} alt={s.name} />
                      <div className="mt-2 text-sm font-bold text-ink">{s.name}</div>
                      <p className="mt-1 text-sm text-ink2">{s.signs}</p>
                      <div className="mt-2">
                        <Stages stages={s.stages} />
                      </div>
                    </div>
                  ))}
              </div>
            </section>
          ))}
        </div>
      )}
    </div>
  );
}
