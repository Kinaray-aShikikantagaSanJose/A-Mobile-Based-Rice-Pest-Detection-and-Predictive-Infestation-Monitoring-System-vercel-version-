import { useEffect, useRef } from 'react';
import L from './leaflet-global.js';
import 'leaflet.heat';
import 'leaflet/dist/leaflet.css';
import { useT } from '../i18n/index.jsx';
import { fmtCount, fmtDate } from '../lib.js';
import { LEVEL_COLOR } from './ui.jsx';

const NO_LEVEL = '#8E9E90';
export const TILE_URL = 'https://tile.opentopomap.org/{z}/{x}/{y}.png';
export const TILE_ATTRIBUTION = '© OpenStreetMap contributors, SRTM | © OpenTopoMap';

// Heatmap colours, low to high, like a weather map. The legend uses the same stops.
export const HEAT_GRADIENT = { 0.2: '#2c7bb6', 0.4: '#00a6ca', 0.6: '#90eb9d', 0.8: '#f9d057', 1: '#d7191c' };
export const HEAT_NOTE = 'Intensity reflects reported cases, not total pest population.';
// Weight of one validated record by its confirmed level (records without a level count as LOW).
const LEVEL_WEIGHT = { LOW: 1 / 3, MEDIUM: 2 / 3, HIGH: 1 };
// Arrow colours for the directional spread, one per pest.
export const SPREAD_COLORS = ['#7c3aed', '#0f766e', '#be185d', '#1d4ed8', '#b45309'];

// Tooltip HTML includes farmer-entered text (barangay names), so escape it.
const esc = (v) =>
  String(v ?? '').replace(/[&<>"']/g, (ch) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[ch]);

/** Barangay circle radius in pixels (visible at province zoom): grows with the number of records. */
const radius = (records) => Math.min(12 + Math.sqrt(records) * 4, 30);

/** Arrowhead pointing along `bearing` (degrees clockwise from north). */
function arrowIcon(color, bearing) {
  return L.divIcon({
    className: '',
    iconSize: [26, 26],
    iconAnchor: [13, 13],
    html: `<svg width="26" height="26" viewBox="0 0 26 26" style="transform: rotate(${bearing}deg)"><path d="M13 2 L22 22 L13 17 L4 22 Z" fill="${color}" stroke="#fff" stroke-width="2" stroke-linejoin="round"/></svg>`,
  });
}

/**
 * Validated observations on a map, as markers (points + barangay hotspots)
 * or as a heatmap. Both views use the same `points`, so the heatmap shows
 * exactly what the markers would. `spread` adds the directional arrows.
 */
export default function HotspotMap({
  points = [],
  hotspots = [],
  onSelect,
  focus,
  className = 'h-[460px]',
  mode = 'markers',
  weightBy = 'level',
  spread = [],
}) {
  const mapRef = useRef(null);
  const mapObj = useRef(null);
  const layerRef = useRef(null);
  const heatRef = useRef(null);
  const arrowRef = useRef(null);
  const rendererRef = useRef(null);
  const selectRef = useRef(onSelect);
  selectRef.current = onSelect;
  const t = useT();

  useEffect(() => {
    if (mapObj.current) return undefined;
    // Centered on Antique.
    const map = L.map(mapRef.current, { scrollWheelZoom: false }).setView([11.2, 122.05], 9);
    L.tileLayer(TILE_URL, { maxZoom: 17, attribution: TILE_ATTRIBUTION }).addTo(map);
    // Canvas keeps thousands of circles smooth (SVG slows down with many points).
    rendererRef.current = L.canvas({ padding: 0.5 });
    layerRef.current = L.layerGroup().addTo(map);
    arrowRef.current = L.layerGroup().addTo(map);
    mapObj.current = map;
    const ro = new ResizeObserver(() => map.invalidateSize());
    ro.observe(mapRef.current);
    return () => {
      ro.disconnect();
      map.remove();
      mapObj.current = null;
      layerRef.current = null;
      heatRef.current = null;
      arrowRef.current = null;
    };
  }, []);

  useEffect(() => {
    const layer = layerRef.current;
    const map = mapObj.current;
    if (!layer || !map) return;
    layer.clearLayers();
    if (heatRef.current) {
      map.removeLayer(heatRef.current);
      heatRef.current = null;
    }
    const renderer = rendererRef.current;

    if (mode === 'heat') {
      const heat = points.map((p) => [p.lat, p.lng, weightBy === 'cases' ? 1 : LEVEL_WEIGHT[p.level] || LEVEL_WEIGHT.LOW]);
      heatRef.current = L.heatLayer(heat, {
        radius: 26,
        blur: 20,
        maxZoom: 13,
        minOpacity: 0.3,
        // Cases: about three records close together reach the top colour.
        max: weightBy === 'cases' ? 3 : 1.5,
        gradient: HEAT_GRADIENT,
      }).addTo(map);
    } else {
      for (const h of hotspots) {
        const color = LEVEL_COLOR[h.level] || NO_LEVEL;
        L.circleMarker([h.lat, h.lng], {
          renderer,
          radius: radius(h.records),
          color,
          fillColor: color,
          fillOpacity: 0.18,
          weight: 2,
          dashArray: '5 4',
        })
          .bindTooltip(
            `<b>${esc(h.barangay)}</b>, ${esc(h.municipality)}<br/>` +
              `${esc(t('Highest level:'))} <b>${esc(t(h.level))}</b> · ${esc(h.records === 1 ? t('{n} record', { n: h.records }) : t('{n} records', { n: h.records }))}<br/>` +
              `${esc(h.pests.map((p) => t(p)).join(', '))}<br/>${esc(t('Latest: {date}', { date: fmtDate(h.latest) }))}`,
            { sticky: true },
          )
          .addTo(layer);
      }

      for (const p of points) {
        const color = LEVEL_COLOR[p.level] || NO_LEVEL;
        const count = p.is_disease ? '' : ` · ${esc(t(fmtCount(p.count)))}`;
        const marker = L.circleMarker([p.lat, p.lng], {
          renderer,
          radius: 6,
          color: '#ffffff',
          fillColor: color,
          fillOpacity: 0.95,
          weight: 2,
        }).bindTooltip(
          `<b>${p.sample ? esc(t('Sample')) : `#${esc(p.id)}`} ${esc(p.pest)}</b> · ${esc(p.level || t('no level'))}${count}<br/>` +
            `${esc(p.barangay || '—')}, ${esc(p.municipality)} · ${esc(fmtDate(p.created_at))}`,
        );
        if (!p.sample) marker.on('click', () => selectRef.current?.(p));
        marker.addTo(layer);
      }
    }

    const coords = [...points.map((p) => [p.lat, p.lng]), ...(mode === 'heat' ? [] : hotspots.map((h) => [h.lat, h.lng]))];
    if (coords.length) map.fitBounds(L.latLngBounds(coords).pad(0.25), { maxZoom: 14 });
  }, [points, hotspots, mode, weightBy, t]);

  // Directional spread: an arrow from each pest's Week 1 centre to its Week 2 centre.
  useEffect(() => {
    const layer = arrowRef.current;
    if (!layer) return;
    layer.clearLayers();
    spread.forEach((s, i) => {
      if (!s.from || !s.to || s.status === 'insufficient') return;
      const color = SPREAD_COLORS[i % SPREAD_COLORS.length];
      const tip = `<b>${esc(s.pest)}</b><br/>${esc(s.message)}<br/>${esc(s.detail)}`;
      if (s.status === 'moved') {
        L.polyline([[s.from.lat, s.from.lng], [s.to.lat, s.to.lng]], { color, weight: 4, opacity: 0.9, dashArray: '8 6' })
          .bindTooltip(tip, { sticky: true })
          .addTo(layer);
        L.circleMarker([s.from.lat, s.from.lng], { radius: 5, color: '#fff', weight: 2, fillColor: color, fillOpacity: 1 })
          .bindTooltip(tip)
          .addTo(layer);
        L.marker([s.to.lat, s.to.lng], { icon: arrowIcon(color, s.bearing || 0), keyboard: false }).bindTooltip(tip).addTo(layer);
      } else {
        L.circleMarker([s.to.lat, s.to.lng], { radius: 9, color, weight: 3, fillColor: '#fff', fillOpacity: 0.9 })
          .bindTooltip(tip)
          .addTo(layer);
      }
    });
  }, [spread]);

  useEffect(() => {
    if (focus && mapObj.current) mapObj.current.setView([focus.lat, focus.lng], 14);
  }, [focus]);

  const gradientCss = `linear-gradient(to right, ${Object.entries(HEAT_GRADIENT)
    .map(([stop, color]) => `${color} ${Number(stop) * 100}%`)
    .join(', ')})`;

  return (
    <div>
      {/* isolate keeps Leaflet's z-indexes below drawers and menus */}
      <div className="relative isolate">
        <div ref={mapRef} className={`w-full rounded-xl border border-line ${className}`} />
        {mode === 'heat' && (
          <div className="pointer-events-none absolute bottom-3 left-3 z-[1000] max-w-[260px] rounded-lg bg-white/95 px-3 py-2 text-xs font-medium text-ink shadow-md ring-1 ring-line">
            {t(HEAT_NOTE)}
          </div>
        )}
      </div>
      <div className="mt-3 flex flex-wrap items-center gap-2.5 text-sm text-ink2">
        {mode === 'heat' ? (
          <div className="flex flex-wrap items-center gap-3 rounded-full border border-line bg-white px-3 py-1.5 shadow-sm">
            <span className="font-semibold text-ink">{weightBy === 'cases' ? t('Number of validated cases') : t('Weighted by infestation level')}</span>
            <span className="text-xs font-semibold">{t('Low')}</span>
            <span className="inline-block h-3 w-40 rounded-full" style={{ background: gradientCss }} aria-hidden="true" />
            <span className="text-xs font-semibold">{t('High')}</span>
          </div>
        ) : (
          <>
            {Object.entries(LEVEL_COLOR).map(([k, v]) => (
              <span key={k} className="flex items-center gap-2 rounded-full border border-line bg-white px-3 py-1.5 font-bold text-ink shadow-sm">
                <span className="inline-block h-5 w-5 rounded-full ring-2 ring-white" style={{ background: v, boxShadow: `0 0 0 1px ${v}` }} />
                {t(k)}
              </span>
            ))}
            <span className="flex items-center gap-2 rounded-full border border-line bg-white px-3 py-1.5 shadow-sm">
              <span className="inline-block h-5 w-5 rounded-full" style={{ background: NO_LEVEL }} />
              {t('Disease report (no level)')}
            </span>
            <span className="flex items-center gap-2 rounded-full border border-line bg-white px-3 py-1.5 shadow-sm">
              <span className="inline-block h-5 w-5 rounded-full border-2 border-dashed border-ink2" />
              {t('Barangay hotspot, coloured by its highest confirmed level')}
            </span>
          </>
        )}
        {spread.some((s) => s.status === 'moved') && (
          <span className="flex items-center gap-2 rounded-full border border-line bg-white px-3 py-1.5 shadow-sm">
            <span className="inline-block w-6 border-t-[3px] border-dashed border-ink2" />
            {t('Direction reported cases moved')}
          </span>
        )}
        {onSelect && mode !== 'heat' && <span className="text-muted">{t('Click a point to open the record.')}</span>}
      </div>
    </div>
  );
}
