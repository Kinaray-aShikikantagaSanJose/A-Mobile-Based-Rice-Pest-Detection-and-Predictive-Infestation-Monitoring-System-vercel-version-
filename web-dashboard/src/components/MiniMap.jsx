import { useEffect, useRef } from 'react';
import L from 'leaflet';
import { useT } from '../i18n/index.jsx';
import { osmLink } from '../lib.js';
import { TILE_ATTRIBUTION, TILE_URL } from './HotspotMap.jsx';

/** Small, non-interactive map pinning one observation's GPS location. */
export default function MiniMap({ lat, lng }) {
  const t = useT();
  const ref = useRef(null);

  useEffect(() => {
    const map = L.map(ref.current, {
      zoomControl: false,
      attributionControl: false,
      scrollWheelZoom: false,
      dragging: false,
      doubleClickZoom: false,
      boxZoom: false,
      keyboard: false,
      touchZoom: false,
    }).setView([lat, lng], 15);
    L.tileLayer(TILE_URL, { maxZoom: 17, attribution: TILE_ATTRIBUTION }).addTo(map);
    // circleMarker avoids Leaflet's default marker images, which Vite doesn't bundle.
    L.circleMarker([lat, lng], { radius: 8, color: '#ffffff', weight: 3, fillColor: '#E63946', fillOpacity: 1 }).addTo(map);
    const ro = new ResizeObserver(() => map.invalidateSize());
    ro.observe(ref.current);
    return () => {
      ro.disconnect();
      map.remove();
    };
  }, [lat, lng]);

  return (
    <div>
      <div ref={ref} className="isolate h-40 w-full rounded-xl border border-line" />
      <a
        className="mt-1 inline-block text-xs text-brand-700 underline decoration-brand-200 underline-offset-2 hover:text-brand-900"
        href={osmLink(lat, lng)}
        target="_blank"
        rel="noreferrer"
      >
        {lat.toFixed(5)}, {lng.toFixed(5)} · {t('open in OpenStreetMap')}
      </a>
    </div>
  );
}
