/*
 * Receive side: one stream per incoming transmission. Packets are decoded,
 * queued on a small jitter buffer and played through a filter chain built from
 * the server's Config.audio:
 *
 *   decoded audio -> highpass -> lowpass -> [drive -> soft clip -> makeup] -> out
 *   noise floor   -> bandpass -> gain ----------------------------------------^
 *
 * The clipper and the noise floor are what make an analog channel sound
 * different from a digital one. The player's `fx` setting scales both:
 * full = as configured, light = half, off = band limiting only.
 */
(function () {
  'use strict';
  const A = (window.PSRAudio = window.PSRAudio || {});

  const JITTER = 0.12;        // seconds of audio buffered before playback starts
  const MAX_LATENCY = 1.0;    // packets that would play later than this are dropped
  const MAX_STREAMS = 4;

  // Used until the server's audio config arrives, and as the shape of it.
  const FALLBACK = {
    digital: { high: 250, low: 3400, drive: 1, makeup: 1, noise: 0, tailMs: 0 },
    analog: { high: 380, low: 2400, drive: 1.6, makeup: 0.8, noise: 0.06, tailMs: 110 },
  };

  const FX_SCALE = { full: 1, light: 0.5, off: 0 };

  function softClipCurve() {
    const n = 1024, curve = new Float32Array(n);
    const norm = Math.tanh(2.5);
    for (let i = 0; i < n; i++) {
      const x = (i / (n - 1)) * 2 - 1;
      curve[i] = Math.tanh(2.5 * x) / norm;
    }
    return curve;
  }

  function Player() {
    this.streams = new Map();
    this.volume = 0.8;
    this.master = null;
    this.config = FALLBACK;
    this.fx = 1;
    this.noiseBuffer = null;
  }

  // Server audio config, and the player's fx setting. Takes effect on the next
  // transmission; a stream already playing keeps the chain it was built with.
  Player.prototype.configure = function (config, fxMode) {
    if (config && config.digital && config.analog) this.config = config;
    const scale = FX_SCALE[fxMode];
    this.fx = scale === undefined ? 1 : scale;
  };

  // The numbers for one mode after the player's fx setting is applied.
  Player.prototype._chain = function (mode) {
    const base = (mode === 'analog' ? this.config.analog : this.config.digital) || FALLBACK.digital;
    const fx = this.fx;
    return {
      high: base.high, low: base.low,
      // fx only scales how far past clean the effect goes
      drive: 1 + (Math.max(1, base.drive || 1) - 1) * fx,
      makeup: 1 + ((base.makeup === undefined ? 1 : base.makeup) - 1) * fx,
      noise: (base.noise || 0) * fx,
      tailMs: (base.tailMs || 0) * fx,
    };
  };

  Player.prototype._master = function () {
    if (!this.master) {
      const audio = A.context();
      this.master = audio.createGain();
      this.master.gain.value = this.volume;
      this.master.connect(audio.destination);
    }
    return this.master;
  };

  Player.prototype.setVolume = function (v) {
    this.volume = Math.max(0, Math.min(1, v));
    if (this.master) this.master.gain.value = this.volume;
  };

  Player.prototype._noise = function () {
    const audio = A.context();
    if (this.noiseBuffer && this.noiseBuffer.sampleRate === audio.sampleRate) return this.noiseBuffer;
    const buffer = audio.createBuffer(1, Math.floor(audio.sampleRate), audio.sampleRate);
    const data = buffer.getChannelData(0);
    for (let i = 0; i < data.length; i++) data[i] = Math.random() * 2 - 1;
    this.noiseBuffer = buffer;
    return buffer;
  };

  // A looping noise source through the channel's band, used for the carrier
  // hiss and for the squelch tail.
  Player.prototype._openNoise = function (chain, level) {
    const audio = A.context();
    const source = audio.createBufferSource();
    source.buffer = this._noise();
    source.loop = true;
    const band = audio.createBiquadFilter();
    band.type = 'bandpass';
    band.frequency.value = Math.sqrt(chain.high * chain.low);
    band.Q.value = 0.6;
    const gain = audio.createGain();
    gain.gain.value = level;
    source.connect(band);
    band.connect(gain);
    gain.connect(this._master());
    source.start();
    return { source: source, gain: gain };
  };

  Player.prototype.open = function (txId, codecId, mode) {
    if (this.streams.has(txId)) return;
    if (this.streams.size >= MAX_STREAMS) return;
    const audio = A.context();
    const self = this;
    const chain = this._chain(mode);

    const input = audio.createGain();
    const highpass = audio.createBiquadFilter();
    highpass.type = 'highpass';
    highpass.frequency.value = chain.high;
    const lowpass = audio.createBiquadFilter();
    lowpass.type = 'lowpass';
    lowpass.frequency.value = chain.low;
    input.connect(highpass);
    highpass.connect(lowpass);

    let tail = lowpass;
    if (chain.drive > 1.01) {
      // the pre-gain is what the clipper hears, so it sets how much it bites
      const drive = audio.createGain();
      drive.gain.value = chain.drive;
      const shaper = audio.createWaveShaper();
      shaper.curve = softClipCurve();
      shaper.oversample = '2x';   // keeps the harder clipping from aliasing
      const makeup = audio.createGain();
      makeup.gain.value = chain.makeup;
      lowpass.connect(drive);
      drive.connect(shaper);
      shaper.connect(makeup);
      tail = makeup;
    }
    tail.connect(this._master());

    const stream = { input: input, tail: tail, next: 0, decoder: null, chain: chain, noise: null };
    if (chain.noise > 0.001) stream.noise = this._openNoise(chain, chain.noise);

    try {
      stream.decoder = A.Codecs.createDecoder(codecId, function (samples, rate) {
        self._schedule(stream, samples, rate);
      });
    } catch (e) {
      console.error('[psradio] cannot decode codec', codecId, e);
      tail.disconnect();
      if (stream.noise) {
        try { stream.noise.source.stop(); } catch (stopError) { /* never started */ }
      }
      return;
    }
    this.streams.set(txId, stream);
  };

  Player.prototype.push = function (txId, base64) {
    const stream = this.streams.get(txId);
    if (!stream) return;
    try {
      const packets = A.Codecs.unpack(A.Codecs.fromBase64(base64));
      for (let i = 0; i < packets.length; i++) stream.decoder.decode(packets[i]);
    } catch (e) {
      /* a malformed packet from another player is simply skipped */
    }
  };

  Player.prototype._schedule = function (stream, samples, rate) {
    if (!samples.length || rate < 8000 || rate > 96000) return;
    const audio = A.context();
    const now = audio.currentTime;
    if (stream.next < now) stream.next = now + JITTER;       // first packet or underrun
    if (stream.next - now > MAX_LATENCY) return;
    const buffer = audio.createBuffer(1, samples.length, rate);
    buffer.copyToChannel(samples, 0);
    const source = audio.createBufferSource();
    source.buffer = buffer;
    source.connect(stream.input);
    source.start(stream.next);
    stream.next += buffer.duration;
  };

  // The squelch tail: a short burst of noise as the carrier drops, which is
  // what a real receiver does when the other radio stops transmitting.
  Player.prototype._tail = function (chain, startAt) {
    const audio = A.context();
    const dur = chain.tailMs / 1000;
    if (dur <= 0.005) return;
    const burst = this._openNoise(chain, 0);
    const at = Math.max(audio.currentTime, startAt);
    const level = Math.max(chain.noise, 0.05);
    burst.gain.gain.setValueAtTime(level, at);
    burst.gain.gain.linearRampToValueAtTime(0, at + dur);
    burst.source.stop(at + dur + 0.02);
  };

  Player.prototype.close = function (txId) {
    const stream = this.streams.get(txId);
    if (!stream) return;
    this.streams.delete(txId);
    try { stream.decoder.close(); } catch (e) { /* already closed */ }

    const audio = A.context();
    const endsAt = Math.max(audio.currentTime, stream.next);
    if (stream.noise) {
      // fade the carrier hiss out with the audio, then hand over to the tail
      try {
        stream.noise.gain.gain.setValueAtTime(stream.chain.noise, endsAt);
        stream.noise.gain.gain.linearRampToValueAtTime(0, endsAt + 0.02);
        stream.noise.source.stop(endsAt + 0.05);
      } catch (e) { /* context already gone */ }
    }
    this._tail(stream.chain, endsAt);

    // let queued audio finish before tearing the chain down
    const wait = endsAt - audio.currentTime + stream.chain.tailMs / 1000 + 0.25;
    setTimeout(function () {
      try { stream.tail.disconnect(); } catch (e) { /* already gone */ }
    }, Math.max(0, wait) * 1000);
  };

  Player.prototype.closeAll = function () {
    const ids = Array.from(this.streams.keys());
    for (let i = 0; i < ids.length; i++) this.close(ids[i]);
  };

  A.Player = Player;
})();
