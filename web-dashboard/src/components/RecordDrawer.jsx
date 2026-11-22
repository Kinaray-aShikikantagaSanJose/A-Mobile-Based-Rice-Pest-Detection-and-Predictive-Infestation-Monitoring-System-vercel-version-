import { useEffect, useState } from 'react';
import { api } from '../api.js';
import { useT } from '../i18n/index.jsx';
import { fmtConf, fmtCount, fmtDate, fmtDateTime, landTypeLabel, OPTION_TYPES, pestLabel, REVIEW_ACTIONS, ROLE_LABELS, useAction, useAsync, waitingLabel } from '../lib.js';
import DetectionPhoto from './DetectionPhoto.jsx';
import Icon from './icons.jsx';
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
  const t = useT();
  const failed = ai.status === 'failed';
  const noPests = ai.result === 'no_pests_found';
  return (
    <div className="rounded-2xl border border-line bg-white p-4">
      <div className="text-xs font-semibold uppercase tracking-wide text-ink2">{t('Model result')}</div>
      {ai.pest ? (
        <>
          <div className="mt-1 flex flex-wrap items-baseline gap-2">
            <span className="text-lg font-bold text-ink">{ai.pest_name}</span>
            {ai.confidence != null && <span className="text-sm font-semibold text-ink2">{t('{n} confidence', { n: fmtConf(ai.confidence) })}</span>}
          </div>
          {ai.confidence != null && (
            <div className="mt-2 h-1.5 w-full overflow-hidden rounded-full bg-gray-100">
              <div className="h-full bg-brand-600" style={{ width: fmtConf(ai.confidence) }} />
            </div>
          )}
          <div className="mt-3 text-sm">
            <span className="text-ink2">{t('Count:')} </span>
            <span className="font-semibold text-ink">{fmtCount(ai.count)}</span>
          </div>
        </>
      ) : (
        <div className="mt-1 text-sm font-semibold text-ink">
          {t(failed ? 'Analysis unavailable' : noPests ? 'No pests found' : 'No supported pest recognized')}
        </div>
      )}
      {ai.message && <p className="mt-2 text-xs text-ink2">{t(ai.message)}</p>}
    </div>
  );
}

function ConfirmedCard({ scan }) {
  const t = useT();
  const c = scan.confirmed;
  return (
    <div className="rounded-2xl border border-emerald-200 bg-emerald-50/60 p-4">
      <div className="text-xs font-semibold uppercase tracking-wide text-emerald-800">{t('Confirmed by the reviewer')}</div>
      <div className="mt-1 flex flex-wrap items-center gap-2">
        <span className="text-lg font-bold text-ink">{c.pest === 'other' ? t(pestLabel(c.pest)) : c.pest_name || pestLabel(c.pest)}</span>
        <LevelBadge level={c.level} />
      </div>
      <div className="mt-1 text-sm text-ink2">
        {t('Count:')} <b className="text-ink">{fmtCount(c.count)}</b>
        {scan.suggested_level && scan.suggested_level !== c.level && <span> · {t('level suggested was {level}', { level: t(scan.suggested_level) })}</span>}
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
  const t = useT();
  const submitter = scan.submitter?.name || t('The farmer');
  return (
    <ol className="relative space-y-4 border-l border-line pl-5">
      <li>
        <span className="absolute -left-[5px] mt-1.5 h-2.5 w-2.5 rounded-full bg-brand-200" />
        <div className="text-sm font-semibold text-ink">{t('Submitted from the mobile app')}</div>
        <div className="text-xs text-ink2">
          {submitter} · {fmtDateTime(scan.created_at)}
        </div>
      </li>
      {(scan.history || []).map((h, i) => (
        <li key={i}>
          <span className="absolute -left-[5px] mt-1.5 h-2.5 w-2.5 rounded-full bg-brand-700" />
          <div className="text-sm font-semibold text-ink">
            {t(REVIEW_ACTIONS[h.action] || h.action)}
            {h.action === 'validated' && (
              <span className="font-normal text-ink2">
                {' '}
                — {h.pest === 'other' ? t(pestLabel(h.pest)) : pestLabel(h.pest)}, {fmtCount(h.count)}, {t(h.level)}
              </span>
            )}
          </div>
          <div className="text-xs text-ink2">
            {h.reviewer} · {t(ROLE_LABELS[h.reviewer_role] || h.reviewer_role)} · {fmtDateTime(h.created_at)}
          </div>
          {h.note && <p className="mt-1 whitespace-pre-line text-sm text-ink">{h.note}</p>}
        </li>
      ))}
    </ol>
  );
}

/** Options hidden from the farmer by the treatment feedback rule. */
function AlreadyTried({ items }) {
  const t = useT();
  if (!items?.length) return null;
  return (
    <p className="rounded-lg bg-canvas px-3 py-2 text-xs text-ink2">
      {t('Not recommended to this farmer again (they applied it and sent feedback):')}{' '}
      <b className="text-ink">{items.map((x) => x.title).join(', ')}</b>. {t('Re-allow it under Treatments & follow-ups.')}
    </p>
  );
}

function Recommendations({ recs }) {
  const t = useT();
  const groups = OPTION_TYPES.filter(([k]) => recs.groups[k]?.length);
  if (!groups.length) {
    return (
      <div className="space-y-3">
        <p className="text-sm text-ink2">{t('No approved library entries match this pest, crop stage and level yet.')}</p>
        <AlreadyTried items={recs.already_tried} />
      </div>
    );
  }
  return (
    <div className="space-y-3">
      <AlreadyTried items={recs.already_tried} />
      {groups.map(([k, label]) => (
        <div key={k}>
          <div className="text-xs font-semibold uppercase tracking-wide text-ink2">{t(label)}</div>
          <ul className="mt-1 space-y-1.5">
            {recs.groups[k].map((r) => (
              <li key={r.id} className="text-sm">
                <span className="font-semibold text-ink">{r.title}</span>
                <span className="block text-xs text-muted">{t('Source:')} {r.source_reference}</span>
              </li>
            ))}
          </ul>
        </div>
      ))}
      <p className="rounded-lg bg-orange-50 px-3 py-2 text-xs text-orange-800">{t(recs.chemical_note)}</p>
    </div>
  );
}

/**
 * Asks before deleting an observation (with an optional reason sent to the
 * farmer). Only shown to agriculturists and to technicians for their area;
 * the API and the database check the same rule.
 */
function DeleteRecord({ scan, onDeleted, onCancel }) {
  const t = useT();
  const [reason, setReason] = useState('');
  const action = useAction();
  const remove = () =>
    action.run(async () => {
      await api.deleteRecord(scan.id, reason.trim());
      onDeleted(t('Observation #{id} was deleted.', { id: scan.id }));
    });
  return (
    <div className="rounded-2xl border border-red-200 bg-red-50 p-4" role="alertdialog" aria-labelledby="delete-title">
      <div id="delete-title" className="flex items-center gap-2 text-sm font-bold text-red-800">
        <Icon name="trash" className="h-4 w-4" />
        {t('Delete observation #{id}?', { id: scan.id })}
      </div>
      <p className="mt-1 text-sm text-red-800">
        {t('This removes the record, its photo, treatments and review history. The farmer is told in the app. This can’t be undone.')}
      </p>
      <label className="mt-3 block">
        <span className="label">{t('Reason (optional, shown to the farmer)')}</span>
        <textarea className="input min-h-[64px]" value={reason} maxLength={500} onChange={(e) => setReason(e.target.value)} />
      </label>
      <ErrorNote message={action.error} />
      <div className="mt-3 flex flex-wrap justify-end gap-2">
        <Button variant="secondary" size="sm" onClick={onCancel} disabled={action.busy}>
          {t('Cancel')}
        </Button>
        <Button variant="destructive" size="sm" busy={action.busy} onClick={remove}>
          <Icon name="trash" className="h-4 w-4" />
          {t('Delete')}
        </Button>
      </div>
    </div>
  );
}

/**
 * The shared review panel: photo with model result boxes, details, history, treatments,
 * and the review actions when the viewer may act on this observation.
 * `onReviewed(message)` lets queues close the panel and refresh after a decision
 * (also after a deletion).
 */
export default function RecordDrawer({ scanId, viewer, onClose, onChanged, onReviewed }) {
  const t = useT();
  const [id, setId] = useState(scanId);
  const [saved, setSaved] = useState('');
  const [confirmDelete, setConfirmDelete] = useState(false);
  useEffect(() => {
    setId(scanId);
    setSaved('');
    setConfirmDelete(false);
  }, [scanId]);
  const detail = useAsync(() => api.scan(id), [id]);
  const scan = detail.data?.id === id ? detail.data : null;

  const isPest = scan?.report_type === 'pest';
  const staffView = Boolean(scan?.submitter); // only in-scope staff get submitter details
  const allowed = viewer.role === 'agriculturist' ? ['pending', 'escalated'] : ['pending'];
  const actionable = staffView && allowed.includes(scan.status);
  // Agriculturists and technicians (role_permissions); the server checks the area.
  const canDelete = Boolean(scan) && staffView && viewer.can_delete_records !== false && ['agriculturist', 'technician'].includes(viewer.role);

  const deleted = (message) => {
    onChanged?.();
    if (onReviewed) onReviewed(message);
    else onClose();
  };

  const reviewed = (message) => {
    onChanged?.();
    if (onReviewed) {
      onReviewed(message);
      return;
    }
    setSaved(message);
    detail.reload();
  };

  const title = scan
    ? `#${scan.id} · ${isPest ? scan.confirmed?.pest_name || scan.ai?.pest_name || t(scan.status === 'no_pests' ? 'No pests found' : 'Pest report') : t('Disease report')}`
    : t('Observation #{id}', { id });
  const place = scan ? [scan.barangay, scan.municipality].filter(Boolean).join(', ') || t('No area') : null;

  const tr = t;
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
            {scan.status === 'pending' && <Badge tone="gray">{t('Waiting {time}', { time: waitingLabel(scan.created_at) })}</Badge>}
            {scan.follow_up_of && <Badge tone="blue">{t('Follow-up after treatment #{id}', { id: scan.follow_up_of })}</Badge>}
            {scan.resubmission_of && (
              <button type="button" onClick={() => setId(scan.resubmission_of)} className="rounded-full hover:opacity-80 focus-visible:outline focus-visible:outline-2 focus-visible:outline-brand-600">
                <Badge tone="blue">{t('Retake of #{id}', { id: scan.resubmission_of })}</Badge>
              </button>
            )}
            {scan.resubmitted_as && (
              <button type="button" onClick={() => setId(scan.resubmitted_as)} className="rounded-full hover:opacity-80 focus-visible:outline focus-visible:outline-2 focus-visible:outline-brand-600">
                <Badge tone="blue">{t('Retaken as #{id}', { id: scan.resubmitted_as })}</Badge>
              </button>
            )}
            {scan.location_status === 'outside_antique' && <Badge tone="orange">{t('GPS outside Antique')}</Badge>}
            {canDelete && !confirmDelete && (
              <Button variant="danger" size="sm" className="ml-auto" onClick={() => setConfirmDelete(true)}>
                <Icon name="trash" className="h-4 w-4" />
                {t('Delete record')}
              </Button>
            )}
          </div>

          {confirmDelete && <DeleteRecord scan={scan} onDeleted={deleted} onCancel={() => setConfirmDelete(false)} />}

          {scan.status === 'no_pests' && (
            <Notice tone="gray">
              <b className="text-ink">{t('No pests found')}</b>
              <div className="mt-1">
                {t('The model checked a clear photo and found no insects, so the observation was closed without review and its photo was deleted to save storage.')}
              </div>
            </Notice>
          )}

          {scan.queue_reason === 'no_technician' && (
            <Notice tone="orange">
              <b>{t('No technician covers {place}.', { place })}</b>{' '}
              {t("It came to you instead, so you can review it here. To route future observations from this area to a technician, set a technician's municipality or coverage in User management.")}
            </Notice>
          )}

          {scan.status === 'escalated' && (
            <Notice tone="orange">
              <b>{t('Escalated')}</b>
              {scan.validated_by && ` ${t('by {name}', { name: scan.validated_by })}`}
              {scan.validated_at && ` · ${fmtDateTime(scan.validated_at)}`}
              <div className="mt-1 whitespace-pre-line">{scan.escalation_reason || t('No reason given.')}</div>
              {viewer.role === 'technician' && <div className="mt-1 text-xs">{t('Waiting for an agriculturist to resolve it.')}</div>}
            </Notice>
          )}
          {scan.status === 'returned' && (
            <Notice tone="gray">
              <b className="text-ink">{t('Returned to the farmer')}</b>
              {scan.validated_by && ` ${t('by {name}', { name: scan.validated_by })}`}
              <div className="mt-1 whitespace-pre-line">{scan.return_reason}</div>
            </Notice>
          )}
          {scan.status !== 'escalated' && scan.escalation_reason && (
            <Notice tone="gray">
              <b className="text-ink">{t('Escalation reason:')}</b> {scan.escalation_reason}
            </Notice>
          )}

          <div className="grid gap-4 lg:grid-cols-[1.3fr_1fr]">
            {scan.image_deleted ? (
              <div className="flex min-h-[220px] flex-col items-center justify-center gap-2 rounded-2xl border border-dashed border-line bg-white p-6 text-center">
                <Icon name="camera" className="h-8 w-8 text-muted" />
                <div className="text-sm font-semibold text-ink">{t('Photo removed')}</div>
                <p className="max-w-xs text-xs text-ink2">{t('No pests were found, so the photo was deleted. The result and its details are kept.')}</p>
              </div>
            ) : (
              <DetectionPhoto scanId={scan.id} detections={scan.ai?.detections || []} mainPest={scan.ai?.pest} />
            )}
            <div className="space-y-4">
              {isPest && scan.confirmed && <ConfirmedCard scan={scan} />}
              {isPest && scan.ai && <AiCard ai={scan.ai} />}
              <div className="rounded-2xl border border-line bg-white p-4">
                <dl className="grid grid-cols-2 gap-x-4 gap-y-3">
                  <Fact label={t('Submitted by')} className="col-span-2">
                    {scan.submitter ? (
                      <>
                        {scan.submitter.name}
                        {scan.submitter.role && scan.submitter.role !== 'farmer' && (
                          <span className="text-ink2"> ({t(ROLE_LABELS[scan.submitter.role] || scan.submitter.role)})</span>
                        )}
                        <div className="text-xs text-ink2">
                          {scan.submitter.phone ? (
                            <a className="font-semibold text-brand-700 hover:text-brand-900" href={`tel:${scan.submitter.phone}`}>
                              {scan.submitter.phone}
                            </a>
                          ) : (
                            t('No phone on file')
                          )}{' '}
                          · {scan.submitter.email}
                        </div>
                      </>
                    ) : null}
                  </Fact>
                  <Fact label={t('Crop stage')}>{scan.crop_stage && t(scan.crop_stage)}</Fact>
                  <Fact label={t('Land type')}>{t(scan.land_type_label || landTypeLabel(scan.land_type))}</Fact>
                  {scan.monitoring_method && <Fact label={t('Monitoring')}>{t(scan.monitoring_method)}</Fact>}
                  {scan.monitoring_method === 'Trap-based' && (
                    <>
                      <Fact label={t('Trap / lure type')}>{scan.trap_type}</Fact>
                      <Fact label={t('Target pest')}>{scan.target_pest}</Fact>
                      <Fact label={t('Target sex')}>{scan.target_sex}</Fact>
                    </>
                  )}
                  <Fact label={t(isPest ? "Farmer's notes" : 'Symptoms described')} className="col-span-2">
                    {scan.notes}
                  </Fact>
                </dl>
              </div>
            </div>
          </div>

          <Section title={t('Location')}>
            {scan.lat != null && scan.lng != null ? (
              <MiniMap lat={scan.lat} lng={scan.lng} />
            ) : (
              <p className="text-sm text-ink2">{t('No GPS location was recorded with this observation.')}</p>
            )}
            {scan.location_status === 'outside_antique' && (
              <p className="mt-2 text-xs text-orange-700">{t('The GPS point is outside Antique. The observation is filed under the farmer’s saved barangay.')}</p>
            )}
          </Section>

          {actionable && (
            <Section
              title={t(scan.status === 'escalated' ? 'Resolve this escalation' : 'Review')}
              aside={<Badge tone={viewer.role === 'agriculturist' ? 'purple' : 'brand'}>{t(viewer.role === 'agriculturist' ? 'Agriculturist decision' : 'Technician decision')}</Badge>}
              className="border-brand-200"
            >
              <ReviewForm key={scan.id} scan={scan} viewer={viewer} onDone={reviewed} />
            </Section>
          )}

          {(scan.diagnosis || scan.guidance) && (
            <Section title={t(isPest ? 'Note to the farmer' : 'Diagnosis & guidance')}>
              <dl className="space-y-3">
                {scan.diagnosis && <Fact label={t('Diagnosis')}>{scan.diagnosis}</Fact>}
                {scan.guidance && <Fact label={t(isPest ? 'Note' : 'Management guidance')}>{scan.guidance}</Fact>}
              </dl>
            </Section>
          )}

          {scan.recommendations && (
            <Section title={t('Treatment options the farmer sees')} aside={<span className="text-xs text-muted">{t('From the approved library')}</span>}>
              <Recommendations recs={scan.recommendations} />
            </Section>
          )}

          {scan.history && (
            <Section title={t('History')}>
              <History scan={scan} />
            </Section>
          )}

          {isPest && (
            <Section title={t('Treatments')}>
              {scan.treatments?.length ? (
                <ul className="divide-y divide-line">
                  {scan.treatments.map((tx) => (
                    <li key={tx.id} className="flex flex-wrap items-center justify-between gap-2 py-2 text-sm">
                      <div>
                        <span className="font-medium text-ink">{tx.treatment}</span>{' '}
                        <Badge tone="gray">{tr(tx.option_type)}</Badge>
                        <div className="text-xs text-ink2">
                          {tr('Applied {date} · follow-up due {due}', { date: fmtDate(tx.applied_at), due: fmtDate(tx.follow_up_due) })}
                          {tx.before_count ? ` · ${tr('count before {n}', { n: tx.before_count })}` : ''}
                        </div>
                      </div>
                      {tx.follow_up_scan_id ? (
                        <Button size="sm" variant="secondary" onClick={() => setId(tx.follow_up_scan_id)}>
                          {tr('Open follow-up #{id}', { id: tx.follow_up_scan_id })}
                        </Button>
                      ) : (
                        <span className="text-xs text-muted">{tr('No follow-up yet')}</span>
                      )}
                    </li>
                  ))}
                </ul>
              ) : (
                <p className="text-sm text-ink2">{tr(scan.status === 'validated' ? 'No treatment logged yet.' : 'Treatments can be logged once the observation is validated.')}</p>
              )}
            </Section>
          )}
        </div>
      )}
    </Drawer>
  );
}
