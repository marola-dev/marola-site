/** NASA GIBS satellite layers: keyless public tiles, the page's second third-party origin. */
const GIBS = 'https://gibs.earthdata.nasa.gov/wmts/epsg3857/best/';

export interface Raster {
  layer: string;
  matrix: string;
  ext: 'jpg' | 'png';
  maxzoom: number;
  daysBack: number;
  opacity: number;
}

// daysBack: VIIRS is complete the next day; MUR SST is published with about a day's lag.
const anomaly: Raster = {
  layer: 'GHRSST_L4_MUR_Sea_Surface_Temperature_Anomalies',
  matrix: 'GoogleMapsCompatible_Level7',
  ext: 'png',
  maxzoom: 7,
  daysBack: 2,
  opacity: 0.85,
};
export const RASTERS: Readonly<Record<string, Raster>> = {
  clouds: {
    layer: 'VIIRS_SNPP_CorrectedReflectance_TrueColor',
    matrix: 'GoogleMapsCompatible_Level9',
    ext: 'jpg',
    maxzoom: 9,
    daysBack: 1,
    opacity: 1,
  },
  sst: { ...anomaly, layer: 'GHRSST_L4_MUR_Sea_Surface_Temperature' },
  anomaly,
  elnino: anomaly,
};

// Niño 3.4: 5°N–5°S, 170°W–120°W, where NOAA measures El Niño.
export const NINO34: [number, number][] = [
  [-170, -5],
  [-120, -5],
  [-120, 5],
  [-170, 5],
  [-170, -5],
];

/** Counted back from the day the board was made, not the forecast day: imagery for a future day does not exist. */
export function rasterDay(r: Raster, today: string): string {
  const d = new Date(`${today}T12:00:00Z`);
  d.setUTCDate(d.getUTCDate() - r.daysBack);
  return d.toISOString().slice(0, 10);
}

export const tileUrl = (r: Raster, today: string): string =>
  `${GIBS}${r.layer}/default/${rasterDay(r, today)}/${r.matrix}/{z}/{y}/{x}.${r.ext}`;
