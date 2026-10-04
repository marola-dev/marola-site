/** Page chrome every page shares: the language picked on load, the pt/en toggle, and data-i18n* text (MIP-0054 §5.5, §5.8). */
import { has, lang, resolveLang, setCurrent, SUPPORTED, t } from './i18n.ts';

const STORE_KEY = 'marola.lang';
const ATTRS = ['title', 'aria-label', 'placeholder'] as const;
const listeners: ((lang: string) => void)[] = [];

export const onLang = (fn: (lang: string) => void): void => {
  listeners.push(fn);
};

export function setParam(name: string, value: string | null): void {
  const u = new URL(location.href);
  if (value === null) u.searchParams.delete(name);
  else u.searchParams.set(name, value);
  history.replaceState(null, '', u);
}

export const param = (name: string): string | null => new URLSearchParams(location.search).get(name);

export const closest = (target: EventTarget | null, selector: string): HTMLElement | null =>
  (target as Element | null)?.closest<HTMLElement>(selector) ?? null;

// A key missing from every catalog leaves the source text as it is rather than showing the key.
function applyLang(): void {
  for (const el of document.querySelectorAll('[data-i18n]')) {
    const k = el.getAttribute('data-i18n');
    if (k && has(k)) el.textContent = t(k);
  }
  for (const attr of ATTRS) {
    for (const el of document.querySelectorAll(`[data-i18n-${attr}]`)) {
      const k = el.getAttribute(`data-i18n-${attr}`);
      if (k && has(k)) el.setAttribute(attr, t(k));
    }
  }
  document.documentElement.lang = lang();
  for (const b of document.querySelectorAll('#lang button[data-lang]')) {
    b.setAttribute('aria-pressed', String(b.getAttribute('data-lang') === lang()));
  }
}

// Private mode or blocked site data makes every localStorage access throw.
function readStored(): string | null {
  try {
    return localStorage.getItem(STORE_KEY);
  } catch {
    return null;
  }
}
function writeStored(value: string): void {
  try {
    localStorage.setItem(STORE_KEY, value);
  } catch {
    /* the choice lasts this page only */
  }
}

function setLang(next: string): void {
  if (!SUPPORTED.includes(next)) return;
  setCurrent(next);
  writeStored(next);
  setParam('lang', next);
  applyLang();
  for (const fn of listeners) fn(next);
}

export function initChrome(): void {
  setCurrent(
    resolveLang({
      param: param('lang'),
      stored: readStored(),
      languages: navigator.languages,
      supported: SUPPORTED,
    }),
  );
  applyLang();
  document.getElementById('lang')?.addEventListener('click', (e) => {
    const next = closest(e.target, 'button[data-lang]')?.getAttribute('data-lang');
    if (next && next !== lang()) setLang(next);
  });
}
