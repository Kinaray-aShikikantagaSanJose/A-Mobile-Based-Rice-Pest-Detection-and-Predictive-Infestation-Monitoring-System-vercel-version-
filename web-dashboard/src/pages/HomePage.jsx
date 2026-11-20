import { api } from '../api.js';
import { ErrorNote, Notice, PageHeader, Stat } from '../components/ui.jsx';
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
  const overview = useAsync(() => api.overview(), []);
  const o = overview.data;
  const waiting = o ? (o.waiting_for_agriculturist ?? o.escalations_waiting) : 0;
  return (
    <div>
      <PageHeader title="Home" description="Validated observations across the province this month, where the hotspots are, and what needs your decision." />
      <ErrorNote message={overview.error} onRetry={overview.reload} />
      {o?.pending_without_technician > 0 && (
        <div className="mb-4">
          <Notice tone="orange">
            <b>
              {fmtNum(o.pending_without_technician)} observation{o.pending_without_technician === 1 ? '' : 's'} came from places no technician covers.
            </b>{' '}
            They are in <a className="font-semibold underline" href="#escalations">For your review</a>. To send future observations to a technician, set the
            technician's municipality or coverage in <a className="font-semibold underline" href="#users">User management</a>.
          </Notice>
        </div>
      )}
      {o && (
        <div className="mb-6 grid grid-cols-1 gap-3 sm:grid-cols-2 xl:grid-cols-4">
          <Stat label="Validated this month" value={fmtNum(o.validated_this_month)} tone="brand" hint={`${fmtNum(o.validated)} validated in all`} />
          <HotspotStat counts={o.hotspots} days={o.hotspot_days} />
          <LinkStat page="escalations">
            <Stat
              label="Waiting for you"
              value={fmtNum(waiting)}
              tone={waiting ? 'red' : 'muted'}
              hint={
                waiting
                  ? `${fmtNum(o.escalations_waiting)} escalated · ${fmtNum(o.pending_without_technician || 0)} from areas without a technician →`
                  : 'Nothing waiting'
              }
            />
          </LinkStat>
          <Stat label="Treatments logged" value={fmtNum(o.treatments_this_month)} hint={`This month · ${fmtNum(o.treatments_total)} in all`} />
        </div>
      )}
      <HotspotExplorer viewer={viewer} mapClassName="h-[520px]" />
    </div>
  );
}
