/*
 * Radio tones, synthesised with oscillators and noise — no audio files are
 * shipped. A tone is a list of steps:
 *
 *   [1050, 0.04]            one sine at 1050 Hz for 40 ms
 *   [[1050, 1450], 0.04]    both frequencies together
 *   [0, 0.03]               a gap
 *   ['noise', 0.08]         a band-limited noise burst (squelch crackle)
 *
 * Levels are relative to Tones.volume, which is the player's tone setting.
 */
(function () {
  'use strict';
  const A = (window.PSRAudio = window.PSRAudio || {});

  const TONES = {
    // transmit
    permit:   [[1050, 0.035], [0, 0.03], [1050, 0.035], [0, 0.03], [1050, 0.035]],
    end:      [[880, 0.04]],
    deny:     [[310, 0.28]],
    // refused because someone else has the channel: the classic double "bonk"
    bonk:     [[270, 0.12], [0, 0.04], [270, 0.12]],
    override: [[1450, 0.05], [0, 0.025], [1150, 0.05], [0, 0.025], [950, 0.12]],
    // receive
    rxOpen:   [['noise', 0.025]],
    roger:    [[1250, 0.06]],
    // radio
    power:    [[660, 0.07], [880, 0.07], [1100, 0.09]],
    off:      [[880, 0.07], [660, 0.09]],
    key:      [[1400, 0.02]],
    menu:     [[1700, 0.025], [0, 0.015], [2100, 0.025]],
    error:    [[400, 0.09], [0, 0.04], [400, 0.09]],
    // battery
    battLow:  [[[1400, 1100], 0.08], [0, 0.05], [[1400, 1100], 0.08]],
    battDead: [[700, 0.12], [560, 0.12], [420, 0.3]],
  };

  const Tones = { volume: 0.25 };
  let noiseBuffer = null;

  // One second of white noise, built once and reused by every burst.
  function noise(audio) {
    if (noiseBuffer && noiseBuffer.sampleRate === audio.sampleRate) return noiseBuffer;
    const buffer = audio.createBuffer(1, Math.floor(audio.sampleRate), audio.sampleRate);
    const data = buffer.getChannelData(0);
    for (let i = 0; i < data.length; i++) data[i] = Math.random() * 2 - 1;
    noiseBuffer = buffer;
    return buffer;
  }

  Tones.setVolume = function (v) {
    Tones.volume = Math.max(0, Math.min(1, v));
  };

  // A short ramp at each edge; a square-edged gate clicks.
  function envelope(audio, level, at, dur) {
    const gain = audio.createGain();
    const edge = Math.min(0.004, dur / 4);
    gain.gain.setValueAtTime(0, at);
    gain.gain.linearRampToValueAtTime(level, at + edge);
    gain.gain.setValueAtTime(level, at + dur - edge);
    gain.gain.linearRampToValueAtTime(0, at + dur);
    gain.connect(audio.destination);
    return gain;
  }

  Tones.play = function (name) {
    const steps = TONES[name];
    if (!steps || Tones.volume <= 0) return;
    const audio = A.context();
    let at = audio.currentTime + 0.01;

    for (let i = 0; i < steps.length; i++) {
      const what = steps[i][0], dur = steps[i][1];
      if (what === 'noise') {
        const source = audio.createBufferSource();
        source.buffer = noise(audio);
        source.loop = true;
        const band = audio.createBiquadFilter();
        band.type = 'bandpass';
        band.frequency.value = 1800;
        band.Q.value = 0.7;
        source.connect(band);
        band.connect(envelope(audio, Tones.volume * 0.5, at, dur));
        source.start(at, 0, dur + 0.02);
        source.stop(at + dur + 0.02);
      } else if (what) {
        const freqs = typeof what === 'number' ? [what] : what;
        // sharing one envelope keeps a dual tone from being twice as loud
        const gain = envelope(audio, Tones.volume / freqs.length, at, dur);
        for (let f = 0; f < freqs.length; f++) {
          const osc = audio.createOscillator();
          osc.type = 'sine';
          osc.frequency.value = freqs[f];
          osc.connect(gain);
          osc.start(at);
          osc.stop(at + dur + 0.01);
        }
      }
      at += dur;
    }
  };

  Tones.has = function (name) {
    return Object.prototype.hasOwnProperty.call(TONES, name);
  };

  A.Tones = Tones;
})();
