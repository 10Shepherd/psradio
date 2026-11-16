/*
 * Radio tones, synthesised with oscillators — no audio files are shipped.
 * Each tone is a list of [frequencyHz, durationSeconds] steps; 0 Hz is a gap.
 */
(function () {
  'use strict';
  const A = (window.PSRAudio = window.PSRAudio || {});

  const TONES = {
    permit:  [[1050, 0.035], [0, 0.03], [1050, 0.035], [0, 0.03], [1050, 0.035]],
    deny:    [[310, 0.28]],
    end:     [[880, 0.04]],
    power:   [[660, 0.07], [880, 0.07], [1100, 0.09]],
    off:     [[880, 0.07], [660, 0.09]],
    key:     [[1400, 0.02]],
  };

  const Tones = { volume: 0.25 };

  Tones.play = function (name) {
    const steps = TONES[name];
    if (!steps) return;
    const audio = A.context();
    let t = audio.currentTime + 0.01;
    for (let i = 0; i < steps.length; i++) {
      const freq = steps[i][0], dur = steps[i][1];
      if (freq > 0) {
        const osc = audio.createOscillator();
        const gain = audio.createGain();
        osc.type = 'sine';
        osc.frequency.value = freq;
        // short ramps avoid clicks at the edges
        gain.gain.setValueAtTime(0, t);
        gain.gain.linearRampToValueAtTime(Tones.volume, t + 0.004);
        gain.gain.setValueAtTime(Tones.volume, t + dur - 0.004);
        gain.gain.linearRampToValueAtTime(0, t + dur);
        osc.connect(gain);
        gain.connect(audio.destination);
        osc.start(t);
        osc.stop(t + dur + 0.01);
      }
      t += dur;
    }
  };

  A.Tones = Tones;
})();
