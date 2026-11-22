import { useEffect, useRef, useState } from 'react';
import { api, clearSession, rememberEmail, rememberedEmail, setToken } from '../api.js';
import slide1 from '../assets/login-1.jpg';
import slide2 from '../assets/login-2.jpg';
import slide3 from '../assets/login-3.jpg';
import bgUrl from '../assets/planting-rice.jpg';
import { APP_NAME, Wordmark } from './Brand.jsx';
import { useT } from '../i18n/index.jsx';
import Icon from './icons.jsx';
import LanguageMenu from './LanguageMenu.jsx';

export const STAFF = ['technician', 'agriculturist'];
const EMAIL = /^[^@\s]+@[^@\s]+\.[^@\s]+$/;

// Background photos, cross-faded in turn.
const SLIDES = [bgUrl, slide1, slide2, slide3];
const SLIDE_MS = 6000;

/** Index of the photo showing; moves on every SLIDE_MS while the tab is visible. */
function useSlide() {
  const [index, setIndex] = useState(0);
  useEffect(() => {
    const t = setInterval(() => document.visibilityState === 'visible' && setIndex((i) => (i + 1) % SLIDES.length), SLIDE_MS);
    return () => clearInterval(t);
  }, []);
  return [index, setIndex];
}

function Slideshow({ index }) {
  return SLIDES.map((src, i) => (
    <img
      key={src}
      src={src}
      alt=""
      aria-hidden="true"
      className={`absolute inset-0 h-full w-full object-cover transition-[opacity,transform] ease-out ${i === index ? 'scale-110 opacity-100' : 'scale-100 opacity-0'}`}
      // Fade in 1.4 s; the showing photo zooms in slowly for its whole turn.
      style={{ transitionDuration: i === index ? `1400ms, ${SLIDE_MS + 1400}ms` : '1400ms' }}
    />
  ));
}

function SlideDots({ index, onPick }) {
  const t = useT();
  return (
    <div className="mb-3 flex justify-center gap-2" role="group" aria-label={t('Background photos')}>
      {SLIDES.map((src, i) => (
        <button
          key={src}
          type="button"
          aria-pressed={i === index}
          aria-label={t('Show photo {n} of {total}', { n: i + 1, total: SLIDES.length })}
          onClick={() => onPick(i)}
          className={`h-2 rounded-full transition-all duration-500 focus:outline-none focus-visible:ring-2 focus-visible:ring-gold-400 ${
            i === index ? 'w-8 bg-gold-400' : 'w-2 bg-white/50 hover:bg-white/80'
          }`}
        />
      ))}
    </div>
  );
}

const FEATURES = [
  ['queue', 'Validate observations sent from the field'],
  ['map', 'Watch infestation hotspots on the map'],
  ['pill', 'Follow treatments and their results'],
];

/** Why a signed-in account can't use the dashboard, or null. */
export function accessProblem(status, role, requiredRole = 'agriculturist') {
  if (status === 'pending') {
    return role === requiredRole
      ? 'Your account is waiting for approval by an agriculturist.'
      : `This page is for ${requiredRole}s. Use the sign-in page for your account role.`;
  }
  if (status === 'rejected') {
    return 'Your account was not approved. Contact your municipal agriculture office if you think this is a mistake.';
  }
  if (role !== requiredRole) {
    return requiredRole === 'technician'
      ? 'This page is for technicians only. Agriculturists use the main dashboard sign-in; farmers use the mobile app.'
      : 'This page is for agriculturists. Technicians use the technician sign-in page; farmers use the mobile app.';
  }
  return null;
}

/**
 * Full-screen sign-in: rice-field photos (cross-fading) behind a welcome message on
 * the left and the form on the right (stacked on small screens).
 * Calls onAuthenticated() once the tokens are saved.
 */
export default function LoginScreen({ message, onAuthenticated, requiredRole = 'agriculturist' }) {
  const t = useT();
  const saved = rememberedEmail();
  const [email, setEmail] = useState(saved);
  const [password, setPassword] = useState('');
  const [remember, setRemember] = useState(Boolean(saved));
  const [showPassword, setShowPassword] = useState(false);
  const [capsLock, setCapsLock] = useState(false);
  const [fieldErrors, setFieldErrors] = useState({});
  const [error, setError] = useState(null); // { text, offline }
  const [shaking, setShaking] = useState(false);
  const [busy, setBusy] = useState(false);
  const [showHelp, setShowHelp] = useState(false);
  const passwordRef = useRef(null);
  const emailRef = useRef(null);
  const [slide, setSlide] = useSlide();

  useEffect(() => {
    (saved ? passwordRef : emailRef).current?.focus();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const fail = (text, offline = false) => {
    setError({ text, offline });
    setShaking(true);
  };

  const submit = async (e) => {
    e.preventDefault();
    if (busy) return;
    const trimmed = email.trim();
    const errs = {};
    if (!trimmed) errs.email = 'Enter your email address.';
    else if (!EMAIL.test(trimmed)) errs.email = 'That doesn’t look like an email address.';
    if (!password) errs.password = 'Enter your password.';
    setFieldErrors(errs);
    if (Object.keys(errs).length) {
      setError(null);
      setShaking(true);
      (errs.email ? emailRef : passwordRef).current?.focus();
      return;
    }

    setError(null);
    setBusy(true);
    try {
      const data = await api.login(trimmed, password);
      // Pending and rejected accounts still get a token; the dashboard refuses them.
      const problem = accessProblem(data.status, data.role, requiredRole);
      if (problem) {
        clearSession();
        fail(problem);
        return;
      }
      if (!data.access_token) {
        fail('Sign-in failed: the server did not return a session. Please try again.');
        return;
      }
      setToken(data.access_token, data.refresh_token, remember);
      rememberEmail(remember ? trimmed : '');
      onAuthenticated();
    } catch (err) {
      clearSession();
      fail(err.message || 'Something went wrong. Please try again.', err.kind === 'network');
      if (err.status === 401) {
        setPassword('');
        passwordRef.current?.focus();
      }
    } finally {
      setBusy(false);
    }
  };

  const onPasswordKey = (e) => setCapsLock(Boolean(e.getModifierState?.('CapsLock')));

  return (
    <div className="relative flex min-h-full flex-col overflow-hidden bg-brand-950">
      {/* Language: English / Filipino / Kinaray-a (before signing in too). */}
      <div className="absolute right-5 top-5 z-20 sm:right-8">
        <LanguageMenu onDark />
      </div>
      {/* Background photos with a green wash so text stays readable. */}
      <Slideshow index={slide} />
      <div className="absolute inset-0 bg-gradient-to-r from-brand-950/90 via-brand-950/60 to-brand-950/30" />
      <div className="absolute inset-0 bg-gradient-to-t from-brand-950/75 via-transparent to-brand-950/25" />

      <div className="relative z-10 mx-auto flex w-full max-w-6xl flex-1 flex-col gap-10 px-5 py-8 sm:px-8 lg:flex-row lg:items-center lg:gap-16 lg:py-12">
        {/* Welcome */}
        <section className="flex-1 animate-fade-up text-white">
          <Wordmark dark size="lg" subtitle={t('Web dashboard')} />
          <h1 className="mt-10 text-4xl font-extrabold leading-[1.05] tracking-tight sm:text-5xl lg:mt-14 lg:text-6xl">
            {t('Welcome')}
            <br />
            {t('Back')}
          </h1>
          <p className="mt-5 max-w-md text-[15px] leading-relaxed text-brand-100/85">
            {t('Sign in to validate field observations, monitor infestation hotspots and follow treatment results across your coverage area.')}
          </p>
          <ul className="mt-8 hidden space-y-3 sm:block">
            {FEATURES.map(([icon, text], i) => (
              <li
                key={icon}
                className="flex animate-fade-up items-center gap-3 text-sm text-white/90"
                style={{ animationDelay: `${150 + i * 90}ms` }}
              >
                <span className="flex h-9 w-9 items-center justify-center rounded-lg bg-white/10 text-gold-400 ring-1 ring-white/15 backdrop-blur">
                  <Icon name={icon} className="h-[18px] w-[18px]" />
                </span>
                {t(text)}
              </li>
            ))}
          </ul>
        </section>

        {/* Sign in */}
        <section className="w-full animate-fade-up lg:max-w-[420px]" style={{ animationDelay: '120ms' }}>
          <form
            onSubmit={submit}
            noValidate
            onAnimationEnd={(e) => e.target === e.currentTarget && setShaking(false)}
            className={`p-0 ${shaking ? 'animate-shake' : ''}`}
          >
            <h2 className="text-center text-3xl font-bold text-white">
              {t(requiredRole === 'technician' ? 'Technician sign in' : 'Agriculturist sign in')}
            </h2>
            <p className="mt-2 text-center text-base leading-relaxed text-white/90">
              {t(requiredRole === 'technician'
                ? 'Sign in with your approved technician account.'
                : 'Sign in with your approved agriculturist account.')}
            </p>

            {message && (
              <div className="mt-5 flex items-start gap-2 rounded-xl border border-gold-400/40 bg-gold-500/15 px-3 py-2.5 text-sm text-gold-300">
                <Icon name="alert" className="mt-0.5 h-4 w-4" />
                <span>{t(message)}</span>
              </div>
            )}

            <div className="mt-6 space-y-4">
              <div>
                <label htmlFor="email" className="mb-1.5 block text-base font-semibold text-white">
                  {t('Email address')}
                </label>
                <div className="relative">
                  <Icon name="mail" className="pointer-events-none absolute left-3.5 top-1/2 h-[18px] w-[18px] -translate-y-1/2 text-white/80" />
                  <input
                    id="email"
                    ref={emailRef}
                    className="auth-input"
                    type="email"
                    inputMode="email"
                    autoComplete="username"
                    placeholder="you@example.com"
                    value={email}
                    aria-invalid={Boolean(fieldErrors.email)}
                    aria-describedby={fieldErrors.email ? 'email-error' : undefined}
                    onChange={(e) => {
                      setEmail(e.target.value);
                      if (fieldErrors.email) setFieldErrors((f) => ({ ...f, email: undefined }));
                    }}
                  />
                </div>
                {fieldErrors.email && (
                  <p id="email-error" className="mt-1.5 text-xs font-medium text-red-300">
                    {t(fieldErrors.email)}
                  </p>
                )}
              </div>

              <div>
                <label htmlFor="password" className="mb-1.5 block text-base font-semibold text-white">
                  {t('Password')}
                </label>
                <div className="relative">
                  <Icon name="lock" className="pointer-events-none absolute left-3.5 top-1/2 h-[18px] w-[18px] -translate-y-1/2 text-white/80" />
                  <input
                    id="password"
                    ref={passwordRef}
                    className="auth-input pr-12"
                    type={showPassword ? 'text' : 'password'}
                    autoComplete="current-password"
                    placeholder={t('Your password')}
                    value={password}
                    aria-invalid={Boolean(fieldErrors.password)}
                    aria-describedby={fieldErrors.password ? 'password-error' : undefined}
                    onKeyDown={onPasswordKey}
                    onKeyUp={onPasswordKey}
                    onBlur={() => setCapsLock(false)}
                    onChange={(e) => {
                      setPassword(e.target.value);
                      if (fieldErrors.password) setFieldErrors((f) => ({ ...f, password: undefined }));
                    }}
                  />
                  <button
                    type="button"
                    onClick={() => setShowPassword((v) => !v)}
                    className="absolute right-2 top-1/2 -translate-y-1/2 rounded-lg p-2 text-white/80 hover:bg-white/10 hover:text-white focus:outline-none focus-visible:ring-2 focus-visible:ring-gold-400"
                    aria-label={t(showPassword ? 'Hide password' : 'Show password')}
                    title={t(showPassword ? 'Hide password' : 'Show password')}
                  >
                    <Icon name={showPassword ? 'eyeOff' : 'eye'} className="h-[18px] w-[18px]" />
                  </button>
                </div>
                {fieldErrors.password && (
                  <p id="password-error" className="mt-1.5 text-xs font-medium text-red-300">
                    {t(fieldErrors.password)}
                  </p>
                )}
                {capsLock && !fieldErrors.password && <p className="mt-1.5 text-xs font-medium text-gold-300">{t('Caps Lock is on.')}</p>}
              </div>

              <div className="flex items-center justify-between gap-3 text-sm">
                <label className="flex cursor-pointer select-none items-center gap-2 text-white/85">
                  <input
                    type="checkbox"
                    checked={remember}
                    onChange={(e) => setRemember(e.target.checked)}
                    className="h-4 w-4 cursor-pointer rounded border-white/40 accent-gold-500"
                  />
                  {t('Remember me')}
                </label>
                <button
                  type="button"
                  onClick={() => setShowHelp((v) => !v)}
                  className="font-semibold text-gold-300 underline-offset-4 hover:underline focus:outline-none focus-visible:underline"
                  aria-expanded={showHelp}
                >
                  {t('Forgot password?')}
                </button>
              </div>

              {showHelp && (
                <div className="animate-fade-in rounded-xl border border-white/15 bg-white/10 px-3 py-2.5 text-xs leading-relaxed text-white/85">
                  {t('Password resets are handled by your Municipal Agriculture Office. Contact them or an agriculturist on this dashboard and they will help you get back into your account.')}
                </div>
              )}

              {error && (
                <div
                  role="alert"
                  className="flex items-start gap-2.5 rounded-xl border border-red-300/40 bg-red-500/15 px-3 py-2.5 text-sm text-red-100"
                >
                  <Icon name={error.offline ? 'wifiOff' : 'alert'} className="mt-0.5 h-4 w-4 text-red-300" />
                  <span>{t(error.text)}</span>
                </div>
              )}

              <button
                type="submit"
                disabled={busy}
                className="group flex w-full items-center justify-center gap-2 rounded-xl bg-gold-500 px-4 py-3 text-sm font-bold text-brand-950 shadow-lg shadow-gold-500/20 transition hover:bg-gold-400 focus:outline-none focus-visible:ring-4 focus-visible:ring-gold-400/40 disabled:cursor-wait disabled:opacity-80"
              >
                {busy ? (
                  <>
                    <span className="h-4 w-4 animate-spin rounded-full border-2 border-brand-950 border-r-transparent" />
                    {t('Signing in…')}
                  </>
                ) : (
                  <>
                    {t('Sign in')}
                    <Icon name="arrowRight" className="h-4 w-4 transition-transform group-hover:translate-x-0.5" />
                  </>
                )}
              </button>
            </div>

            <p className="mt-6 flex items-center justify-center gap-1.5 text-center text-sm text-white/90">
              <Icon name="shield" className="h-3.5 w-3.5" />
              {t(requiredRole === 'technician' ? 'Technicians only.' : 'Agriculturists only.')}
            </p>
            <p className="mt-4 text-center text-sm text-white/90">
              {t(requiredRole === 'technician' ? 'Agriculturist?' : 'Technician?')}{' '}
              <a
                href={requiredRole === 'technician' ? '/' : '/technician-login'}
                className="font-bold text-gold-300 underline underline-offset-4 hover:text-gold-200"
              >
                {t(requiredRole === 'technician' ? 'Main dashboard sign in' : 'Technician sign in')}
              </a>
            </p>
          </form>
        </section>
      </div>

      <footer className="relative z-10 px-5 pb-5 text-center text-xs text-white/45 sm:px-8">
        <SlideDots index={slide} onPick={setSlide} />
        © {new Date().getFullYear()} {APP_NAME} · {t('Province of Antique')}
      </footer>
    </div>
  );
}
