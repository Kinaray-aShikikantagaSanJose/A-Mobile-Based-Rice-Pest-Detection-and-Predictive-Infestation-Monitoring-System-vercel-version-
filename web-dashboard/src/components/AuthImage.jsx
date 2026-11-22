import { useEffect, useRef, useState } from 'react';
import { api } from '../api.js';
import { useT } from '../i18n/index.jsx';

/** Scan photo from /sync/scans/{id}/image (needs the login token, so it's
 *  fetched as a blob). Loads only once it scrolls into view. */
export default function AuthImage({ scanId, alt, className = '' }) {
  const t = useT();
  const ref = useRef(null);
  const [visible, setVisible] = useState(false);
  const [src, setSrc] = useState('');
  const [failed, setFailed] = useState(false);

  useEffect(() => {
    const el = ref.current;
    if (!el || visible) return undefined;
    if (!('IntersectionObserver' in window)) {
      setVisible(true);
      return undefined;
    }
    const io = new IntersectionObserver(
      (entries) => {
        if (entries.some((e) => e.isIntersecting)) {
          setVisible(true);
          io.disconnect();
        }
      },
      { rootMargin: '200px' },
    );
    io.observe(el);
    return () => io.disconnect();
  }, [visible]);

  useEffect(() => {
    if (!visible) return undefined;
    let alive = true;
    setFailed(false);
    api
      .imageUrl(scanId)
      .then((url) => alive && setSrc(url))
      .catch(() => alive && setFailed(true));
    return () => {
      alive = false;
    };
  }, [visible, scanId]);

  return (
    <div ref={ref} className={`overflow-hidden bg-brand-50 ${className}`}>
      {src ? (
        <img src={src} alt={alt ?? t('Scan photo')} className="h-full w-full object-cover" />
      ) : (
        <div className="flex h-full w-full items-center justify-center text-muted" title={failed ? t('Photo unavailable') : undefined}>
          {failed && (
            <svg width="40%" height="40%" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round" aria-label={t('Photo unavailable')}>
              <rect x="3" y="5" width="18" height="14" rx="2" />
              <circle cx="9" cy="10" r="1.6" />
              <path d="m21 16-5-5-8 8" />
              <path d="M3 3l18 18" />
            </svg>
          )}
        </div>
      )}
    </div>
  );
}
