import { api } from '../api.js';
import { ErrorNote, Notice, PageHeader, Stat } from '../components/ui.jsx';
import { useT } from '../i18n/index.jsx';
import { fmtNum, useAsync } from '../lib.js';
import { HotspotExplorer, HotspotStat } from './MapPage.jsx';

function LinkStat({ page, children }) {
  return (
    <a href={`#${page}`} className="block rounded-2xl transition-shadow hover:shadow-md focus:outline-none focus:ring-2 focus:ring-brand-600">
      {children}
    </a>
  );
}

/** Agriculturist home: the province at a glance, then the map. */
export default function HomePage({ viewer }) {
  const t = useT();
  const overview = useAsync(() => api.overview(), []);
  const o = overview.data;
  const waiting = o ? (o.waiting_for_agriculturist ?? o.escalations_waiting) : 0;
  return (
    <div>
      <PageHeader title={t('Home')} description={t('Validated observations across the province this month, where the hotspots are, and what needs your decision.')} />
      <ErrorNote message={overview.error} onRetry={overview.reload} />
      {o?.pending_without_technician > 0 && (
        <div className="mb-4">
          <Notice tone="orange">
            <b>
              {o.pending_without_technician === 1
                ? t('{n} observation came from places no technician covers.', { n: fmtNum(o.pending_without_technician) })
                : t('{n} observations came from places no technician covers.', { n: fmtNum(o.pending_without_technician) })}
            </b>{' '}
            {t('They are in')} <a className="font-semibold underline" href="#escalations">{t('For your review')}</a>.{' '}
            {t("To send future observations to a technician, set the technician's municipality or coverage in")}{' '}
            <a className="font-semibold underline" href="#users">{t('User management')}</a>.
          </Notice>
        </div>
      )}
      {o && (
        <div className="mb-6 grid grid-cols-1 gap-3 sm:grid-cols-2 xl:grid-cols-4">
          <Stat label={t('Validated this month')} value={fmtNum(o.validated_this_month)} tone="brand" hint={t('{n} validated in all', { n: fmtNum(o.validated) })} />
          <HotspotStat counts={o.hotspots} days={o.hotspot_days} />
          <LinkStat page="escalations">
            <Stat
              label={t('Waiting for you')}
              value={fmtNum(waiting)}
              tone={waiting ? 'red' : 'muted'}
              hint={
                waiting
                  ? t('{escalated} escalated · {unassigned} from areas without a technician →', {
                      escalated: fmtNum(o.escalations_waiting),
                      unassigned: fmtNum(o.pending_without_technician || 0),
                    })
                  : t('Nothing waiting')
              }
            />
          </LinkStat>
          <Stat
            label={t('Treatments logged')}
            value={fmtNum(o.treatments_this_month)}
            hint={t('This month · {n} in all', { n: fmtNum(o.treatments_total) })}
          />
        </div>
      )}
      <HotspotExplorer viewer={viewer} mapClassName="h-[520px]" />
    </div>
  );
}
