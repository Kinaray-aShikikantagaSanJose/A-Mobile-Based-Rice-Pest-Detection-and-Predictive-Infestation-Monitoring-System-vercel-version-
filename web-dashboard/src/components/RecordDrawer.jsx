import { useEffect, useState } from 'react';
import { api } from '../api.js';
import { fmtConf, fmtCount, fmtDate, fmtDateTime, landTypeLabel, OPTION_TYPES, pestLabel, REVIEW_ACTIONS, ROLE_LABELS, useAsync, waitingLabel } from '../lib.js';
import DetectionPhoto from './DetectionPhoto.jsx';
import MiniMap from './MiniMap.jsx';
import ReviewForm from './ReviewForm.jsx';
import { Badge, Button, Drawer, ErrorNote, LevelBadge, Loading, Notice, ReportTypeBadge, StatusBadge } from './ui.jsx';

function Fact({ label, children, className = '' }) {
  return (
    <div className={className}>
      <dt className="text-xs font-semibold uppercase tracking-wide text-ink2">{label}</dt>
      <dd className="mt-0.5 whitespace-pre-line break-words text-sm text-ink">{children || <span className="text-muted">—</span>}</dd>
    </div>
  );
}

function Section({ title, children, aside, className = '' }) {
  return (
    <section className={`rounded-2xl border border-line bg-white p-5 ${className}`}>
      <div className="mb-3 flex flex-wrap items-center justify-between gap-3">
        <h3 className="text-sm font-bold text-ink">{title}</h3>
        {aside}
      </div>
      {children}
    </section>
  );
}

function AiCard({ ai }) {
  const failed = ai.status === 'failed';
  return (
    <div className="rounded-2xl border border-line bg-white p-4">
      <div className="text-xs font-semibold uppercase tracking-wide text-ink2">Model result</div>
      {ai.pest ? (
        <>
          <div className="mt-1 flex flex-wrap items-baseline gap-2">
            <span className="text-lg font-bold text-ink">{ai.pest_name}</span>
            {ai.confidence != null && <span className="text-sm font-semibold text-ink2">{fmtConf(ai.confidence)} confidence</span>}
          </div>
          {ai.confidence != null && (
            <div className="mt-2 h-1.5 w-full overflow-hidden rounded-full bg-gray-100">
              <div className="h-full bg-brand-600" style={{ width: fmtConf(ai.confidence) }} />
            </div>
          )}
          <div className="mt-3 text-sm">
            <span className="text-ink2">Count: </span>
            <span className="font-semibold text-ink">{fmtCount(ai.count)}</span>
          </div>
        </>
      ) : (
        <div className="mt-1 text-sm font-semibold text-ink">{failed ? 'Analysis unavailable' : 'No supported pest recognized'}</div>
      )}
      {ai.message && <p className="mt-2 text-xs text-ink2">{ai.message}</p>}
    </div>
  );
}

function ConfirmedCard({ scan }) {
  const c = scan.confirmed;
  return (
    <div className="rounded-2xl border border-emerald-200 bg-emerald-50/60 p-4">
      <div className="text-xs font-semibold uppercase tracking-wide text-emerald-800">Confirmed by the reviewer</div>
      <div className="mt-1 flex flex-wrap items-center gap-2">
        <span className="text-lg font-bold text-ink">{c.pest_name || pestLabel(c.pest)}</span>
        <LevelBadge level={c.level} />
      </div>
      <div className="mt-1 text-sm text-ink2">
        Count: <b className="text-ink">{fmtCount(c.count)}</b>
        {scan.suggested_level && scan.suggested_level !== c.level && <span> · level suggested was {scan.suggested_level}</span>}
      </div>
      {c.indicators?.length > 0 && (
        <ul className="mt-2 list-disc space-y-0.5 pl-5 text-xs text-ink2">
          {c.indicators.map((i) => (
            <li key={i}>{i}</li>
          ))}
        </ul>
      )}
    </div>
  );
}

function History({ scan }) {
  const submitter = scan.submitter?.name || 'The farmer';
  return (
    <ol className="relative space-y-4 border-l border-line pl-5">
      <li>
        <span className="absolute -left-[5px] mt-1.5 h-2.5 w-2.5 rounded-full bg-brand-200" />
        <div className="text-sm font-semibold text-ink">Submitted from the mobile app</div>
        <div className="text-xs text-ink2">
          {submitter} · {fmtDateTime(scan.created_at)}
        </div>
      </li>
      {(scan.history || []).map((h, i) => (
        <li key={i}>
          <span className="absolute -left-[5px] mt-1.5 h-2.5 w-2.5 rounded-full bg-brand-700" />
          <div className="text-sm font-semibold text-ink">
            {REVIEW_ACTIONS[h.action] || h.action}
            {h.action === 'validated' && (
              <span className="font-normal text-ink2">
                {' '}
                — {pestLabel(h.pest)}, {fmtCount(h.count)}, {h.level}
              </span>
            )}
          </div>
          <div className="text-xs text-ink2">
            {h.reviewer} · {ROLE_LABELS[h.reviewer_role] || h.reviewer_role} · {fmtDateTime(h.created_at)}
          </div>
          {h.note && <p className="mt-1 whitespace-pre-line text-sm text-ink">{h.note}</p>}
        </li>
      ))}
    </ol>
  );
}

/** Options hidden from the farmer by the treatment feedback rule. */
function AlreadyTried({ items }) {
  if (!items?.length) return null;
  return (
    <p className="rounded-lg bg-canvas px-3 py-2 text-xs text-ink2">
      Not recommended to this farmer again (they applied it and sent feedback):{' '}
      <b className="text-ink">{items.map((t) => t.title).join(', ')}</b>. Re-allow it under Treatments &amp; follow-ups.
    </p>
  );
}

function Recommendations({ recs }) {
  const groups = OPTION_TYPES.filter(([k]) => recs.groups[k]?.length);
  if (!groups.length) {
    return (
      <div className="space-y-3">
        <p className="text-sm text-ink2">No approved library entries match this pest, crop stage and level yet.</p>
        <AlreadyTried items={recs.already_tried} />
      </div>
    );
  }
  return (
    <div className="space-y-3">
      <AlreadyTried items={recs.already_tried} />
      {groups.map(([k, label]) => (
        <div key={k}>
          <div className="text-xs font-semibold uppercase tracking-wide text-ink2">{label}</div>
          <ul className="mt-1 space-y-1.5">
            {recs.groups[k].map((r) => (
              <li key={r.id} className="text-sm">
                <span className="font-semibold text-ink">{r.title}</span>
                <span className="block text-xs text-muted">Source: {r.source_reference}</span>
              </li>
            ))}
          </ul>
        </div>
      ))}
      <p className="rounded-lg bg-orange-50 px-3 py-2 text-xs text-orange-800">{recs.chemical_note}</p>
    </div>
  );
}

/**
 * The shared review panel: photo with model result boxes, details, history, treatments,
 * and the review actions when the viewer may act on this observation.
 * `onReviewed(message)` lets queues close the panel and refresh after a decision.
 */
export default function RecordDrawer({ scanId, viewer, onClose, onChanged, onReviewed }) {
  const [id, setId] = useState(scanId);
  const [saved, setSaved] = useState('');
  useEffect(() => {
    setId(scanId);
    setSaved('');
  }, [scanId]);
  const detail = useAsync(() => api.scan(id), [id]);
  const scan = detail.data?.id === id ? detail.data : null;

  const isPest = scan?.report_type === 'pest';
  const staffView = Boolean(scan?.submitter); // only in-scope staff get submitter details
  const allowed = viewer.role === 'agriculturist' ? ['pending', 'escalated'] : ['pending'];
  const actionable = staffView && allowed.includes(scan.status);

  const reviewed = (message) => {
    onChanged?.();
    if (onReviewed) {
      onReviewed(message);
      return;
    }
    setSaved(message);
    detail.reload();
  };

  const title = scan ? `#${scan.id} · ${isPest ? scan.confirmed?.pest_name || scan.ai?.pest_name || 'Pest report' : 'Disease report'}` : `Observation #${id}`;
  const place = scan ? [scan.barangay, scan.municipality].filter(Boolean).join(', ') || 'No area' : null;

  return (
    <Drawer open onClose={onClose} title={title} subtitle={scan ? `${place} · ${fmtDateTime(scan.created_at)}` : null} width="max-w-5xl">
      {!scan && detail.loading && <Loading />}
      <ErrorNote message={detail.error} onRetry={detail.reload} />
      {scan && (
        <div className="space-y-4">
          {saved && <Notice>{saved}</Notice>}

          <div className="flex flex-wrap items-center gap-2">
            <StatusBadge status={scan.status} />
            <ReportTypeBadge type={scan.report_type} />
            {(scan.level || scan.confirmed?.level) && <LevelBadge level={scan.level || scan.confirmed.level} />}
            {scan.status === 'pending' && <Badge tone="gray">Waiting {waitingLabel(scan.created_at)}</Badge>}
            {scan.follow_up_of && <Badge tone="blue">Follow-up after treatment #{scan.follow_up_of}</Badge>}
            {scan.resubmission_of && (
              <button type="button" onClick={() => setId(scan.resubmission_of)} className="rounded-full hover:opacity-80 focus-visible:outline focus-visible:outline-2 focus-visible:outline-brand-600">
                <Badge tone="blue">Retake of #{scan.resubmission_of}</Badge>
              </button>
            )}
            {scan.resubmitted_as && (
              <button type="button" onClick={() => setId(scan.resubmitted_as)} className="rounded-full hover:opacity-80 focus-visible:outline focus-visible:outline-2 focus-visible:outline-brand-600">
                <Badge tone="blue">Retaken as #{scan.resubmitted_as}</Badge>
              </button>
            )}
          </div>

          {scan.queue_reason === 'no_technician' && (
            <Notice tone="orange">
              <b>No technician covers {place}.</b> It came to you instead, so you can review it here. To route future observations from
              this area to a technician, set a technician's municipality or coverage in User management.
            </Notice>
          )}

          {scan.status === 'escalated' && (
            <Notice tone="orange">
              <b>Escalated</b>
              {scan.validated_by && ` by ${scan.validated_by}`}
              {scan.validated_at && ` · ${fmtDateTime(scan.validated_at)}`}
              <div className="mt-1 whitespace-pre-line">{scan.escalation_reason || 'No reason given.'}</div>
              {viewer.role === 'technician' && <div className="mt-1 text-xs">Waiting for an agriculturist to resolve it.</div>}
            </Notice>
          )}
          {scan.status === 'returned' && (
            <Notice tone="gray">
              <b className="text-ink">Returned to the farmer</b>
              {scan.validated_by && ` by ${scan.validated_by}`}
              <div className="mt-1 whitespace-pre-line">{scan.return_reason}</div>
            </Notice>
          )}
          {scan.status !== 'escalated' && scan.escalation_reason && (
            <Notice tone="gray">
              <b className="text-ink">Escalation reason:</b> {scan.escalation_reason}
            </Notice>
          )}

          <div className="grid gap-4 lg:grid-cols-[1.3fr_1fr]">
            <DetectionPhoto scanId={scan.id} detections={scan.ai?.detections || []} mainPest={scan.ai?.pest} />
            <div className="space-y-4">
              {isPest && scan.confirmed && <ConfirmedCard scan={scan} />}
              {isPest && scan.ai && <AiCard ai={scan.ai} />}
              <div className="rounded-2xl border border-line bg-white p-4">
                <dl className="grid grid-cols-2 gap-x-4 gap-y-3">
                  <Fact label="Submitted by" className="col-span-2">
                    {scan.submitter ? (
                      <>
                        {scan.submitter.name}
                        {scan.submitter.role && scan.submitter.role !== 'farmer' && (
                          <span className="text-ink2"> ({ROLE_LABELS[scan.submitter.role] || scan.submitter.role})</span>
                        )}
                        <div className="text-xs text-ink2">
                          {scan.submitter.phone ? (
                            <a className="font-semibold text-brand-700 hover:text-brand-900" href={`tel:${scan.submitter.phone}`}>
                              {scan.submitter.phone}
                            </a>
                          ) : (
                            'No phone on file'
                          )}{' '}
                          · {scan.submitter.email}
                        </div>
                      </>
                    ) : null}
                  </Fact>
                  <Fact label="Crop stage">{scan.crop_stage}</Fact>
                  <Fact label="Land type">{scan.land_type_label || landTypeLabel(scan.land_type)}</Fact>
                  {scan.monitoring_method && <Fact label="Monitoring">{scan.monitoring_method}</Fact>}
                  {scan.monitoring_method === 'Trap-based' && (
                    <>
                      <Fact label="Trap / lure type">{scan.trap_type}</Fact>
                      <Fact label="Target pest">{scan.target_pest}</Fact>
                      <Fact label="Target sex">{scan.target_sex}</Fact>
                    </>
                  )}
                  <Fact label={isPest ? "Farmer's notes" : 'Symptoms described'} className="col-span-2">
                    {scan.notes}
                  </Fact>
                </dl>
              </div>
            </div>
          </div>

          <Section title="Location">
            {scan.lat != null && scan.lng != null ? (
              <MiniMap lat={scan.lat} lng={scan.lng} />
            ) : (
              <p className="text-sm text-ink2">No GPS location was recorded with this observation.</p>
            )}
          </Section>

          {actionable && (
            <Section
              title={scan.status === 'escalated' ? 'Resolve this escalation' : 'Review'}
              aside={<Badge tone={viewer.role === 'agriculturist' ? 'purple' : 'brand'}>{ROLE_LABELS[viewer.role]} decision</Badge>}
              className="border-brand-200"
            >
              <ReviewForm key={scan.id} scan={scan} viewer={viewer} onDone={reviewed} />
            </Section>
          )}

          {(scan.diagnosis || scan.guidance) && (
            <Section title={isPest ? 'Note to the farmer' : 'Diagnosis & guidance'}>
              <dl className="space-y-3">
                {scan.diagnosis && <Fact label="Diagnosis">{scan.diagnosis}</Fact>}
                {scan.guidance && <Fact label={isPest ? 'Note' : 'Management guidance'}>{scan.guidance}</Fact>}
              </dl>
            </Section>
          )}

          {scan.recommendations && (
            <Section title="Treatment options the farmer sees" aside={<span className="text-xs text-muted">From the approved library</span>}>
              <Recommendations recs={scan.recommendations} />
            </Section>
          )}

          {scan.history && (
            <Section title="History">
              <History scan={scan} />
            </Section>
          )}

          {isPest && (
            <Section title="Treatments">
              {scan.treatments?.length ? (
                <ul className="divide-y divide-line">
                  {scan.treatments.map((t) => (
                    <li key={t.id} className="flex flex-wrap items-center justify-between gap-2 py-2 text-sm">
                      <div>
                        <span className="font-medium text-ink">{t.treatment}</span>{' '}
                        <Badge tone="gray">{t.option_type}</Badge>
                        <div className="text-xs text-ink2">
                          Applied {fmtDate(t.applied_at)} · follow-up due {fmtDate(t.follow_up_due)}
                          {t.before_count ? ` · count before ${t.before_count}` : ''}
                        </div>
                      </div>
                      {t.follow_up_scan_id ? (
                        <Button size="sm" variant="secondary" onClick={() => setId(t.follow_up_scan_id)}>
                          Open follow-up #{t.follow_up_scan_id}
                        </Button>
                      ) : (
                        <span className="text-xs text-muted">No follow-up yet</span>
                      )}
                    </li>
                  ))}
                </ul>
              ) : (
                <p className="text-sm text-ink2">{scan.status === 'validated' ? 'No treatment logged yet.' : 'Treatments can be logged once the observation is validated.'}</p>
              )}
            </Section>
          )}
        </div>
      )}
    </Drawer>
  );
}
