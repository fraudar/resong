// Motor Web Audio em tempo real para resong (Equalizador 5 bandas, Som 8D, Bass Boost, Reverb, Normalização e Mono).
(function () {
  if (typeof window === 'undefined' || typeof document === 'undefined') return;

  const BAND_FREQS = [60, 230, 910, 3600, 14000];
  const BAND_TYPES = ['lowshelf', 'peaking', 'peaking', 'peaking', 'highshelf'];
  const BAND_Q = [0.7, 1.2, 1.1, 1.2, 0.7];

  const defaultState = {
    enabled: false,
    bands: [0, 0, 0, 0, 0],
    bassBoost: 0,
    reverb: 0,
    spatial8d: false,
    rotationHz: 0.18,
    speed: 1.0,
    preservePitch: true,
    monoAudio: false,
    normalization: true,
    gapless: true,
  };

  let state = { ...defaultState };
  let ctx = null;
  let impulseBuffer = null;
  const audioElements = new Set();
  const graphs = new WeakMap();
  const corsFailedUrls = new Set();

  function createImpulseResponse(audioCtx, seconds = 1.7, decay = 2.6) {
    const rate = audioCtx.sampleRate;
    const length = Math.floor(rate * seconds);
    const buffer = audioCtx.createBuffer(2, length, rate);
    for (let ch = 0; ch < 2; ch++) {
      const data = buffer.getChannelData(ch);
      for (let i = 0; i < length; i++) {
        const env = Math.pow(1 - i / length, decay);
        // Suaviza ataque inicial em ~18ms para soar espacial sem eco áspero
        const fadeIn = Math.min(1, i / (rate * 0.018));
        data[i] = (Math.random() * 2 - 1) * env * fadeIn;
      }
    }
    return buffer;
  }

  function ensureContext() {
    const AudioCtx = window.AudioContext || window.webkitAudioContext;
    if (!AudioCtx) return null;
    if (!ctx) {
      ctx = new AudioCtx({ latencyHint: 'playback' });
    }
    if (ctx.state === 'suspended') {
      ctx.resume().catch(() => {});
    }
    return ctx;
  }

  function buildGraph(el) {
    if (graphs.has(el)) return graphs.get(el);
    const audioCtx = ensureContext();
    if (!audioCtx) return null;

    try {
      const source = audioCtx.createMediaElementSource(el);
      const inputGain = audioCtx.createGain();
      const bassFilter = audioCtx.createBiquadFilter();
      bassFilter.type = 'lowshelf';
      bassFilter.frequency.value = 85;
      bassFilter.gain.value = 0;

      const eqFilters = BAND_FREQS.map((freq, idx) => {
        const f = audioCtx.createBiquadFilter();
        f.type = BAND_TYPES[idx];
        f.frequency.value = freq;
        f.Q.value = BAND_Q[idx];
        f.gain.value = 0;
        return f;
      });

      // Estágio 8D: oscilador na thread de áudio dirige panner + leve filtro de profundidade
      const depthFilter = audioCtx.createBiquadFilter();
      depthFilter.type = 'lowpass';
      depthFilter.frequency.value = 20000;
      depthFilter.Q.value = 0.5;

      const panner = audioCtx.createStereoPanner
        ? audioCtx.createStereoPanner()
        : null;

      const lfo = audioCtx.createOscillator();
      lfo.type = 'sine';
      lfo.frequency.value = state.rotationHz || 0.18;

      const panDepthGain = audioCtx.createGain();
      panDepthGain.gain.value = 0;

      const depthLfo = audioCtx.createOscillator();
      depthLfo.type = 'triangle';
      depthLfo.frequency.value = state.rotationHz || 0.18;

      const depthModGain = audioCtx.createGain();
      depthModGain.gain.value = 0;

      if (panner) {
        lfo.connect(panDepthGain);
        panDepthGain.connect(panner.pan);
      }
      depthLfo.connect(depthModGain);
      depthModGain.connect(depthFilter.frequency);
      lfo.start();
      depthLfo.start();

      // Reverb paralelo com ConvolverNode
      const dryGain = audioCtx.createGain();
      const wetGain = audioCtx.createGain();
      wetGain.gain.value = 0;
      const convolver = audioCtx.createConvolver();
      if (!impulseBuffer) impulseBuffer = createImpulseResponse(audioCtx);
      convolver.buffer = impulseBuffer;

      // Compressor/Normalizador -14 LUFS + proteção contra clipping de EQ
      const compressor = audioCtx.createDynamicsCompressor();
      const makeupGain = audioCtx.createGain();
      const outputGain = audioCtx.createGain();

      source.connect(inputGain);
      inputGain.connect(bassFilter);
      let head = bassFilter;
      for (const f of eqFilters) {
        head.connect(f);
        head = f;
      }
      head.connect(depthFilter);
      const spatialTail = panner ? panner : depthFilter;
      if (panner) depthFilter.connect(panner);

      spatialTail.connect(dryGain);
      spatialTail.connect(convolver);
      convolver.connect(wetGain);

      dryGain.connect(compressor);
      wetGain.connect(compressor);
      compressor.connect(makeupGain);
      makeupGain.connect(outputGain);
      outputGain.connect(audioCtx.destination);

      const graph = {
        el,
        audioCtx,
        inputGain,
        bassFilter,
        eqFilters,
        depthFilter,
        panner,
        lfo,
        depthLfo,
        panDepthGain,
        depthModGain,
        dryGain,
        wetGain,
        compressor,
        makeupGain,
        outputGain,
      };
      graphs.set(el, graph);
      applyStateToGraph(graph);
      return graph;
    } catch (_) {
      return null;
    }
  }

  function applyStateToElement(el) {
    try {
      const pitch = state.preservePitch !== false;
      if ('preservesPitch' in el) el.preservesPitch = pitch;
      if ('webkitPreservesPitch' in el) el.webkitPreservesPitch = pitch;
      if ('mozPreservesPitch' in el) el.mozPreservesPitch = pitch;
      if (typeof state.speed === 'number' && state.speed > 0 && Math.abs(el.playbackRate - state.speed) > 0.001) {
        el.playbackRate = state.speed;
      }
    } catch (_) {}
  }

  function applyStateToGraph(g) {
    const now = g.audioCtx.currentTime;
    const active = Boolean(state.enabled);

    for (let i = 0; i < g.eqFilters.length; i++) {
      const targetGain = active ? Number(state.bands?.[i] ?? 0) : 0;
      g.eqFilters[i].gain.setTargetAtTime(Math.max(-12, Math.min(12, targetGain)), now, 0.03);
    }

    const bassDb = active ? Math.max(0, Math.min(1, Number(state.bassBoost ?? 0))) * 9.5 : 0;
    g.bassFilter.gain.setTargetAtTime(bassDb, now, 0.03);

    const is8d = active && Boolean(state.spatial8d);
    const hz = Math.max(0.05, Math.min(0.6, Number(state.rotationHz ?? 0.18)));
    g.lfo.frequency.setTargetAtTime(hz, now, 0.04);
    g.depthLfo.frequency.setTargetAtTime(hz, now, 0.04);
    g.panDepthGain.gain.setTargetAtTime(is8d ? 0.92 : 0, now, 0.06);
    g.depthFilter.frequency.setTargetAtTime(is8d ? 13500 : 20000, now, 0.06);
    g.depthModGain.gain.setTargetAtTime(is8d ? 5500 : 0, now, 0.06);

    const userRev = active ? Math.max(0, Math.min(1, Number(state.reverb ?? 0))) : 0;
    const effectiveRev = Math.min(1, userRev + (is8d && userRev < 0.22 ? 0.18 : 0));
    g.dryGain.gain.setTargetAtTime(1.0 - effectiveRev * 0.25, now, 0.04);
    g.wetGain.gain.setTargetAtTime(effectiveRev * 0.72, now, 0.04);

    // Normalização dinâmica (-14 LUFS) funciona mesmo com EQ desativado se o toggle normalization estiver ativo
    if (state.normalization) {
      g.compressor.threshold.setTargetAtTime(-22, now, 0.04);
      g.compressor.knee.setTargetAtTime(20, now, 0.04);
      g.compressor.ratio.setTargetAtTime(4.5, now, 0.04);
      g.compressor.attack.setTargetAtTime(0.004, now, 0.04);
      g.compressor.release.setTargetAtTime(0.22, now, 0.04);
      g.makeupGain.gain.setTargetAtTime(1.32, now, 0.04);
    } else {
      g.compressor.threshold.setTargetAtTime(-1.5, now, 0.04);
      g.compressor.knee.setTargetAtTime(6, now, 0.04);
      g.compressor.ratio.setTargetAtTime(12, now, 0.04);
      g.makeupGain.gain.setTargetAtTime(1.0, now, 0.04);
    }

    try {
      const mono = active && Boolean(state.monoAudio);
      g.outputGain.channelCount = mono ? 1 : Math.min(2, g.audioCtx.destination.maxChannelCount || 2);
      g.outputGain.channelCountMode = mono ? 'explicit' : 'max';
    } catch (_) {}
  }

  function needsGraph() {
    if (state.normalization) return true;
    if (!state.enabled) return false;
    if (state.spatial8d || state.monoAudio) return true;
    if (Number(state.bassBoost || 0) > 0.01 || Number(state.reverb || 0) > 0.01) return true;
    return Array.isArray(state.bands) && state.bands.some((b) => Math.abs(Number(b || 0)) > 0.05);
  }

  function applyAll() {
    for (const el of audioElements) {
      applyStateToElement(el);
      const existing = graphs.get(el);
      if (existing) {
        applyStateToGraph(existing);
      } else if (needsGraph() && !el.paused) {
        buildGraph(el);
      }
    }
  }

  function hookAudioElement(el) {
    if (audioElements.has(el)) return el;
    audioElements.add(el);

    const srcDesc = Object.getOwnPropertyDescriptor(HTMLMediaElement.prototype, 'src');
    if (srcDesc && srcDesc.get && srcDesc.set) {
      Object.defineProperty(el, 'src', {
        configurable: true,
        enumerable: true,
        get() {
          return srcDesc.get.call(this);
        },
        set(val) {
          const url = typeof val === 'string' ? val : String(val || '');
          const isLocalProxy = url.includes('/api/stream/');
          if (url && (isLocalProxy || !corsFailedUrls.has(url))) {
            this.crossOrigin = 'anonymous';
          } else {
            this.removeAttribute('crossorigin');
          }
          srcDesc.set.call(this, val);
          applyStateToElement(this);
        },
      });
    }

    el.addEventListener('error', () => {
      // Apenas registra falha CORS para uma próxima tentativa iniciada pelo Dart;
      // nunca chama el.load() aqui para evitar race com just_audio_web ou recarga de src antigo.
      const curSrc = el.currentSrc || el.src;
      if (curSrc && !curSrc.includes('/api/stream/') && el.getAttribute('crossorigin')) {
        corsFailedUrls.add(curSrc);
        el.removeAttribute('crossorigin');
      }
    });

    el.addEventListener('play', () => {
      ensureContext();
      applyStateToElement(el);
      if (!graphs.has(el) && !el.getAttribute('crossorigin')) {
        // Sem crossOrigin não anexa MediaElementAudioSource para evitar silêncio por CORS
        return;
      }
      if (needsGraph() || graphs.has(el)) {
        const g = buildGraph(el);
        if (g) applyStateToGraph(g);
      }
    });

    el.addEventListener('canplaythrough', () => {
      applyStateToElement(el);
    });

    return el;
  }

  const origCreateElement = document.createElement.bind(document);
  document.createElement = function (tagName, options) {
    const el = origCreateElement(tagName, options);
    if (typeof tagName === 'string' && tagName.toLowerCase() === 'audio') {
      hookAudioElement(el);
    }
    return el;
  };

  window.addEventListener(
    'pointerdown',
    () => {
      if (ctx && ctx.state === 'suspended') {
        ctx.resume().catch(() => {});
      }
    },
    { passive: true },
  );

  const prewarmedUrls = new Set();
  window.__resongAudioFx = {
    apply(jsonOrObj) {
      try {
        const next = typeof jsonOrObj === 'string' ? JSON.parse(jsonOrObj) : jsonOrObj;
        state = { ...defaultState, ...next };
        applyAll();
      } catch (_) {}
    },
    resume() {
      ensureContext();
    },
    prewarm(url) {
      if (!url || !state.gapless || prewarmedUrls.has(url)) return;
      prewarmedUrls.add(url);
      if (prewarmedUrls.size > 20) {
        const first = prewarmedUrls.values().next().value;
        prewarmedUrls.delete(first);
      }
      fetch(url, {
        headers: { Range: 'bytes=0-131071' },
        mode: 'cors',
      }).catch(() => {});
    },
    getState() {
      return { ...state };
    },
  };
})();
