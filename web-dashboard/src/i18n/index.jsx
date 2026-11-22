import { createContext, useCallback, useContext, useEffect, useMemo, useState } from 'react';
import { TRANSLATIONS } from './strings.js';

/**
 * Dashboard languages. Keys are the English text itself: `t('Validated records')`
 * looks the text up in ./parts/*.js and falls back to the English text when a
 * translation is missing, so nothing ever shows blank.
 *
 *   en  - English
 *   fil - Filipino (simple, everyday words)
 *   krj - Kinaray-a / Karay-a as spoken in Antique (ISO 639-3 "krj")
 *
 * Placeholders: t('{n} observations', { n: 3 }).
 */
export const LANGUAGES = [
  { code: 'en', label: 'English', short: 'EN', locale: 'en-PH' },
  { code: 'fil', label: 'Filipino', short: 'FIL', locale: 'fil-PH' },
  { code: 'krj', label: 'Kinaray-a', short: 'KRJ', locale: 'fil-PH' },
];
const CODES = LANGUAGES.map((l) => l.code);
const STORAGE_KEY = 'rp_lang';

function readStored() {
  try {
    const v = window.localStorage.getItem(STORAGE_KEY);
    return CODES.includes(v) ? v : null;
  } catch {
    return null;
  }
}

/** True once the person picked a language on this browser (it then wins over the account's). */
export const hasStoredLanguage = () => readStored() !== null;

let current = readStored() || 'en';

export const currentLanguage = () => current;
/** Intl locale for dates and numbers (Kinaray-a uses the Filipino calendar words). */
export const currentLocale = () => LANGUAGES.find((l) => l.code === current)?.locale || 'en-PH';

function fill(text, vars) {
  if (!vars) return text;
  return text.replace(/\{(\w+)\}/g, (m, k) => (vars[k] === undefined || vars[k] === null ? m : String(vars[k])));
}

/** Translates `text` (English) into the current language. Usable outside components too. */
export function translate(text, vars, lang = current) {
  if (text === null || text === undefined) return '';
  const s = String(text);
  if (lang === 'en') return fill(s, vars);
  const entry = TRANSLATIONS[s];
  return fill((entry && entry[lang]) || s, vars);
}

const I18nContext = createContext({ lang: 'en', setLang: () => {}, t: translate, locale: 'en-PH' });

const listeners = new Set();

/** Changes the language everywhere (and remembers it on this browser). */
export function setLanguage(code, { remember = true } = {}) {
  if (!CODES.includes(code) || code === current) return;
  current = code;
  if (remember) {
    try {
      window.localStorage.setItem(STORAGE_KEY, code);
    } catch {
      /* private mode: this tab only */
    }
  }
  document.documentElement.lang = code === 'en' ? 'en' : code;
  listeners.forEach((fn) => fn(code));
}

export function I18nProvider({ children }) {
  const [lang, setLang] = useState(current);
  useEffect(() => {
    document.documentElement.lang = lang === 'en' ? 'en' : lang;
    const on = (code) => setLang(code);
    listeners.add(on);
    return () => listeners.delete(on);
  }, [lang]);
  const t = useCallback((text, vars) => translate(text, vars, lang), [lang]);
  const value = useMemo(
    () => ({ lang, setLang: setLanguage, t, locale: LANGUAGES.find((l) => l.code === lang)?.locale || 'en-PH' }),
    [lang, t],
  );
  return <I18nContext.Provider value={value}>{children}</I18nContext.Provider>;
}

/** `{ lang, setLang, t, locale }` — components re-render when the language changes. */
export const useI18n = () => useContext(I18nContext);
/** Shorthand: `const t = useT();` */
export const useT = () => useContext(I18nContext).t;
