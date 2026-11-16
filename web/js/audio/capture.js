/*
 * Microphone capture. The microphone is opened on the first transmission
 * (never before), then kept but muted between transmissions so later PTT
 * presses start instantly. release() closes it completely.
 */
(function () {
  'use strict';
  const A = (window.PSRAudio = window.PSRAudio || {});
  const FRAME = 960;

  let ctx = null;
  A.context = function () {
    if (!ctx) {
      const Ctor = window.AudioContext || window.webkitAudioContext;
      ctx = new Ctor({ sampleRate: 48000, latencyHint: 'interactive' });
    }
    if (ctx.state === 'suspended') ctx.resume().catch(function () {});
    return ctx;
  };

  function Capture() {
    this.stream = null;
    this.node = null;
    this.onFrame = null;
    this.frame = new Float32Array(FRAME);
    this.fill = 0;
  }

  // Resolves once audio is flowing; rejects when the microphone is refused
  // or missing (the caller shows "Mic unavailable").
  Capture.prototype.start = async function (onFrame) {
    if (!this.stream) {
      this.stream = await navigator.mediaDevices.getUserMedia({
        audio: { channelCount: 1, echoCancellation: true, noiseSuppression: true, autoGainControl: true },
        video: false,
      });
    }
    if (!this.node) await this._build();
    this.stream.getAudioTracks().forEach(function (t) { t.enabled = true; });
    this.fill = 0;
    this.onFrame = onFrame;
  };

  Capture.prototype.pause = function () {
    this.onFrame = null;
    if (this.stream) this.stream.getAudioTracks().forEach(function (t) { t.enabled = false; });
  };

  Capture.prototype.release = function () {
    this.onFrame = null;
    if (this.node) {
      try { this.source.disconnect(); this.node.disconnect(); this.sink.disconnect(); } catch (e) { /* already gone */ }
      this.node = null;
    }
    if (this.stream) {
      this.stream.getTracks().forEach(function (t) { t.stop(); });
      this.stream = null;
    }
  };

  Capture.prototype._build = async function () {
    const audio = A.context();
    const self = this;
    this.source = audio.createMediaStreamSource(this.stream);
    // Processing nodes only run when connected to the output; a zero gain
    // keeps the player's own voice out of their speakers.
    this.sink = audio.createGain();
    this.sink.gain.value = 0;
    this.sink.connect(audio.destination);

    try {
      await audio.audioWorklet.addModule('js/audio/capture-worklet.js');
      this.node = new AudioWorkletNode(audio, 'psr-capture');
      this.node.port.onmessage = function (e) {
        if (self.onFrame) self.onFrame(e.data);
      };
    } catch (e) {
      // Older Chromium: fall back to the main-thread processor.
      this.node = audio.createScriptProcessor(2048, 1, 1);
      this.node.onaudioprocess = function (ev) { self._push(ev.inputBuffer.getChannelData(0)); };
    }
    this.source.connect(this.node);
    this.node.connect(this.sink);
  };

  Capture.prototype._push = function (chunk) {
    if (!this.onFrame) return;
    let i = 0;
    while (i < chunk.length) {
      const n = Math.min(chunk.length - i, FRAME - this.fill);
      this.frame.set(chunk.subarray(i, i + n), this.fill);
      this.fill += n;
      i += n;
      if (this.fill === FRAME) {
        this.onFrame(this.frame.slice(0));
        this.fill = 0;
      }
    }
  };

  A.Capture = Capture;
})();
