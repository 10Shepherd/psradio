/*
 * Radio page: draws the display, sends button presses to the client script,
 * and runs the transmit / receive audio. It never decides anything about
 * access — it shows what the server reported.
 */
(function () {
  'use strict';
  const A = window.PSRAudio;
  const Codecs = A.Codecs;
  const RESOURCE = typeof GetParentResourceName === 'function' ? GetParentResourceName() : 'psradio';

  const $ = function (id) { return document.getElementById(id); };
  const el = {
    radio: $('radio'), lcd: $('lcd'), led: $('led'),
    mode: $('lcd-mode'), ind: $('lcd-ind'), unit: $('lcd-unit'),
    zone: $('lcd-zone'), chan: $('lcd-chan'), msg: $('lcd-msg'),
    power: $('btn-power'), close: $('btn-close'), ptt: $('btn-ptt'),
    zoneKey: $('btn-zone'), chPrev: $('btn-ch-prev'), chNext: $('btn-ch-next'),
    volUp: $('btn-vol-up'), volDown: $('btn-vol-down'),
  };

  const capture = new A.Capture();
  const player = new A.Player();

  let strings = {};
  let access = null;                 // { codeplug, zones } or null
  let state = { power: false, channelId: null, callsign: null, unitId: null };
  let tx = null;                     // current outgoing transmission
  const rx = new Map();              // txId -> { label }
  let msgTimer = null;
  let msgBusy = false;

  function post(name, data) {
    return fetch('https://' + RESOURCE + '/' + name, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json; charset=UTF-8' },
      body: JSON.stringify(data || {}),
    }).catch(function () {});
  }

  function t(key, param) {
    const s = Object.prototype.hasOwnProperty.call(strings, key) ? String(strings[key]) : key;
    return param === undefined || param === null ? s : s.replace('{1}', String(param));
  }

  // ---------------------------------------------------------------- display
  function applyStrings() {
    document.querySelectorAll('[data-i18n]').forEach(function (n) { n.textContent = t(n.dataset.i18n); });
    document.querySelectorAll('[data-i18n-aria]').forEach(function (n) {
      n.setAttribute('aria-label', t(n.dataset.i18nAria));
    });
  }

  // Zones that hold at least one channel this radio may select.
  function usableZones() {
    if (!access) return [];
    return access.zones
      .map(function (z) { return { id: z.id, name: z.name, channels: z.channels.filter(function (c) { return c.tx; }) }; })
      .filter(function (z) { return z.channels.length > 0; });
  }

  function locate() {
    const zones = usableZones();
    for (let zi = 0; zi < zones.length; zi++) {
      for (let ci = 0; ci < zones[zi].channels.length; ci++) {
        if (zones[zi].channels[ci].id === state.channelId) {
          return { zones: zones, zi: zi, ci: ci, zone: zones[zi], channel: zones[zi].channels[ci] };
        }
      }
    }
    return { zones: zones, zi: -1, ci: -1, zone: null, channel: null };
  }

  function showMessage(text, alert) {
    el.msg.textContent = text;
    el.msg.classList.toggle('alert', !!alert);
    clearTimeout(msgTimer);
    msgBusy = true;
    msgTimer = setTimeout(function () {
      msgBusy = false;
      el.msg.classList.remove('alert');
      renderMessage();
    }, 2500);
  }

  function renderMessage() {
    if (tx && tx.live) { el.msg.textContent = ''; return; }
    const first = rx.values().next().value;
    el.msg.textContent = first ? t('rx_from', first.label) : '';
  }

  function render() {
    const on = state.power;
    el.lcd.classList.toggle('off', !on);
    el.power.setAttribute('aria-pressed', on ? 'true' : 'false');
    const here = locate();
    el.zone.textContent = here.zone ? here.zone.name : '';
    el.chan.textContent = here.channel ? here.channel.name : t('no_channel');
    el.mode.textContent = here.channel ? t(here.channel.mode === 'analog' ? 'mode_analog' : 'mode_digital') : '';
    el.unit.textContent = state.callsign || (state.unitId ? t('unit', state.unitId) : '');
    const sending = !!(tx && tx.live);
    const receiving = on && rx.size > 0;
    el.ind.textContent = sending ? t('ind_tx') : receiving ? t('ind_rx') : '';
    el.led.className = 'led' + (sending ? ' tx' : receiving ? ' rx' : '');
    el.ptt.classList.toggle('active', sending);
    if (!msgBusy) renderMessage();
  }

  // ---------------------------------------------------------------- channel keys
  function select(channel) {
    if (!state.power || !channel || channel.id === state.channelId) return;
    A.Tones.play('key');
    post('select', { channelId: channel.id });
  }

  function stepChannel(delta) {
    const here = locate();
    if (!here.zones.length) return;
    if (!here.zone) return select(here.zones[0].channels[0]);
    const list = here.zone.channels;
    select(list[(here.ci + delta + list.length) % list.length]);
  }

  function nextZone() {
    const here = locate();
    if (!here.zones.length) return;
    select(here.zones[(here.zi + 1) % here.zones.length].channels[0]);
  }

  // ---------------------------------------------------------------- transmit
  function flush(cur) {
    if (!cur.pending.length) return;
    const data = Codecs.toBase64(Codecs.pack(cur.pending));
    cur.pending = [];
    post('txFrame', { txId: cur.id, seq: cur.seq++, data: data });
  }

  async function txStart(m) {
    txStop();
    const cur = { id: m.txId, seq: 0, pending: [], per: Math.max(1, m.framesPerPacket | 0), live: false, open: true, encoder: null };
    tx = cur;
    try {
      cur.encoder = Codecs.createEncoder(m.codec, { bitrate: m.bitrate }, function (packet) {
        if (!cur.open) return;
        cur.pending.push(packet);
        if (cur.pending.length >= cur.per) flush(cur);
      });
      await capture.start(function (frame) { if (cur.open) cur.encoder.encode(frame); });
    } catch (e) {
      console.error('[psradio] microphone', e);
      cur.open = false;
      if (tx === cur) tx = null;
      post('micError', { name: String((e && e.name) || 'error') });
      A.Tones.play('deny');
      showMessage(t('mic_error'), true);
      render();
      return;
    }
    if (!cur.open) { capture.pause(); return; }   // key released while the mic prompt was up
    cur.live = true;
    A.Tones.play('permit');
    render();
  }

  function txStop() {
    if (!tx) return;
    const cur = tx;
    tx = null;
    const wasLive = cur.live;
    cur.open = false;
    cur.live = false;
    capture.pause();
    try { if (cur.encoder) cur.encoder.close(); } catch (e) { /* already closed */ }
    if (wasLive) A.Tones.play('end');
    render();
  }

  // ---------------------------------------------------------------- messages from the client script
  const handlers = {
    init: function (m) {
      strings = m.strings || {};
      access = m.access || null;
      state = Object.assign({ power: false, channelId: null }, m.state || {});
      applyStrings();
      render();
    },
    access: function (m) {
      access = m.access || null;
      render();
    },
    state: function (m) {
      const before = state;
      state = Object.assign({ power: false, channelId: null }, m.state || {});
      if (before.power !== state.power) A.Tones.play(state.power ? 'power' : 'off');
      if (!state.power || before.channelId !== state.channelId) {
        player.closeAll();
        rx.clear();
      }
      if (!state.power) { txStop(); capture.release(); }
      render();
    },
    visible: function (m) {
      el.radio.hidden = !m.visible;
      if (m.visible) el.power.focus();
    },
    message: function (m) { showMessage(String(m.text || ''), false); },
    deny: function (m) {
      txStop();
      A.Tones.play('deny');
      showMessage(t(String(m.reason || 'tx_denied')), true);
    },
    txStart: function (m) { txStart(m); },
    txStop: function () { txStop(); },
    rxStart: function (m) {
      if (!state.power || m.channelId !== state.channelId) return;
      player.open(m.txId, m.codec, m.mode);
      rx.set(m.txId, { label: String(m.label || '') });
      render();
    },
    rxFrame: function (m) { player.push(m.txId, m.data); },
    rxStop: function (m) {
      player.close(m.txId);
      rx.delete(m.txId);
      render();
    },
  };

  window.addEventListener('message', function (e) {
    const m = e.data;
    if (m && typeof m.type === 'string' && Object.prototype.hasOwnProperty.call(handlers, m.type)) {
      handlers[m.type](m);
    }
  });

  // ---------------------------------------------------------------- controls
  el.power.addEventListener('click', function () {
    A.context();                                  // unlock audio on a user gesture
    post('power', { on: !state.power });
  });
  el.close.addEventListener('click', function () { post('close'); });
  el.zoneKey.addEventListener('click', nextZone);
  el.chPrev.addEventListener('click', function () { stepChannel(-1); });
  el.chNext.addEventListener('click', function () { stepChannel(1); });

  function loadVolume() {
    try {
      const v = parseFloat(localStorage.getItem('psradio.volume'));
      if (v >= 0 && v <= 1) player.setVolume(v);
    } catch (e) { /* storage unavailable: keep the default */ }
  }
  function changeVolume(delta) {
    player.setVolume(Math.round((player.volume + delta) * 10) / 10);
    try { localStorage.setItem('psradio.volume', String(player.volume)); } catch (e) { /* not saved */ }
    A.Tones.play('key');
    showMessage(t('ui_volume', Math.round(player.volume * 100) + '%'), false);
  }
  el.volUp.addEventListener('click', function () { changeVolume(0.1); });
  el.volDown.addEventListener('click', function () { changeVolume(-0.1); });

  // On-screen PTT: hold with the mouse, or hold Space / Enter while focused.
  let pttPressed = false;
  function pttDown(e) { if (e) e.preventDefault(); if (!pttPressed) { pttPressed = true; post('pttDown'); } }
  function pttUp() { if (pttPressed) { pttPressed = false; post('pttUp'); } }
  el.ptt.addEventListener('mousedown', pttDown);
  window.addEventListener('mouseup', pttUp);
  el.ptt.addEventListener('blur', pttUp);
  el.ptt.addEventListener('keydown', function (e) { if ((e.key === ' ' || e.key === 'Enter') && !e.repeat) pttDown(e); });
  el.ptt.addEventListener('keyup', function (e) { if (e.key === ' ' || e.key === 'Enter') pttUp(); });

  window.addEventListener('keydown', function (e) {
    if (e.key === 'Escape' && !el.radio.hidden) post('close');
  });

  // ---------------------------------------------------------------- start
  loadVolume();
  Codecs.detect().then(function (caps) { post('ready', { opus: caps.opus }); });
})();
