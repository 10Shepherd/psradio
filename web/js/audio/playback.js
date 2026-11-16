/*
 * Receive side: one stream per incoming transmission. Packets are decoded,
 * queued on a small jitter buffer and played through a filter chain chosen by
 * the channel mode:
 *   digital  band-limited to roughly 250 Hz - 3.4 kHz
 *   analog   narrower band plus soft clipping
 */
(function () {
  'use strict';
  const A = (window.PSRAudio = window.PSRAudio || {});

  const JITTER = 0.12;        // seconds of audio buffered before playback starts
  const MAX_LATENCY = 1.0;    // packets that would play later than this are dropped
  const MAX_STREAMS = 4;

  function softClipCurve() {
    const n = 1024, curve = new Float32Array(n);
    for (let i = 0; i < n; i++) {
      const x = (i / (n - 1)) * 2 - 1;
      curve[i] = Math.tanh(2.5 * x) / Math.tanh(2.5);
    }
    return curve;
  }

  function Player() {
    this.streams = new Map();
    this.volume = 0.8;
    this.master = null;
  }

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

  Player.prototype.open = function (txId, codecId, mode) {
    if (this.streams.has(txId)) return;
    if (this.streams.size >= MAX_STREAMS) return;
    const audio = A.context();
    const self = this;
    const analog = mode === 'analog';

    const input = audio.createGain();
    const highpass = audio.createBiquadFilter();
    highpass.type = 'highpass';
    highpass.frequency.value = analog ? 300 : 250;
    const lowpass = audio.createBiquadFilter();
    lowpass.type = 'lowpass';
    lowpass.frequency.value = analog ? 2700 : 3400;
    input.connect(highpass);
    highpass.connect(lowpass);
    let tail = lowpass;
    if (analog) {
      const shaper = audio.createWaveShaper();
      shaper.curve = softClipCurve();
      lowpass.connect(shaper);
      tail = shaper;
    }
    tail.connect(this._master());

    const stream = { input: input, tail: tail, next: 0, decoder: null };
    try {
      stream.decoder = A.Codecs.createDecoder(codecId, function (samples, rate) {
        self._schedule(stream, samples, rate);
      });
    } catch (e) {
      console.error('[psradio] cannot decode codec', codecId, e);
      tail.disconnect();
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

  Player.prototype.close = function (txId) {
    const stream = this.streams.get(txId);
    if (!stream) return;
    this.streams.delete(txId);
    try { stream.decoder.close(); } catch (e) { /* already closed */ }
    // let queued audio finish before tearing the chain down
    const wait = Math.max(0, stream.next - A.context().currentTime) + 0.25;
    setTimeout(function () {
      try { stream.tail.disconnect(); } catch (e) { /* already gone */ }
    }, wait * 1000);
  };

  Player.prototype.closeAll = function () {
    const ids = Array.from(this.streams.keys());
    for (let i = 0; i < ids.length; i++) this.close(ids[i]);
  };

  A.Player = Player;
})();
