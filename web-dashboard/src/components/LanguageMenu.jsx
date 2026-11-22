import { useEffect, useRef, useState } from 'react';
import { LANGUAGES, useI18n } from '../i18n/index.jsx';
import Icon from './icons.jsx';

const HINTS = { en: 'English', fil: 'Tagalog / Filipino', krj: 'Karay-a (Antique)' };

/**
 * Language picker: a translate icon with the current code (EN / FIL / KRJ)
 * that opens a small menu. The choice applies at once, is kept in this
 * browser, and `onPicked(code)` lets the caller save it on the account.
 * `onDark` styles the button for the sign-in page's photo background.
 */
export default function LanguageMenu({ onPicked, onDark = false, align = 'right' }) {
  const { lang, setLang, t } = useI18n();
  const [open, setOpen] = useState(false);
  const ref = useRef(null);
  const current = LANGUAGES.find((l) => l.code === lang) || LANGUAGES[0];

  useEffect(() => {
    if (!open) return undefined;
    const onDown = (e) => ref.current && !ref.current.contains(e.target) && setOpen(false);
    const onKey = (e) => e.key === 'Escape' && setOpen(false);
    window.addEventListener('mousedown', onDown);
    window.addEventListener('keydown', onKey);
    return () => {
      window.removeEventListener('mousedown', onDown);
      window.removeEventListener('keydown', onKey);
    };
  }, [open]);

  const pick = (code) => {
    setOpen(false);
    if (code === lang) return;
    setLang(code);
    onPicked?.(code);
  };

  return (
    <div className="relative" ref={ref}>
      <button
        type="button"
        onClick={() => setOpen((o) => !o)}
        aria-haspopup="menu"
        aria-expanded={open}
        aria-label={`${t('Language')}: ${current.label}`}
        title={t('Language')}
        className={`inline-flex items-center gap-1.5 rounded-lg px-2 py-2 text-xs font-bold transition focus:outline-none focus-visible:ring-2 ${
          onDark
            ? 'bg-white/10 text-white ring-1 ring-white/25 hover:bg-white/20 focus-visible:ring-gold-400'
            : 'text-ink2 hover:bg-canvas hover:text-ink focus-visible:ring-brand-600'
        }`}
      >
        <Icon name="languages" className="h-[20px] w-[20px]" />
        <span>{current.short}</span>
      </button>

      {open && (
        <div
          role="menu"
          className={`absolute top-12 z-[1700] w-60 animate-fade-in overflow-hidden rounded-2xl border border-line bg-white text-left shadow-2xl ${
            align === 'left' ? 'left-0' : 'right-0'
          }`}
        >
          <div className="border-b border-line px-4 py-3 text-sm font-bold text-ink">{t('Choose your language')}</div>
          <ul className="py-1">
            {LANGUAGES.map((l) => {
              const on = l.code === lang;
              return (
                <li key={l.code}>
                  <button
                    type="button"
                    role="menuitemradio"
                    aria-checked={on}
                    onClick={() => pick(l.code)}
                    className={`flex w-full items-center gap-3 px-4 py-2.5 text-left hover:bg-canvas ${on ? 'bg-brand-50' : ''}`}
                  >
                    <span
                      className={`w-10 rounded-md py-0.5 text-center text-[11px] font-extrabold ${
                        on ? 'bg-brand-700 text-white' : 'bg-canvas text-ink2'
                      }`}
                    >
                      {l.short}
                    </span>
                    <span className="min-w-0 flex-1">
                      <span className="block text-sm font-semibold text-ink">{l.label}</span>
                      <span className="block text-xs text-muted">{HINTS[l.code]}</span>
                    </span>
                    {on && <Icon name="check" className="h-4 w-4 text-brand-700" />}
                  </button>
                </li>
              );
            })}
          </ul>
        </div>
      )}
    </div>
  );
}
