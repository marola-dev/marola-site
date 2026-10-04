/** The ambient wave sound: a recorded loop (vendor/sounds/LICENSE.waves), fetched on first use. */
const URL_ = 'vendor/sounds/waves.mp3';
const LEVEL = 0.6;
const SILENT = 0.0001;
const PAD_S = 0.05; // the MP3 encoder's padding at both ends, which would click at every loop

type AudioCtor = new () => AudioContext;

export function waveSound(button: HTMLElement): void {
  let ctx: AudioContext | null = null;
  let gain: GainNode | null = null;
  let on = false;

  const press = (v: boolean): void => {
    on = v;
    button.setAttribute('aria-pressed', String(v));
  };

  async function load(c: AudioContext, out: GainNode): Promise<void> {
    try {
      const r = await fetch(URL_);
      if (!r.ok) throw new Error(`${r.status} ${URL_}`);
      const bytes = await r.arrayBuffer();
      // the callback form: Safari before 14.1 has no promise-returning decodeAudioData
      const audio = await new Promise<AudioBuffer>((resolve, reject) => {
        void c.decodeAudioData(bytes, resolve, reject);
      });
      const src = c.createBufferSource();
      src.buffer = audio;
      src.loop = true;
      src.loopStart = PAD_S;
      src.loopEnd = audio.duration - PAD_S;
      src.connect(out);
      src.start(0, PAD_S);
    } catch (e) {
      console.error(e);
      // the next click tries again from scratch
      press(false);
      void c.close();
      if (ctx === c) ctx = gain = null;
    }
  }

  button.addEventListener('click', () => {
    try {
      if (!ctx || !gain) {
        const w = window as Window & { AudioContext?: AudioCtor; webkitAudioContext?: AudioCtor };
        const Ctx = w.AudioContext ?? w.webkitAudioContext;
        if (!Ctx) return;
        ctx = new Ctx();
        gain = ctx.createGain();
        gain.gain.value = SILENT;
        gain.connect(ctx.destination);
        void load(ctx, gain);
      }
      if (ctx.state === 'suspended') void ctx.resume();
      press(!on);
      const now = ctx.currentTime;
      gain.gain.cancelScheduledValues(now);
      gain.gain.setTargetAtTime(on ? LEVEL : SILENT, now, 0.5);
    } catch (e) {
      console.error(e);
    }
  });
}
