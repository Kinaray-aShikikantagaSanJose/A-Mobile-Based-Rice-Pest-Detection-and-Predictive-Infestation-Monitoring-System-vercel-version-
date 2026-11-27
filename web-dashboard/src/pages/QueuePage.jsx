import { useMemo, useState } from 'react';
import { api } from '../api.js';
import AuthImage from '../components/AuthImage.jsx';
import RecordDrawer from '../components/RecordDrawer.jsx';
import { Badge, Button, Empty, ErrorNote, Loading, Notice, Panel, PageHeader, RelevanceBadge, Segmented } from '../components/ui.jsx';
import { useT } from '../i18n/index.jsx';
import { fmtConf, fmtDateTime, landTypeLabel, useAsync, useInterval, waitingLabel } from '../lib.js';

function waitTone(iso) {
  const hours = (Date.now() - new Date(iso)) / 3600000;
  return hours >= 72 ? 'red' : hours >= 24 ? 'orange' : 'gray';
}

function AiGuess({ ai }) {
  const t = useT();
  if (!ai?.pest) {
    return <span className="text-sm text-ink2">{ai?.status === 'failed' ? t('Model result unavailable') : t('Model result: no supported pest found')}</span>;
  }
  return (
    <span className="flex flex-wrap items-center gap-2">
      <span className="font-semibold text-ink">{t(ai.pest_name)}</span>
      {ai.confidence != null && <Badge tone="brand">{fmtConf(ai.confidence)}</Badge>}
      <span className="text-xs text-ink2">{ai.count == null ? t('Not countable') : t('{n} counted', { n: ai.count })}</span>
    </span>
  );
}

function QueueItem({ item, nameOf, onOpen }) {
  const t = useT();
  const escalated = item.queue_reason === 'escalated';
  const since = escalated ? item.validated_at || item.created_at : item.created_at;
  return (
    <li>
      <button
        type="button"
        onClick={() => onOpen(item.id)}
        className="flex w-full flex-col gap-3 px-4 py-4 text-left hover:bg-brand-50/60 sm:flex-row sm:items-center sm:px-5"
      >
        <div className="flex min-w-0 flex-1 items-start gap-4">
          <AuthImage scanId={item.id} className="h-16 w-16 shrink-0 rounded-xl border border-line" />
          <div className="min-w-0 flex-1 space-y-1">
            <div className="flex flex-wrap items-center gap-2">
              <span className="text-xs font-semibold text-muted">#{item.id}</span>
              {item.resubmission_of && <Badge tone="blue">{t('Retake of #{id}', { id: item.resubmission_of })}</Badge>}
              <RelevanceBadge relevance={item.image_relevance} />
              {item.report_type === 'pest' ? (
                <AiGuess ai={item.ai} />
              ) : (
                <span className="line-clamp-2 text-sm text-ink">{item.notes || t('No description')}</span>
              )}
            </div>
            <div className="text-sm text-ink2">
              <span className="font-medium text-ink">{item.barangay || t('No barangay')}</span>
              {item.municipality && `, ${item.municipality}`} · {item.crop_stage ? t(item.crop_stage) : t('stage not given')}
              {item.monitoring_method === 'Trap-based' && ` · ${t('trap')}`}
              {' · '}{t(item.land_type_label || landTypeLabel(item.land_type))}
            </div>
            <div className="text-xs text-ink2">
              {item.submitter?.name}
              {item.submitter?.phone && ` · ${item.submitter.phone}`} · {t('submitted {date}', { date: fmtDateTime(item.created_at) })}
            </div>
            {escalated && (
              <div className="mt-1 rounded-lg bg-violet-50 px-3 py-2 text-xs text-violet-900">
                <b>{t('Escalated by {name}:', { name: nameOf(item.validated_by) })}</b>{' '}
                <span className="whitespace-pre-line">{item.escalation_reason || t('No reason given.')}</span>
              </div>
            )}
            {item.queue_reason === 'no_technician' && (
              <div className="mt-1 rounded-lg bg-orange-50 px-3 py-2 text-xs text-orange-900">
                <b>{t('No technician covers this area.')}</b>{' '}
                {t('Review it here, or assign a technician to {area} in User management.', { area: item.municipality || t('the area') })}
              </div>
            )}
          </div>
        </div>
        <div className="flex items-center gap-3 sm:flex-col sm:items-end">
          <Badge tone={waitTone(since)}>{escalated ? t('To Be Validated') : t('Not Validated')} · {waitingLabel(since)}</Badge>
          <span className="text-sm font-semibold text-brand-700">{t('Review →')}</span>
        </div>
      </button>
    </li>
  );
}

/**
 * Technicians: pending observations in their coverage area. Agriculturists:
 * escalations from every area, plus observations from places no technician covers.
 */
export default function QueuePage({ viewer, onChanged }) {
  const t = useT();
  const escalations = viewer.role === 'agriculturist';
  const [kind, setKind] = useState('pest');
  // Agriculturists: both queues, or one of them. Same statuses, no new ones.
  const [queue, setQueue] = useState('');
  const [openId, setOpenId] = useState(null);
  const [notice, setNotice] = useState('');
  const res = useAsync(() => Promise.all([api.queue('pest'), api.queue('disease')]).then(([pest, disease]) => ({ pest, disease })), []);
  // Agriculturists see who escalated by name; the queue only carries the email.
  const users = useAsync(() => (escalations ? api.users() : Promise.resolve([])), [escalations]);
  const names = useMemo(() => Object.fromEntries((users.data || []).map((u) => [u.email, u.full_name])), [users.data]);
  const nameOf = (email) => names[email] || email || t('a technician');
  useInterval(res.reload, 60000);

  const items = (res.data?.[kind] || []).filter((i) => !queue || i.queue === queue);
  const count = (k) => (res.data ? ` (${res.data[k].filter((i) => !queue || i.queue === queue).length})` : '');

  return (
    <div>
      <PageHeader
        title={escalations ? t('For your review') : t('Not Validated queue')}
        description={
          escalations
            ? t('Cases technicians escalated, and observations from places no technician covers, oldest first. Check the result, then return it, or validate it with the level. For escalated cases, record the diagnosis and the guidance for the farmer.')
            : t('Observations from farmers in your coverage area, oldest first. Check the result (confirm or correct the model result), then decide: return it for a new photo, validate it with the level, or escalate it.')
        }
        area={escalations ? undefined : viewer.area_label}
        actions={
          <Button variant="secondary" size="sm" onClick={res.reload} busy={res.loading && Boolean(res.data)}>
            {t('Refresh')}
          </Button>
        }
      />
      {notice && (
        <div className="mb-4 flex items-start justify-between gap-3 rounded-xl border border-brand-200 bg-brand-50 px-4 py-3 text-sm text-brand-900">
          <span>{notice}</span>
          <button type="button" className="text-xs font-semibold" onClick={() => setNotice('')}>
            {t('Dismiss')}
          </button>
        </div>
      )}
      <ErrorNote message={res.error} onRetry={res.reload} />
      <Panel
        title={escalations ? t('To Be Validated, and Not Validated from areas without a technician') : t('Not Validated')}
        subtitle={escalations ? t('Oldest submission first') : t('Oldest first')}
        actions={
          <div className="flex flex-wrap gap-2">
          {escalations && (
            <Segmented
              value={queue}
              onChange={setQueue}
              options={[
                ['', t('Both queues')],
                ['to_be_validated', t('To Be Validated')],
                ['not_validated', t('Not Validated')],
              ]}
            />
          )}
          <Segmented
            value={kind}
            onChange={setKind}
            options={[
              ['pest', `${t('Pest')}${count('pest')}`],
              ['disease', `${t('Disease')}${count('disease')}`],
            ]}
          />
          </div>
        }
        bodyClassName=""
      >
        {!res.data && res.loading ? (
          <Loading />
        ) : items.length ? (
          <ul className="divide-y divide-line">
            {items.map((item) => (
              <QueueItem key={item.id} item={item} nameOf={nameOf} onOpen={setOpenId} />
            ))}
          </ul>
        ) : (
          <Empty title={escalations ? t('Nothing waiting for you') : t('Nothing to validate')}>
            {escalations
              ? kind === 'pest'
                ? t('No escalated pest cases, and none from places without a technician.')
                : t('No escalated disease cases, and none from places without a technician.')
              : viewer.area_label === ''
                ? t('Your account has no coverage area yet, so no observations reach your queue.')
                : kind === 'pest'
                  ? t('No pest observations from your area are waiting.')
                  : t('No disease observations from your area are waiting.')}
          </Empty>
        )}
      </Panel>
      {!escalations && (
        <div className="mt-4">
          <Notice tone="gray">
            {t('Escalated observations leave this queue and go to an agriculturist. You can follow them in your validation history.')}
          </Notice>
        </div>
      )}
      {openId && (
        <RecordDrawer
          scanId={openId}
          viewer={viewer}
          onClose={() => setOpenId(null)}
          onChanged={() => {
            res.reload();
            onChanged?.();
          }}
          onReviewed={(message) => {
            setOpenId(null);
            setNotice(message);
          }}
        />
      )}
    </div>
  );
}
