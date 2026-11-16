/*
 * Codec abstraction for psradio voice.
 *
 * Every codec takes 20 ms frames of mono 48 kHz float audio (960 samples) and
 * produces one self-contained packet per frame. To add a codec, add an id in
 * shared/protocol.lua (PSR.Codec) and a matching entry in `registry` below.
 *
 *   id 1  opus   WebCodecs Opus (the browser's own encoder). Wideband.
 *   id 2  adpcm  IMA ADPCM, 8 kHz, 4 bits per sample = 32 kbit/s. Pure
 *                JavaScript, always available, narrowband "radio" sound.
 *
 * Not included: IMBE / AMBE (no vetted redistributable implementation is
 * bundled, so none is claimed) and Codec 2 (would need a WebAssembly build).
 *
 * This file also runs under Node for the offline unit tests.
 */
(function (root) {
  'use strict';

  const RATE = 48000;
  const FRAME = 960;                 // 20 ms at 48 kHz
  const ID = { opus: 1, adpcm: 2 };

  // ------------------------------------------------------------ packet framing
  // A network packet is a sequence of [uint16 big-endian length][bytes] records.
  function pack(packets) {
    let size = 0;
    for (const p of packets) size += 2 + p.length;
    const out = new Uint8Array(size);
    let o = 0;
    for (const p of packets) {
      out[o] = p.length >> 8;
      out[o + 1] = p.length & 255;
      out.set(p, o + 2);
      o += 2 + p.length;
    }
    return out;
  }

  // Input comes from another player, so it is treated as hostile: bounds are
  // checked and a malformed tail is ignored.
  function unpack(bytes, maxPackets) {
    const out = [];
    const limit = maxPackets || 8;
    let o = 0;
    while (o + 2 <= bytes.length && out.length < limit) {
      const len = (bytes[o] << 8) | bytes[o + 1];
      o += 2;
      if (len === 0 || o + len > bytes.length) break;
      out.push(bytes.subarray(o, o + len));
      o += len;
    }
    return out;
  }

  function toBase64(u8) {
    let s = '';
    for (let i = 0; i < u8.length; i++) s += String.fromCharCode(u8[i]);
    return btoa(s);
  }

  function fromBase64(str) {
    const s = atob(str);
    const out = new Uint8Array(s.length);
    for (let i = 0; i < s.length; i++) out[i] = s.charCodeAt(i);
    return out;
  }

  // ------------------------------------------------------------ IMA ADPCM
  const STEP = [
    7, 8, 9, 10, 11, 12, 13, 14, 16, 17, 19, 21, 23, 25, 28, 31, 34, 37, 41, 45, 50, 55, 60, 66,
    73, 80, 88, 97, 107, 118, 130, 143, 157, 173, 190, 209, 230, 253, 279, 307, 337, 371, 408,
    449, 494, 544, 598, 658, 724, 796, 876, 963, 1060, 1166, 1282, 1411, 1552, 1707, 1878, 2066,
    2272, 2499, 2749, 3024, 3327, 3660, 4026, 4428, 4871, 5358, 5894, 6484, 7132, 7845, 8630,
    9493, 10442, 11487, 12635, 13899, 15289, 16818, 18500, 20350, 22385, 24623, 27086, 29794, 32767,
  ];
  const INDEX_ADJUST = [-1, -1, -1, -1, 2, 4, 6, 8];
  const ADPCM_RATE = 8000;
  const DECIMATE = RATE / ADPCM_RATE;          // 6
  const ADPCM_SAMPLES = FRAME / DECIMATE;      // 160 per 20 ms
  const ADPCM_HEADER = 3;                      // predictor (int16 BE) + step index
  const ADPCM_PACKET = ADPCM_HEADER + ADPCM_SAMPLES / 2;

  // Low-pass before dropping to 8 kHz: windowed-sinc FIR, cut-off 3.4 kHz.
  const TAPS = (function () {
    const n = 49, fc = 3400 / RATE, taps = new Float32Array(n);
    let sum = 0;
    for (let i = 0; i < n; i++) {
      const m = i - (n - 1) / 2;
      const sinc = m === 0 ? 2 * fc : Math.sin(2 * Math.PI * fc * m) / (Math.PI * m);
      taps[i] = sinc * (0.54 - 0.46 * Math.cos((2 * Math.PI * i) / (n - 1)));
      sum += taps[i];
    }
    for (let i = 0; i < n; i++) taps[i] /= sum;
    return taps;
  })();

  function adpcmStep(state, code) {
    const step = STEP[state.index];
    let delta = step >> 3;
    if (code & 4) delta += step;
    if (code & 2) delta += step >> 1;
    if (code & 1) delta += step >> 2;
    state.pred += code & 8 ? -delta : delta;
    if (state.pred > 32767) state.pred = 32767;
    else if (state.pred < -32768) state.pred = -32768;
    state.index += INDEX_ADJUST[code & 7];
    if (state.index < 0) state.index = 0;
    else if (state.index > 88) state.index = 88;
  }

  function AdpcmEncoder(onPacket) {
    const state = { pred: 0, index: 0 };
    const hist = new Float32Array(TAPS.length - 1 + FRAME);

    this.encode = function (frame) {
      if (frame.length !== FRAME) return;
      hist.set(frame, TAPS.length - 1);
      const out = new Uint8Array(ADPCM_PACKET);
      out[0] = (state.pred >> 8) & 255;
      out[1] = state.pred & 255;
      out[2] = state.index;
      for (let k = 0; k < ADPCM_SAMPLES; k++) {
        let acc = 0;
        const base = k * DECIMATE;
        for (let j = 0; j < TAPS.length; j++) acc += hist[base + j] * TAPS[j];
        let sample = Math.round(acc * 32767);
        if (sample > 32767) sample = 32767;
        else if (sample < -32768) sample = -32768;

        let diff = sample - state.pred;
        let code = 0;
        if (diff < 0) { code = 8; diff = -diff; }
        let step = STEP[state.index];
        if (diff >= step) { code |= 4; diff -= step; }
        step >>= 1;
        if (diff >= step) { code |= 2; diff -= step; }
        step >>= 1;
        if (diff >= step) code |= 1;
        adpcmStep(state, code);

        if (k & 1) out[ADPCM_HEADER + (k >> 1)] |= code << 4;
        else out[ADPCM_HEADER + (k >> 1)] = code;
      }
      // keep the filter tail for the next frame
      hist.copyWithin(0, FRAME, FRAME + TAPS.length - 1);
      onPacket(out);
    };
    this.close = function () {};
  }

  function AdpcmDecoder(onAudio) {
    this.decode = function (packet) {
      if (packet.length !== ADPCM_PACKET || packet[2] > 88) return;
      const pred = (packet[0] << 8) | packet[1];
      const state = { pred: pred > 32767 ? pred - 65536 : pred, index: packet[2] };
      const out = new Float32Array(ADPCM_SAMPLES);
      for (let k = 0; k < ADPCM_SAMPLES; k++) {
        const byte = packet[ADPCM_HEADER + (k >> 1)];
        adpcmStep(state, k & 1 ? byte >> 4 : byte & 15);
        out[k] = state.pred / 32768;
      }
      onAudio(out, ADPCM_RATE);
    };
    this.close = function () {};
  }

  // ------------------------------------------------------------ Opus (WebCodecs)
  function opusConfig(bitrate) {
    return { codec: 'opus', sampleRate: RATE, numberOfChannels: 1, bitrate: bitrate || 16000 };
  }

  function OpusEncoder(opts, onPacket) {
    let timestamp = 0;
    const enc = new AudioEncoder({
      output: function (chunk) {
        const bytes = new Uint8Array(chunk.byteLength);
        chunk.copyTo(bytes);
        onPacket(bytes);
      },
      error: function (e) { console.error('[psradio] opus encoder', e); },
    });
    enc.configure(opusConfig(opts && opts.bitrate));

    this.encode = function (frame) {
      if (enc.state !== 'configured' || frame.length !== FRAME) return;
      const data = new AudioData({
        format: 'f32', sampleRate: RATE, numberOfFrames: FRAME, numberOfChannels: 1,
        timestamp: timestamp, data: frame,
      });
      timestamp += 20000;            // microseconds
      enc.encode(data);
      data.close();
    };
    this.close = function () { if (enc.state !== 'closed') enc.close(); };
  }

  function OpusDecoder(onAudio) {
    let timestamp = 0;
    const dec = new AudioDecoder({
      output: function (audio) {
        const out = new Float32Array(audio.numberOfFrames);
        audio.copyTo(out, { planeIndex: 0 });
        const rate = audio.sampleRate;
        audio.close();
        onAudio(out, rate);
      },
      error: function (e) { console.error('[psradio] opus decoder', e); },
    });
    dec.configure({ codec: 'opus', sampleRate: RATE, numberOfChannels: 1 });

    this.decode = function (packet) {
      if (dec.state !== 'configured' || packet.length > 1275) return;
      dec.decode(new EncodedAudioChunk({ type: 'key', timestamp: timestamp, data: packet }));
      timestamp += 20000;
    };
    this.close = function () { if (dec.state !== 'closed') dec.close(); };
  }

  // ------------------------------------------------------------ registry
  const registry = {};
  registry[ID.adpcm] = {
    name: 'adpcm',
    encoder: function (opts, onPacket) { return new AdpcmEncoder(onPacket); },
    decoder: function (onAudio) { return new AdpcmDecoder(onAudio); },
  };
  registry[ID.opus] = {
    name: 'opus',
    encoder: function (opts, onPacket) { return new OpusEncoder(opts, onPacket); },
    decoder: function (onAudio) { return new OpusDecoder(onAudio); },
  };

  // Which codecs this browser can really run. ADPCM is always true.
  async function detect() {
    const caps = { adpcm: true, opus: false };
    try {
      if (typeof AudioEncoder === 'function' && typeof AudioDecoder === 'function') {
        const enc = await AudioEncoder.isConfigSupported(opusConfig(16000));
        const dec = await AudioDecoder.isConfigSupported({ codec: 'opus', sampleRate: RATE, numberOfChannels: 1 });
        caps.opus = !!(enc && enc.supported && dec && dec.supported);
      }
    } catch (e) {
      caps.opus = false;
    }
    return caps;
  }

  const api = {
    RATE: RATE, FRAME: FRAME, ID: ID,
    pack: pack, unpack: unpack, toBase64: toBase64, fromBase64: fromBase64,
    detect: detect,
    createEncoder: function (id, opts, onPacket) {
      const c = registry[id];
      if (!c) throw new Error('unknown codec ' + id);
      return c.encoder(opts, onPacket);
    },
    createDecoder: function (id, onAudio) {
      const c = registry[id];
      if (!c) throw new Error('unknown codec ' + id);
      return c.decoder(onAudio);
    },
  };

  root.PSRAudio = root.PSRAudio || {};
  root.PSRAudio.Codecs = api;
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
})(typeof window !== 'undefined' ? window : globalThis);
