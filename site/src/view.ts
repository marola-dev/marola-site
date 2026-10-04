/** HTML for the tooltips, list, card and footer, built from the board in the current language. Every string a
 * visitor reads goes through t(); board data is escaped. */
import { band, type Beach, type Board, hourEntry, isPast, noWaterData, type NoteCode, type Shown, type Trail, type WaterPoint } from './board.ts';
import { icon } from './icons.ts';
import { type Args, locale, t } from './i18n.ts';

const ENTITIES: Readonly<Record<string, string>> = { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' };
export const esc = (s: string | number): string => String(s).replace(/[&<>"']/g, (c) => ENTITIES[c] ?? c);

/** t() for text with plain-text args, escaped whole; markup args go through bare t() pre-escaped. */
export const tx = (key: string, args?: Args): string => esc(t(key, args));

const formats = new Map<string, Intl.NumberFormat>();
function num(n: number, digits: number): string {
  const key = `${locale()}${digits}`;
  let f = formats.get(key);
  if (!f) formats.set(key, (f = new Intl.NumberFormat(locale(), { minimumFractionDigits: digits, maximumFractionDigits: digits })));
  return f.format(n);
}

// A no-break space keeps "6 s" together when a tooltip cell wraps.
const fmt = (n: number | null | undefined, unit = '', digits = 1): string =>
  n === null || n === undefined ? t('common.na') : num(n, digits) + unit.replace(' ', ' ');

const shortDate = (iso: string): string =>
  new Intl.DateTimeFormat(locale(), { day: 'numeric', month: 'short', timeZone: 'UTC' }).format(new Date(`${iso}T00:00:00Z`));

/** A wire enum through the catalog (wind.*, lvl.*, dir.*); a value with no key passes through. */
function word(prefix: string, v: string): string {
  const key = prefix + v.toLowerCase();
  const out = t(key);
  return out === key ? v : out;
}

const COMPASS = ['n', 'ne', 'e', 'se', 's', 'sw', 'w', 'nw'] as const;
const compass = (deg: number): string => word('dir.', COMPASS[Math.round(deg / 45) % 8] ?? 'n');

const yesNo = (b: boolean): string => (b ? 'yes' : 'no');

const waterSummary = (beach: Beach): string => (noWaterData(beach) ? t('water.no_data') : beach.water.summary);

const condLabel = (c: WaterPoint['condition']): string =>
  c === 'proper' ? 'PRÓPRIA' : c === 'improper' ? 'IMPRÓPRIA' : t('water.unclassified');

const wavesText = (waveM: number | null, periodS: number | null): string =>
  t('cell.waves', { m: fmt(waveM, ' m'), every: yesNo(periodS !== null), s: fmt(periodS, ' s', 0) });

const FACILITIES = ['parking', 'toilets', 'shower', 'lifeguard'] as const;
function facilitiesHtml(beach: Beach): string {
  const f = beach.facilities ?? {};
  return FACILITIES.flatMap((k) => {
    const n = f[k];
    return n === undefined ? [] : [`${icon(k)} ${tx(`fac.${k}`, { n })}`];
  }).join(' · ');
}

/** The hover tooltip's aspect grid; the card repeats it first, since touch has no hover (MIP-0009 §3). */
export function aspectsHtml(beach: Beach, s: Shown | null): string {
  const head = `<div class="head">${esc(beach.name)} · ${s ? tx('tip.at', { score: s.score, h: s.h }) : tx('tip.dark')}</div>`;
  const e = hourEntry(beach, s);
  if (!s || !e) return head;
  const kmh = fmt(e.wind_kmh, ' km/h', 0);
  // an older board has no wind band: number only, no word
  const wind =
    `${icon('wind')} ${e.wind_level ? `${esc(word('wind.', e.wind_level))}, ${esc(kmh)}` : tx('cell.wind', { v: kmh })}` +
    (s.best && beach.sea.wind_dir_deg !== null ? ` <abbr class="dir">${esc(compass(beach.sea.wind_dir_deg))}</abbr>` : '');
  const peak = beach.whales.peak && beach.whales.peak !== e.h;
  const whales = tx('cell.whales', { level: word('lvl.', e.whales), best: yesNo(!!peak), peak: beach.whales.peak ?? '' });
  const facilities = facilitiesHtml(beach);
  return (
    `${head}<div class="grid">` +
    `<span>${wind}</span>` +
    `<span>${icon('thermometer')} ${tx('cell.water', { v: fmt(e.sea_temp_c, ' °C') })}</span>` +
    `<span>${icon('waves')} ${esc(wavesText(e.wave_m, s.best ? beach.sea.period_s : null))}</span>` +
    `<span>${icon('jellyfish')} ${tx('cell.jellyfish', { level: word('lvl.', e.jellyfish) })}</span>` +
    `<span>${icon('fish')} ${whales}</span>` +
    `<span class="wide ${beach.water.unfit ? 'unfit' : 'water'}"><i class="wdot ${beach.water.unfit ? 'c0' : noWaterData(beach) ? 'cna' : 'c70'}"></i> ${esc(waterSummary(beach))}</span>` +
    (facilities ? `<span class="wide facilities">${facilities}</span>` : '') +
    '</div>'
  );
}

/** A white ring keeps neighbouring dots apart; the selected one grows into a numbered badge. */
export function dotSvg(fill: string, selected: boolean, score: number | null, darkText: boolean): string {
  const size = selected ? 32 : 16;
  const r = size / 2;
  const label =
    selected && score !== null
      ? `<text x="16" y="20.5" text-anchor="middle" font-size="13" font-weight="600" fill="${darkText ? '#181b22' : '#fff'}">${esc(score)}</text>`
      : '';
  return (
    `<svg viewBox="0 0 ${size} ${size}" width="${size}" height="${size}" aria-hidden="true">` +
    `<circle cx="${r}" cy="${r}" r="${r - 0.5}" fill="#1d2733"/>` +
    `<circle cx="${r}" cy="${r}" r="${r - 2}" fill="${esc(fill)}" stroke="#fff" stroke-width="2"/>${label}</svg>`
  );
}

export const trailTipHtml = (trail: Trail): string => `${icon('footprints')} ${esc(trail.name)} · ${fmt(trail.length_km, ' km')}`;

export const waterPointTipHtml = (p: WaterPoint): string =>
  `<span class="water">${esc(p.point)} (${esc(p.location)}): ${esc(condLabel(p.condition))}, ${esc(p.sampled_on)}</span>`;

export function daysHtml(days: readonly { day: string; file: string }[], picked: string | null): string {
  return days
    .map((d, i) => {
      const date = esc(d.day.slice(5));
      // a third day and later are named by their date alone, so the picker fits one row on a phone
      const label = i === 0 ? `${tx('day.today')} <small>${date}</small>` : i === 1 ? `${tx('day.tomorrow')} <small>${date}</small>` : date;
      return `<button type="button"${d.day === picked ? ' class="on"' : ''} data-day="${esc(d.day)}" data-file="${esc(d.file)}">${label}</button>`;
    })
    .join('');
}

export function listHtml(rows: readonly { beach: Beach; km: number | null; shown: Shown | null }[]): string {
  const items = rows.map(({ beach: b, km, shown: s }) => {
    const water = b.water.unfit
      ? `<span class="water unfit">${esc(waterSummary(b))}</span>`
      : b.water.points.length
        ? `<span class="water">${esc(waterSummary(b))}</span>`
        : '';
    const dist = km === null ? '' : ` <span class="dist">${num(km, 1)} km</span>`;
    return (
      `<li data-name="${esc(b.name)}"><span class="score ${band(s?.score, b.water.unfit)}">${s ? s.score : '–'}</span>` +
      `${esc(b.name)} <span class="dist">${s ? esc(s.h) : tx('list.dark')}</span>${dist}${water}</li>`
    );
  });
  return `<ol>${items.join('')}</ol>`;
}

// MIP-0054 note codes carry raw numbers; round them as the English notes did.
const NOTE_ARGS: Readonly<Record<string, (v: unknown) => string>> = {
  wave_m: (v) => num(Number(v), 1),
  sea_temp_c: (v) => num(Number(v), 1),
  wind_kmh: (v) => num(Number(v), 0),
  rain_pct: (v) => num(Number(v), 0),
  sampled_on: (v) => shortDate(String(v)),
  avoid: (v) => (Array.isArray(v) ? v.join('; ') : String(v)),
};

function argOf(k: string, v: unknown): string | number {
  const f = NOTE_ARGS[k];
  if (f) return f(v);
  return typeof v === 'number' ? v : String(v);
}

/** note.<code> in the current language; a code this page has no key for keeps the board's English. */
function noteText(code: NoteCode, english: string | undefined): string {
  const args: Record<string, string | number> = { enterococci_per_100ml: 'na' };
  for (const [k, v] of Object.entries(code.args)) if (v !== null && v !== undefined) args[k] = argOf(k, v);
  const key = `note.${code.code}`;
  const out = t(key, args);
  return out === key ? (english ?? code.code) : out;
}

function notesOf(s: Shown): string[] {
  if (!s.note_codes?.length) return s.notes;
  return s.note_codes.map((c, i) => noteText(c, s.notes[i]));
}

export function cardHtml(board: Board, b: Beach, s: Shown | null): string {
  const head = s
    ? `<p class="headline"><span class="score ${band(s.score, b.water.unfit)}">${s.score}/100</span> ` +
      (s.best ? t('card.best_at', { h: `<b>${esc(s.h)}</b>` }) : t('card.at_best', { h: `<b>${esc(s.h)}</b>`, best: esc(b.best.hour), score: b.best.score })) +
      (isPast(board, s.h) ? ` <span class="past">${tx('card.past')}</span>` : '') +
      '</p>'
    : `<p class="headline past">${tx('tip.dark')}</p>`;
  const notes = s ? notesOf(s) : [];
  const why = notes.length ? `<ul>${notes.map((n) => `<li>${esc(n)}</li>`).join('')}</ul>` : tx('card.good');
  const points = b.water.points.map((p) => {
    const cls = p.condition === 'improper' ? 'water improper' : p.condition === 'proper' ? 'water proper' : 'water';
    const count = p.enterococci_per_100ml === null ? '' : `, ${tx('card.enterococci', { n: p.enterococci_per_100ml })}`;
    return `<li><span class="${cls}">${esc(p.point)} (${esc(p.location)}): ${esc(condLabel(p.condition))}</span>, ${esc(p.sampled_on)}${count}</li>`;
  });
  const water =
    `<span class="${b.water.unfit ? 'unfit' : 'water'}">${esc(waterSummary(b))}</span>` +
    (points.length ? `<ul>${points.join('')}</ul>` : '') +
    (b.water.source ? `<small>${t('card.source', { source: `<span class="src">${esc(b.water.source)}</span>` })}</small>` : '');
  const signed = new Intl.NumberFormat(locale(), { signDisplay: 'exceptZero', minimumFractionDigits: 1, maximumFractionDigits: 1 });
  const tides = b.tides.length
    ? `${b.tides.map((td) => tx(td.high ? 'tide.high' : 'tide.low', { time: td.time, m: signed.format(td.m) })).join(', ')} <small>${tx('tide.hourly')}</small>`
    : tx('tide.none');
  const sea = b.sea;
  const seaText = [
    fmt(sea.temp_c, '°C'),
    wavesText(sea.wave_m, sea.period_s),
    ...(sea.swell_m !== null ? [t('card.swell', { v: fmt(sea.swell_m, ' m') })] : []),
    ...(sea.current_kmh !== null ? [t('card.current', { v: fmt(sea.current_kmh, ' km/h') })] : []),
  ].join(', ');
  const air = [
    fmt(sea.air_temp_c, '°C', 0),
    t('cell.wind', { v: fmt(sea.wind_kmh, ' km/h', 0) }),
    ...(sea.uv !== null ? [t('card.uv', { v: fmt(sea.uv, '', 0) })] : []),
    ...(sea.rain_pct !== null ? [t('card.rain', { pct: num(sea.rain_pct, 0) })] : []),
  ].join(', ');
  const whales = t('card.whales_now', {
    level: word('lvl.', b.whales.now),
    best: yesNo(b.whales.peak !== null && b.whales.peak !== ''),
    peak: b.whales.peak ?? '',
    season: yesNo(b.whales.season),
  });
  const row = (key: string, html: string): string => `<dt>${tx(key)}</dt><dd>${html}</dd>`;
  return (
    `<button class="close" type="button" aria-label="${tx('card.close')}">×</button>` +
    `<h2>${esc(b.name)}</h2>` +
    `<div class="aspects">${aspectsHtml(b, s)}</div>${head}<dl>` +
    row('card.why', why) +
    row('card.water', water) +
    row('card.sea', `${esc(seaText)} <small>${tx('card.at', { h: b.best.hour })}</small>`) +
    row('card.tide', tides) +
    row('card.air', esc(air)) +
    row('card.jellyfish', esc(word('lvl.', b.jellyfish))) +
    row('card.whales', esc(whales)) +
    // Coordinates keep the dot in every language: a decimal comma would collide with the separator.
    row(
      'card.where',
      `<a href="https://www.openstreetmap.org/?mlat=${b.lat}&mlon=${b.lon}#map=15/${b.lat}/${b.lon}" target="_blank" rel="noopener">${b.lat.toFixed(4)}, ${b.lon.toFixed(4)}</a>`,
    ) +
    '</dl>'
  );
}

const REPO = 'https://github.com/marola-dev/marola';
const SOURCE_LINKS: Readonly<Record<string, string>> = {
  'OpenStreetMap/Overpass': 'https://www.openstreetmap.org/copyright',
  'Open-Meteo': 'https://open-meteo.com/',
  'IMA/SC': 'https://balneabilidade.ima.sc.gov.br/',
};

export function footerHtml(board: Board, areaName: string): string {
  const { beaches, forecast, water } = board.sources;
  const srcs = [beaches, forecast, water]
    .filter((s) => s !== null)
    .map((s) => {
      const href = SOURCE_LINKS[s.split(' ')[0] ?? ''];
      return `<span class="src">${href ? `<a href="${href}" target="_blank" rel="noopener">${esc(s)}</a>` : esc(s)}</span>`;
    })
    .join(' · ');
  const { lore } = board;
  const loreHtml = lore
    ? `<p class="lore">${lore.kind === 'creature' ? `${icon('fish')} ${tx('lore.creature')}` : `${icon('book')} ${tx('lore.fact')}`} ${esc(lore.text)}` +
      ` <a href="${esc(lore.source)}" target="_blank" rel="noopener">[${tx('lore.source')}]</a></p>`
    : '';
  const status = t('footer.generated', {
    when: esc(board.generated_at.replace('T', ' ').slice(0, 16)),
    area: esc(areaName),
    day: esc(board.day),
    n: board.beaches.length,
    sources: srcs,
  });
  return `<p id="status">${status}</p>${loreHtml}<p>${tx('footer.blurb')} <a href="${REPO}" target="_blank" rel="noopener">${tx('footer.github')}</a>.</p>`;
}
