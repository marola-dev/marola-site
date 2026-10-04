// What the page's plain-JS siblings put on window: vendor/mapbox-gl-csp.js, and the two config files the deploy rewrites.

// The slice of Mapbox GL JS 3 this page calls. The mapbox-gl npm package (67 MB) would only bring these types.
declare namespace mapboxgl {
  type LngLatLike = [number, number];
  type Bounds = [LngLatLike, LngLatLike];

  interface Layer {
    id: string;
    type: string;
    [key: string]: unknown;
  }
  interface CustomLayer {
    id: string;
    type: 'custom';
    renderingMode?: '2d' | '3d';
    onAdd?(map: Map, gl: WebGLRenderingContext): void;
    onRemove?(map: Map, gl: WebGLRenderingContext): void;
    render(gl: WebGLRenderingContext, matrix: number[]): void;
  }
  interface GeoJSONSource {
    setData(data: unknown): void;
  }
  interface MapEvent {
    originalEvent?: Event;
    lngLat: LngLatLike;
    features?: { properties: Record<string, string> }[];
    error?: { status?: number };
  }
  interface FitOptions {
    padding?: number;
    duration?: number;
    maxZoom?: number;
  }

  interface Map {
    touchZoomRotate: { disableRotation(): void };
    on(type: string, listener: (e: MapEvent) => void): this;
    on(type: string, layerId: string, listener: (e: MapEvent) => void): this;
    addControl(control: object, position?: string): this;
    jumpTo(options: { center: LngLatLike; zoom: number }): this;
    fitBounds(bounds: Bounds, options?: FitOptions): this;
    panTo(center: LngLatLike): this;
    setMinZoom(zoom: number): this;
    getZoom(): number;
    getBounds(): { getWest(): number; getEast(): number; getNorth(): number; getSouth(): number };
    resize(): this;
    getStyle(): { layers?: Layer[] } | undefined;
    addSource(id: string, source: Record<string, unknown>): void;
    getSource(id: string): GeoJSONSource | undefined;
    removeSource(id: string): void;
    addLayer(layer: Layer | CustomLayer, before?: string): void;
    getLayer(id: string): Layer | undefined;
    removeLayer(id: string): void;
    setLayoutProperty(id: string, name: string, value: unknown): void;
    getCanvas(): HTMLCanvasElement;
    triggerRepaint(): void;
  }
  interface Marker {
    setLngLat(lngLat: LngLatLike): this;
    addTo(map: Map): this;
    remove(): this;
  }
  interface Popup {
    setLngLat(lngLat: LngLatLike): this;
    setHTML(html: string): this;
    addTo(map: Map): this;
    remove(): this;
  }
  interface Api {
    Map: new (options: Record<string, unknown>) => Map;
    Marker: new (options: { element: HTMLElement; anchor?: string }) => Marker;
    Popup: new (options?: Record<string, unknown>) => Popup;
    NavigationControl: new (options?: { showCompass?: boolean }) => object;
    accessToken: string;
    workerUrl: string;
    readonly version: string;
  }
}

interface Window {
  mapboxgl?: mapboxgl.Api;
  MAROLA_MAPBOX?: { token?: string; style?: string };
  MAROLA_CHAT_ENDPOINT?: string;
}
