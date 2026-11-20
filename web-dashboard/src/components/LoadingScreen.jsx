import { APP_NAME, Logo } from './Brand.jsx';
import Icon from './icons.jsx';

/**
 * Shown between sign-in and the dashboard (and when a saved session is
 * resumed): the logo with pulsing rings, the steps being done, a progress bar.
 * With `error` set it becomes an error card with Try again / Sign in again.
 */
export default function LoadingScreen({ steps, current, name, error, onRetry, onSignOut }) {
  const progress = error ? 0 : Math.min(1, (current + 0.5) / steps.length);
  return (
    <div
      className="relative flex min-h-full items-center justify-center overflow-hidden bg-brand-950 px-5 py-10 text-white"
      role="status"
      aria-live="polite"
      aria-busy={!error}
    >
      {/* Soft light blooms */}
      <div className="pointer-events-none absolute -left-32 -top-32 h-96 w-96 rounded-full bg-brand-700/40 blur-3xl" />
      <div className="pointer-events-none absolute -bottom-40 -right-24 h-[28rem] w-[28rem] rounded-full bg-gold-500/15 blur-3xl" />

      <div className="relative w-full max-w-sm animate-fade-up text-center">
        <div className="relative mx-auto flex h-32 w-32 items-center justify-center">
          {!error && (
            <>
              <span className="absolute inset-0 animate-pulse-ring rounded-full bg-gold-400/30" />
              <span className="absolute inset-0 animate-pulse-ring rounded-full bg-leaf/30 [animation-delay:0.9s]" />
            </>
          )}
          <span className={`relative flex h-28 w-28 items-center justify-center rounded-full bg-white shadow-2xl shadow-black/30 ${error ? '' : 'animate-float'}`}>
            <Logo className="h-20 w-20" />
          </span>
        </div>

        <div className="mt-6 text-2xl font-extrabold tracking-tight">
          Palay <span className="text-gold-400">Patrol</span>
        </div>

        {error ? (
          <div className="mt-6 animate-fade-up rounded-2xl border border-white/10 bg-white/[0.06] p-5 text-left backdrop-blur">
            <div className="flex items-start gap-3">
              <span className="flex h-10 w-10 shrink-0 items-center justify-center rounded-full bg-red-500/15 text-red-300">
                <Icon name={error.offline ? 'wifiOff' : 'alert'} />
              </span>
              <div className="min-w-0">
                <div className="font-semibold">{error.title}</div>
                <p className="mt-1 text-sm leading-relaxed text-brand-100/80">{error.text}</p>
              </div>
            </div>
            <div className="mt-5 flex flex-col gap-2 sm:flex-row">
              <button
                type="button"
                onClick={onRetry}
                className="inline-flex flex-1 items-center justify-center gap-2 rounded-xl bg-gold-500 px-4 py-2.5 text-sm font-bold text-brand-950 transition hover:bg-gold-400 focus:outline-none focus-visible:ring-4 focus-visible:ring-gold-400/40"
              >
                <Icon name="refresh" className="h-4 w-4" />
                Try again
              </button>
              <button
                type="button"
                onClick={onSignOut}
                className="inline-flex flex-1 items-center justify-center gap-2 rounded-xl border border-white/20 px-4 py-2.5 text-sm font-semibold text-white transition hover:bg-white/10 focus:outline-none focus-visible:ring-4 focus-visible:ring-white/20"
              >
                <Icon name="logout" className="h-4 w-4" />
                Sign in again
              </button>
            </div>
          </div>
        ) : (
          <>
            <p className="mt-1 h-5 text-sm text-brand-100/75">{name ? `Welcome, ${name}` : 'Getting things ready'}</p>

            <div className="mx-auto mt-7 h-1.5 w-full overflow-hidden rounded-full bg-white/10">
              <div
                className="relative h-full overflow-hidden rounded-full bg-gradient-to-r from-leaf to-gold-400 transition-[width] duration-500 ease-out"
                style={{ width: `${progress * 100}%` }}
              >
                <span className="absolute inset-y-0 w-1/3 animate-indeterminate bg-white/40 blur-[2px]" />
              </div>
            </div>

            <ol className="mt-6 space-y-2.5 text-left">
              {steps.map((label, i) => {
                const done = i < current;
                const active = i === current;
                return (
                  <li
                    key={label}
                    className={`flex items-center gap-3 rounded-xl px-3 py-2 text-sm transition-colors duration-300 ${
                      active ? 'bg-white/[0.07] text-white' : done ? 'text-brand-100/85' : 'text-brand-100/40'
                    }`}
                  >
                    <span className="flex h-6 w-6 shrink-0 items-center justify-center">
                      {done ? (
                        <span className="flex h-6 w-6 animate-fade-in items-center justify-center rounded-full bg-leaf text-white">
                          <Icon name="check" className="h-3.5 w-3.5" strokeWidth={3} />
                        </span>
                      ) : active ? (
                        <span className="h-5 w-5 animate-spin rounded-full border-2 border-gold-400 border-r-transparent" />
                      ) : (
                        <span className="h-2 w-2 rounded-full bg-white/25" />
                      )}
                    </span>
                    {label}
                  </li>
                );
              })}
            </ol>
          </>
        )}

        <p className="mt-8 text-xs text-white/35">{APP_NAME} · Web dashboard</p>
      </div>
    </div>
  );
}
