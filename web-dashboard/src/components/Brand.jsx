import logoUrl from '../assets/logo.png';

export const APP_NAME = 'Palay Patrol';

/** The Palay Patrol logo (transparent PNG). `tile` puts it on a light rounded square for dark backgrounds. */
export function Logo({ className = 'h-10 w-10', tile = false }) {
  const img = <img src={logoUrl} alt={`${APP_NAME} logo`} className="h-full w-full object-contain" draggable="false" />;
  if (!tile) return <span className={`inline-flex shrink-0 ${className}`}>{img}</span>;
  return (
    <span className={`inline-flex shrink-0 items-center justify-center rounded-xl bg-white/95 p-1 shadow-sm ring-1 ring-black/5 ${className}`}>
      {img}
    </span>
  );
}

/** Logo plus the app name, for headers. */
export function Wordmark({ subtitle, dark = false, size = 'md' }) {
  const big = size === 'lg';
  return (
    <div className="flex items-center gap-3">
      <Logo className={big ? 'h-14 w-14' : 'h-10 w-10'} tile={dark} />
      <div className="min-w-0">
        <div className={`font-extrabold tracking-tight ${big ? 'text-2xl' : 'text-base'} ${dark ? 'text-white' : 'text-ink'}`}>
          Palay <span className={dark ? 'text-gold-400' : 'text-gold-600'}>Patrol</span>
        </div>
        {subtitle && <div className={`truncate text-xs ${dark ? 'text-brand-100/75' : 'text-ink2'}`}>{subtitle}</div>}
      </div>
    </div>
  );
}
