import { useEffect, useState } from 'react';
import { api } from '../api.js';
import { useT } from '../i18n/index.jsx';
import { fmtConf, pestLabel } from '../lib.js';

const MAIN = '#FACC15'; // boxes of the pest the model result settled on
const OTHER = '#38BDF8'; // boxes of any other pest it saw
const MAX_LABELS = 30; // beyond this, labels only on hover

/**
 * The full photo with the model result's detection boxes drawn over it. Boxes are
 * fractions (0–1) of the stored photo, so they're positioned in percent over
 * an <img> shown at its natural aspect ratio (no cropping) and line up at any size.
 */
export default function DetectionPhoto({ scanId, detections = [], mainPest }) {
  const t = useT();
  const [src, setSrc] = useState('');
  const [failed, setFailed] = useState(false);
  const [showBoxes, setShowBoxes] = useState(true);

  useEffect(() => {
    let alive = true;
    setSrc('');
    setFailed(false);
    api
      .imageUrl(scanId)
      .then((url) => alive && setSrc(url))
      .catch(() => alive && setFailed(true));
    return () => {
      alive = false;
    };
  }, [scanId]);

  const hasBoxes = detections.length > 0;
  const otherPests = [...new Set(detections.map((d) => d.pest).filter((p) => p !== mainPest))];

  return (
    <div>
      <div className="flex min-h-[220px] items-center justify-center overflow-hidden rounded-2xl border border-line bg-ink/90">
        {src ? (
          <div className="relative inline-block max-w-full">
            <img src={src} alt={t('Observation {id}', { id: scanId })} className="block h-auto max-h-[62vh] w-auto max-w-full" />
            {showBoxes &&
              detections.map((d, i) => {
                const color = d.pest === mainPest ? MAIN : OTHER;
                const tip = `${t(pestLabel(d.pest))} ${fmtConf(d.conf)}`;
                return (
                  <div
                    key={i}
                    title={tip}
                    className="absolute"
                    style={{
                      left: `${d.x1 * 100}%`,
                      top: `${d.y1 * 100}%`,
                      width: `${(d.x2 - d.x1) * 100}%`,
                      height: `${(d.y2 - d.y1) * 100}%`,
                      border: `2px solid ${color}`,
                      boxShadow: '0 0 0 1px rgba(0,0,0,.45)',
                    }}
                  >
                    {detections.length <= MAX_LABELS && (
                      <span
                        className={`absolute left-[-2px] top-0 whitespace-nowrap px-1 text-[10px] font-bold leading-4 text-ink ${
                          d.y1 < 0.04 ? '' : '-translate-y-full' // keep labels of boxes at the top edge inside the photo
                        }`}
                        style={{ background: color }}
                      >
                        {fmtConf(d.conf)}
                      </span>
                    )}
                  </div>
                );
              })}
          </div>
        ) : (
          <span className="p-8 text-sm text-brand-100">{failed ? t('Photo unavailable.') : t('Loading photo…')}</span>
        )}
      </div>
      <div className="mt-2 flex flex-wrap items-center justify-between gap-2 text-xs text-ink2">
        {hasBoxes ? (
          <label className="flex cursor-pointer items-center gap-2">
            <input type="checkbox" className="h-4 w-4 accent-brand-700" checked={showBoxes} onChange={(e) => setShowBoxes(e.target.checked)} />
            {t('Show model result boxes ({n})', { n: detections.length })}
            <span className="flex items-center gap-1">
              <span className="inline-block h-2.5 w-2.5" style={{ background: MAIN }} />
              {t(pestLabel(mainPest))}
            </span>
            {otherPests.length > 0 && (
              <span className="flex items-center gap-1">
                <span className="inline-block h-2.5 w-2.5" style={{ background: OTHER }} />
                {otherPests.map((p) => t(pestLabel(p))).join(', ')}
              </span>
            )}
          </label>
        ) : (
          <span />
        )}
        {src && (
          <a href={src} target="_blank" rel="noreferrer" className="font-semibold text-brand-700 hover:text-brand-900">
            {t('Open full size')}
          </a>
        )}
      </div>
    </div>
  );
}
