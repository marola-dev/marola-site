/** The board the app image writes (site/board.schema.json), and the pure reads the page makes of it. */
export type Likelihood = 'Low' | 'Moderate' | 'High';

export interface NoteCode {
  code: string;
  args: Readonly<Record<string, unknown>>;
}

export interface Hour {
  h: string;
  score: number;
  notes: string[];
  note_codes?: NoteCode[];
  sea_temp_c: number | null;
  wave_m: number | null;
  wind_kmh: number | null;
  wind_level?: string | null;
  jellyfish: Likelihood;
  whales: Likelihood;
}

export interface WaterPoint {
  point: string;
  location: string;
  lat: number;
  lon: number;
  condition: 'proper' | 'improper' | 'unknown';
  sampled_on: string;
  enterococci_per_100ml: number | null;
  rain: string | null;
}

export interface Facilities {
  parking?: number;
  toilets?: number;
  shower?: number;
  lifeguard?: number;
}

export interface Sea {
  temp_c: number | null;
  wave_m: number | null;
  period_s: number | null;
  wave_dir_deg: number | null;
  swell_m: number | null;
  swell_period_s: number | null;
  current_kmh: number | null;
  wind_kmh: number | null;
  wind_dir_deg: number | null;
  air_temp_c: number | null;
  uv: number | null;
  rain_pct: number | null;
}

export interface Beach {
  name: string;
  lat: number;
  lon: number;
  best: { hour: string; score: number; notes: string[]; note_codes?: NoteCode[] };
  hours: Hour[];
  facilities?: Facilities;
  water: { summary: string; unfit: boolean; note: string | null; source: string | null; points: WaterPoint[] };
  tides: { time: string; m: number; high: boolean }[];
  sea: Sea;
  jellyfish: Likelihood;
  whales: { now: Likelihood; peak: string | null; season: boolean };
}

export interface Trail {
  name: string;
  length_km: number;
  difficulty: string | null;
  geometry: [number, number][]; // [lat, lon]
}

export interface Board {
  schema: number;
  area: string;
  day: string;
  today: string;
  generated_at: string;
  sources: { beaches: string; forecast: string; water: string | null };
  lore: { kind: 'secret' | 'creature'; text: string; source: string; lang: string } | null;
  beaches: Beach[];
  trails?: Trail[];
}

export interface Area {
  id: string;
  name: string;
  lat: number;
  lon: number;
}

export interface Latest {
  days: { day: string; file: string }[];
}

/** What a beach shows at the slider's position: its best hour (best: true) or one hour of hours[]. */
export interface Shown {
  h: string;
  score: number;
  notes: string[];
  note_codes?: NoteCode[] | undefined;
  best?: boolean;
}

// 2 adds note_codes (MIP-0054 task 3); anything else is a board newer than this page.
export const SCHEMAS = [1, 2];

/** hour null = each beach at its own best hour; null back = the beach is dark at that hour. */
export function shown(beach: Beach, hour: string | null): Shown | null {
  const b = beach.best;
  if (hour === null) return { h: b.hour, score: b.score, notes: b.notes, note_codes: b.note_codes, best: true };
  return beach.hours.find((x) => x.h === hour) ?? null;
}

export const hourEntry = (beach: Beach, s: Shown | null): Hour | null => (s ? (beach.hours.find((x) => x.h === s.h) ?? null) : null);

/** The slider's stops. */
export const hoursOf = (board: Board): string[] => [...new Set(board.beaches.flatMap((b) => b.hours.map((h) => h.h)))].sort();

export function isPast(board: Board, h: string): boolean {
  return board.day === board.today && h < board.generated_at.slice(11, 16);
}

export function haversineKm(a: { lat: number; lon: number }, b: { lat: number; lon: number }): number {
  const rad = Math.PI / 180;
  const dLat = (b.lat - a.lat) * rad;
  const dLon = (b.lon - a.lon) * rad;
  const h = Math.sin(dLat / 2) ** 2 + Math.cos(a.lat * rad) * Math.cos(b.lat * rad) * Math.sin(dLon / 2) ** 2;
  return 2 * 6371 * Math.asin(Math.sqrt(h));
}

/** Nearest first when here is known, else best score first; a dark beach goes last. */
export function ranked(
  beaches: readonly Beach[],
  score: (b: Beach) => number | null,
  here: { lat: number; lon: number } | null,
): { beach: Beach; km: number | null }[] {
  const rows = beaches.map((beach) => ({ beach, km: here ? haversineKm(here, beach) : null, score: score(beach) ?? -1 }));
  return rows.sort(here ? (a, b) => (a.km ?? 0) - (b.km ?? 0) : (a, b) => b.score - a.score);
}

export type Band = 'c70' | 'c40' | 'c1' | 'c0' | 'cna';

/** The score's colour band, the class style.css paints (.c70 … .cna) and the --c* token a marker fills with. */
export function band(score: number | null | undefined, unfit = false): Band {
  if (score === null || score === undefined) return 'cna';
  if (unfit || score <= 0) return 'c0';
  if (score >= 70) return 'c70';
  if (score >= 40) return 'c40';
  return 'c1';
}

export const waterBand = (condition: WaterPoint['condition']): Band =>
  condition === 'improper' ? 'c0' : condition === 'proper' ? 'c70' : 'cna';

// 'no data' is the one summary the board writes in words rather than the agency's verdict.
export const noWaterData = (beach: Beach): boolean => beach.water.summary === 'no data';

// The picker shows a two-letter code; areas.json is shared with the app, so the codes live here.
const AREA_CODES: Readonly<Record<string, string>> = { floripa: 'FL', rio: 'RJ', salvador: 'BA' };
export const areaCode = (a: Area): string =>
  AREA_CODES[a.id] ?? a.name.normalize('NFD').replace(/[^A-Za-z]/g, '').slice(0, 2).toUpperCase();
