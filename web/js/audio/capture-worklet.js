// Runs on the audio thread: collects microphone samples into 20 ms frames
// (960 samples at 48 kHz) and posts each frame to the page.
class PsrCapture extends AudioWorkletProcessor {
  constructor() {
    super();
    this.frame = new Float32Array(960);
    this.fill = 0;
  }

  process(inputs) {
    const input = inputs[0] && inputs[0][0];
    if (!input) return true;
    let i = 0;
    while (i < input.length) {
      const n = Math.min(input.length - i, 960 - this.fill);
      this.frame.set(input.subarray(i, i + n), this.fill);
      this.fill += n;
      i += n;
      if (this.fill === 960) {
        this.port.postMessage(this.frame.slice(0));
        this.fill = 0;
      }
    }
    return true;
  }
}

registerProcessor('psr-capture', PsrCapture);
