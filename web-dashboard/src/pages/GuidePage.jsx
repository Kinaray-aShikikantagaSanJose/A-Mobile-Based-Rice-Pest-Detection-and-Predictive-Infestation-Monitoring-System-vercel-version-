import { useEffect, useState } from 'react';
import { api } from '../api.js';
import { Badge, ErrorNote, Loading, Notice, PageHeader } from '../components/ui.jsx';
import { useI18n, useT } from '../i18n/index.jsx';
import { useAsync } from '../lib.js';

const STAGE_TONE = { Vegetative: 'green', Reproductive: 'orange', Ripening: 'gray' };

/** Example photo from the API, or a placeholder until the group adds one. */
function GuidePhoto({ path, alt }) {
  const t = useT();
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
      {path && !failed ? t('Loading photo…') : t('Example photo not added yet')}
    </div>
  );
}

function Stages({ stages, labels }) {
  const t = useT();
  return (
    <div className="flex flex-wrap gap-1.5">
      {stages.map((s, i) => (
        <Badge key={s} tone={STAGE_TONE[s] || 'gray'}>
          {labels?.[i] || t(s)}
        </Badge>
      ))}
    </div>
  );
}

/**
 * "What to look for". Two clearly separate parts: the four insects the photo
 * model was trained to detect, and the damage symptoms only people check in
 * the field. Text comes from the server in the dashboard language
 * (machine-assisted translations are marked as such). Plus a glossary.
 */
export default function GuidePage() {
  const t = useT();
  const { lang } = useI18n();
  const res = useAsync(() => api.guide(), [lang]);
  const g = res.data;
  const pests = g?.model_detected || g?.pests || [];
  const symptoms = g?.observed_symptoms || g?.symptoms || [];
  return (
    <div>
      <PageHeader
        title={g?.title || t('What to look for')}
        description={t(
          'The four pests the system handles and the damage symptoms reviewers tick, with the crop stage when each appears. Farmers see the same guide in the mobile app.',
        )}
      />
      <ErrorNote message={res.error} onRetry={res.reload} />
      {!g && res.loading && <Loading />}
      {g && (
        <div className="space-y-8">
          {g.translation_note && <Notice tone="orange">{g.translation_note}</Notice>}
          <Notice>
            {g.model_note}
            {g.confirm_note && <span className="mt-1 block font-semibold">{g.confirm_note}</span>}
          </Notice>

          <h2 className="flex items-center gap-2 text-base font-bold text-ink">
            <Badge tone="brand">{t('Model')}</Badge>
            {g.sections?.model_detected || t('Detected by the photo model')}
          </h2>
          {pests.map((p) => (
            <section key={p.key} className="rounded-2xl border border-line bg-white p-5 shadow-sm">
              <div className="grid gap-5 md:grid-cols-[240px_1fr]">
                <GuidePhoto path={p.photo} alt={p.name} />
                <div>
                  <div className="flex flex-wrap items-center gap-2">
                    <h3 className="text-lg font-bold text-ink">{p.name}</h3>
                    <span className="rounded-full bg-canvas px-2 py-0.5 font-mono text-[11px] text-ink2">{t('model class: {label}', { label: p.model_label })}</span>
                  </div>
                  <ul className="mt-2 list-disc space-y-1 pl-5 text-sm text-ink">
                    {p.signs.map((x) => (
                      <li key={x}>{x}</li>
                    ))}
                  </ul>
                  <div className="mt-3 text-xs font-semibold uppercase tracking-wide text-ink2">{t('Crop stage when it appears')}</div>
                  <div className="mt-1">
                    <Stages stages={p.stages} labels={p.stage_labels} />
                  </div>
                  <p className="mt-1 text-xs text-ink2">{p.stage_note}</p>
                </div>
              </div>
            </section>
          ))}

          <h2 className="flex items-center gap-2 text-base font-bold text-ink">
            <Badge tone="purple">{t('People')}</Badge>
            {g.sections?.observed_symptoms || t('Checked by people in the field')}
          </h2>
          <p className="-mt-6 text-sm text-ink2">{t('The model does not detect these. Reviewers tick them when they see them in the photo or the field.')}</p>
          {pests.map((p) => (
            <section key={`sym-${p.key}`} className="rounded-2xl border border-line bg-white p-5 shadow-sm">
              <div className="text-sm font-bold text-ink">{t('Damage linked to {pest}', { pest: p.name })}</div>
              <div className="mt-2 grid gap-4 sm:grid-cols-2 xl:grid-cols-3">
                {symptoms
                  .filter((x) => x.pest === p.key)
                  .map((x) => (
                    <div key={x.key} className="rounded-xl border border-line p-3">
                      <GuidePhoto path={x.photo} alt={x.name} />
                      <div className="mt-2 text-sm font-bold text-ink">{x.name}</div>
                      <p className="mt-1 text-sm text-ink2">{x.signs}</p>
                      <div className="mt-2">
                        <Stages stages={x.stages} labels={x.stage_labels} />
                      </div>
                    </div>
                  ))}
              </div>
            </section>
          ))}

          {g.glossary?.length > 0 && (
            <section className="rounded-2xl border border-line bg-white p-5 shadow-sm">
              <h2 className="text-base font-bold text-ink">{t('Glossary')}</h2>
              <dl className="mt-3 grid gap-3 sm:grid-cols-2">
                {g.glossary.map((x) => (
                  <div key={x.term_en}>
                    <dt className="text-sm font-semibold text-ink">
                      {x.term}
                      {x.term !== x.term_en && <span className="ml-1 text-xs font-normal text-muted">({x.term_en})</span>}
                    </dt>
                    <dd className="text-sm text-ink2">{x.meaning}</dd>
                  </div>
                ))}
              </dl>
            </section>
          )}
        </div>
      )}
    </div>
  );
}
