'use strict';
// Unit tests for the parts of web/js/audio/codecs.js that run without a browser.
const C = require('../web/js/audio/codecs.js');

module.exports = function run() {
  let failed = 0;
  const check = (cond, what) => {
    if (!cond) { failed++; console.log('  FAIL: ' + what); }
  };

  // packet framing round trip
  const packets = [Uint8Array.of(1, 2, 3), new Uint8Array(300).fill(7), Uint8Array.of(9)];
  const wire = C.toBase64(C.pack(packets));
  const back = C.unpack(C.fromBase64(wire));
  check(back.length === 3 && back[1].length === 300 && back[2][0] === 9, 'pack/unpack round trip');
  check(/^[A-Za-z0-9+/]+=?=?$/.test(wire) && wire.length % 4 === 0, 'wire format is plain base64');

  // hostile input
  check(C.unpack(Uint8Array.of(0xff, 0xff, 1, 2)).length === 0, 'length beyond the buffer is rejected');
  check(C.unpack(Uint8Array.of(0, 0, 0, 0)).length === 0, 'zero-length record stops parsing');
  check(C.unpack(Uint8Array.of(0)).length === 0, 'truncated header is ignored');
  const many = C.pack(Array.from({ length: 50 }, () => Uint8Array.of(1)));
  check(C.unpack(many).length === 8, 'packet count per message is capped');

  // ADPCM: a 1 kHz tone must survive encode -> decode at 8 kHz
  const encoded = [];
  const enc = C.createEncoder(C.ID.adpcm, {}, (p) => encoded.push(p));
  const frames = 25;
  for (let f = 0; f < frames; f++) {
    const frame = new Float32Array(C.FRAME);
    for (let i = 0; i < C.FRAME; i++) {
      frame[i] = 0.5 * Math.sin((2 * Math.PI * 1000 * (f * C.FRAME + i)) / C.RATE);
    }
    enc.encode(frame);
  }
  check(encoded.length === frames, 'one ADPCM packet per 20 ms frame');
  check(encoded.every((p) => p.length === 83), 'ADPCM packet is 83 bytes (3 header + 80 data) = 33.2 kbit/s');

  const decoded = [];
  let rate = 0;
  const dec = C.createDecoder(C.ID.adpcm, (samples, r) => { decoded.push(samples); rate = r; });
  encoded.forEach((p) => dec.decode(p));
  check(rate === 8000 && decoded.length === frames && decoded[0].length === 160, 'decoder yields 160 samples at 8 kHz');

  // compare against the ideal tone, skipping the filter warm-up, allowing for filter delay
  const flat = new Float32Array(frames * 160);
  decoded.forEach((d, i) => flat.set(d, i * 160));
  let best = Infinity;
  for (let delay = 0; delay < 16; delay++) {
    let err = 0, n = 0;
    for (let i = 800; i < flat.length; i++) {
      const ideal = 0.5 * Math.sin((2 * Math.PI * 1000 * (i - delay)) / 8000);
      err += (flat[i] - ideal) ** 2;
      n++;
    }
    best = Math.min(best, Math.sqrt(err / n));
  }
  check(best < 0.03, 'ADPCM tone error is small (rms ' + best.toFixed(4) + ')');

  // packets decode independently (each carries its own predictor state)
  const lone = [];
  C.createDecoder(C.ID.adpcm, (s) => lone.push(s)).decode(encoded[20]);
  let diff = 0;
  for (let i = 0; i < 160; i++) diff = Math.max(diff, Math.abs(lone[0][i] - decoded[20][i]));
  check(diff === 0, 'a packet decodes the same without the ones before it');

  // hostile ADPCM input
  const out = [];
  const d2 = C.createDecoder(C.ID.adpcm, (s) => out.push(s));
  d2.decode(new Uint8Array(10));
  d2.decode(Uint8Array.from({ length: 83 }, (_, i) => (i === 2 ? 200 : 255)));
  check(out.length === 0, 'wrong-size and out-of-range ADPCM packets are ignored');
  d2.decode(new Uint8Array(83).fill(255).fill(88, 2, 3));
  check(out.length === 1 && out[0].every((v) => v >= -1 && v <= 1), 'extreme ADPCM input stays within range');

  let threw = false;
  try { C.createDecoder(99, () => {}); } catch (e) { threw = true; }
  check(threw, 'unknown codec id is refused');

  console.log(failed === 0 ? '  ok' : '');
  return failed;
};
