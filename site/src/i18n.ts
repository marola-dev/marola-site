/** t() over the catalogs and the ICU subset they use: {arg}, {n, plural, ...} with #, {x, select, ...} (MIP-0054 §5.5). */
import { CATALOG } from './catalog.ts';

const SOURCE = 'pt-BR';
const PSEUDO = 'x-pseudo';
export const SUPPORTED = Object.keys(CATALOG).filter((l) => l !== PSEUDO);

export type Args = Readonly<Record<string, string | number | undefined>>;

interface Arg {
  name: string;
  type?: string;
  cases: Record<string, Part[]>;
}
type Part = string | Arg | null; // null is a plural's #

function parse(s: string): Part[] {
  let i = 0;
  const fail = (what: string): never => {
    throw new Error(`i18n: expected ${what} at ${i} in ${s}`);
  };
  const skipSpace = (): void => {
    while (/\s/.test(s.charAt(i))) i++;
  };
  const word = (): string => {
    const m = /^\s*([^\s,{}]+)\s*/.exec(s.slice(i));
    if (!m?.[1]) return fail('a name');
    i += m[0].length;
    return m[1];
  };
  const expect = (c: string): void => {
    if (s.charAt(i) !== c) fail(c);
    i++;
  };
  const message = (inPlural: boolean): Part[] => {
    const out: Part[] = [];
    let text = '';
    while (i < s.length && s.charAt(i) !== '}') {
      const c = s.charAt(i++);
      if (c === '{' || (c === '#' && inPlural)) {
        if (text) out.push(text);
        text = '';
        out.push(c === '{' ? argument(inPlural) : null);
      } else text += c;
    }
    if (text) out.push(text);
    return out;
  };
  const argument = (inPlural: boolean): Arg => {
    const node: Arg = { name: word(), cases: {} };
    if (s.charAt(i) === ',') {
      i++;
      node.type = word();
      expect(',');
      skipSpace();
      while (i < s.length && s.charAt(i) !== '}') {
        const key = word();
        expect('{');
        node.cases[key] = message(inPlural || node.type === 'plural');
        expect('}');
        skipSpace();
      }
    }
    expect('}');
    return node;
  };
  const nodes = message(false);
  if (i !== s.length) throw new Error(`i18n: unbalanced } in ${s}`);
  return nodes;
}

// Intl rejects the private-use x-pseudo tag, so it formats like the source language.
const intlLang = (lang: string): string => (lang === PSEUDO ? SOURCE : lang);

const number = (n: number, lang: string): string => new Intl.NumberFormat(intlLang(lang)).format(n);

function render(parts: Part[], args: Args, lang: string, n: number): string {
  return parts
    .map((x) => {
      if (typeof x === 'string') return x;
      if (x === null) return number(n, lang);
      const v = args[x.name];
      if (!x.type) return v === undefined ? `{${x.name}}` : typeof v === 'number' ? number(v, lang) : v;
      if (x.type === 'plural') {
        const count = Number(v);
        const c = x.cases[`=${count}`] ?? x.cases[new Intl.PluralRules(intlLang(lang)).select(count)] ?? x.cases.other ?? [];
        return render(c, args, lang, count);
      }
      return render(x.cases[String(v)] ?? x.cases.other ?? [], args, lang, n);
    })
    .join('');
}

const parsed = new Map<string, Part[]>();

export function format(message: string, args: Args = {}, lang: string = SOURCE): string {
  let parts = parsed.get(message);
  if (!parts) parsed.set(message, (parts = parse(message)));
  return render(parts, args, lang, 0);
}

let current = SOURCE;
export const lang = (): string => current;
export const locale = (): string => intlLang(current);
export const setCurrent = (l: string): void => {
  current = l;
};

const lookup = (key: string, l: string): string | undefined => {
  const cat = CATALOG[l];
  // hasOwnProperty, not Object.hasOwn: Safari before 15.4 has no hasOwn
  return cat && Object.prototype.hasOwnProperty.call(cat, key) ? cat[key] : undefined;
};

export function t(key: string, args?: Args): string {
  const own = lookup(key, current);
  if (own !== undefined) return format(own, args, current);
  const source = lookup(key, SOURCE);
  return source === undefined ? key : format(source, args, SOURCE);
}

export const has = (key: string): boolean => lookup(key, current) !== undefined || lookup(key, SOURCE) !== undefined;

export interface LangInput {
  param?: string | null;
  stored?: string | null;
  languages?: readonly string[];
  supported: readonly string[];
}

function match(tag: string | null | undefined, supported: readonly string[]): string | undefined {
  if (!tag) return undefined;
  const lower = tag.toLowerCase();
  const primary = lower.split('-')[0];
  return supported.find((l) => l.toLowerCase() === lower) ?? supported.find((l) => l.toLowerCase().split('-')[0] === primary);
}

/** §5.5: ?lang=, then the stored choice, then the browser's languages, then pt-BR. x-pseudo only from ?lang=. */
export function resolveLang({ param, stored, languages = [], supported }: LangInput): string {
  if (param === PSEUDO) return PSEUDO;
  for (const tag of [param, stored, ...languages]) {
    const hit = match(tag, supported);
    if (hit) return hit;
  }
  return SOURCE;
}
