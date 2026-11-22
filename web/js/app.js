/*
 * Radio page: draws the display, runs the softkey menu, sends button presses to
 * the client script, and runs the transmit / receive audio.
 *
 * Settings are not here: they are an ox_lib menu on the client side, opened
 * with /radiosetting. This page only applies what the server reports.
 */
(function () {
  'use strict';
  const A = window.PSRAudio;
  const UI = window.PSRUI;
  const Codecs = A.Codecs;
  const RESOURCE = typeof GetParentResourceName === 'function' ? GetParentResourceName() : 'psradio';

  const $ = function (id) { return document.getElementById(id); };
  const el = {
    radio: $('radio'), lcd: $('lcd'), led: $('led'),
    mode: $('lcd-mode'), ind: $('lcd-ind'), unit: $('lcd-unit'),
    main: $('lcd-main'), zone: $('lcd-zone'), chan: $('lcd-chan'),
    panel: $('lcd-panel'), msg: $('lcd-msg'), soft: $('lcd-soft'),
    power: $('btn-power'), close: $('btn-close'), ptt: $('btn-ptt'),
    menu: $('btn-menu'), softkeys: $('softkeys'),
    volUp: $('btn-vol-up'), volDown: $('btn-vol-down'),
    batt: $('batt'), battBar: $('batt-bar'), battText: $('batt-text'),
  };

  const capture = new A.Capture();
  const player = new A.Player();

  let strings = {};
  let access = null;                 // { codeplug, zones } or null
  let state = { power: false, channelId: null, callsign: null, unitId: null, model: null };
  let settings = {};                 // the player's own settings, from the server
  let audioConfig = null;            // Config.audio, from the server
  let battery = { enabled: false, percent: 100, charging: false, warnAt: 0 };
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

  const menu = new UI.Menu({
    onDraw: drawSoftkeys,
    onPage: function () { renderPanel(); render(); },
  });

  // ---------------------------------------------------------------- display
  function applyStrings() {
    document.querySelectorAll('[data-i18n]').forEach(function (n) { n.textContent = t(n.dataset.i18n); });
    document.querySelectorAll('[data-i18n-aria]').forEach(function (n) {
      n.setAttribute('aria-label', t(n.dataset.i18nAria));
    });
    el.menu.textContent = t('ui_menu_short');
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

  function models() {
    return (access && access.codeplug && access.codeplug.models) || [];
  }

  function currentModel() {
    const list = models();
    // The server sends the model in the radio state and in the settings, in
    // that order; either on its own is enough to draw the right radio.
    const wanted = state.model || settings.model;
    for (let i = 0; i < list.length; i++) {
      if (list[i].id === wanted) return list[i];
    }
    return list[0] || { id: null, name: '', skin: 'handheld', softkeys: 3 };
  }

  // The model decides the look and how many softkeys the radio has.
  function applyModel() {
    const model = currentModel();
    el.radio.dataset.skin = model.skin || 'handheld';
    const count = model.softkeys || 3;
    el.radio.dataset.keys = String(count);
    menu.setSoftkeys(count);
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

  function drawSoftkeys(keys) {
    const buttons = el.softkeys.querySelectorAll('[data-soft]');
    const labels = el.soft.querySelectorAll('span');
    // The knob key is the way into the menu, and the way back out of one. On a
    // 4-key radio the fourth softkey is MENU, so CSS hides this one.
    el.menu.textContent = t(menu.isHome() ? 'ui_menu_short' : 'key_back');
    for (let i = 0; i < buttons.length; i++) {
      const entry = i < keys.length ? keys[i] : null;
      const shown = entry ? t(entry.labelKey || entry.label) : '';
      buttons[i].hidden = i >= menu.softkeys;
      buttons[i].textContent = shown;
      buttons[i].disabled = !entry || entry.disabled === true;
      buttons[i].setAttribute('aria-label', entry && entry.ariaKey ? t(entry.ariaKey) : shown);
      if (labels[i]) {
        labels[i].hidden = i >= menu.softkeys;
        labels[i].textContent = shown;
      }
    }
  }

  // The display area below the status row: either the channel, or a menu page.
  function renderPanel() {
    const page = menu.page();
    const onMenuPage = page !== 'home';
    el.main.hidden = onMenuPage;
    el.panel.hidden = !onMenuPage;
    if (page === 'info') renderInfo();
  }

  function renderInfo() {
    const here = locate();
    const cp = (access && access.codeplug) || {};
    const rows = [
      ['info_unit', state.callsign || (state.unitId ? t('unit', state.unitId) : '-')],
      ['info_codeplug', cp.name || '-'],
      ['info_nac', cp.nac || '-'],
      ['info_channel', here.channel ? here.channel.name : '-'],
      ['info_frequency', here.channel && here.channel.frequency
        ? here.channel.frequency.toFixed(3) + ' ' + t('info_mhz') : '-'],
      ['info_mode', here.channel ? t(here.channel.mode === 'analog' ? 'mode_analog_full' : 'mode_digital_full') : '-'],
      ['info_model', currentModel().name || '-'],
    ];
    if (battery.enabled) rows.push(['info_battery', battery.percent + '%']);
    if (cp.supervisor) rows.push(['info_role', t('info_supervisor')]);
    rows.push(['info_settings', t('info_settings_cmd')]);

    el.panel.textContent = '';
    rows.forEach(function (pair) {
      const line = document.createElement('div');
      line.className = 'row';
      const label = document.createElement('span');
      label.className = 'row-label';
      label.textContent = t(pair[0]);
      const value = document.createElement('span');
      value.className = 'row-value';
      value.textContent = String(pair[1]);
      line.appendChild(label);
      line.appendChild(value);
      el.panel.appendChild(line);
    });
  }

  function renderBattery() {
    el.batt.hidden = !battery.enabled;
    if (!battery.enabled) return;
    const percent = Math.max(0, Math.min(100, battery.percent));
    el.battBar.style.width = percent + '%';
    el.battText.textContent = percent + '%';
    el.batt.classList.toggle('low', percent <= (battery.warnAt || 25));
    el.batt.classList.toggle('dead', percent <= 0);
    el.batt.classList.toggle('charging', battery.charging === true);
    el.batt.setAttribute('aria-label',
      t(battery.charging ? 'ui_battery_charging' : 'ui_battery_level', percent + '%'));
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
    el.radio.classList.toggle('latched', sending && settings.pttMode === 'toggle');
    renderBattery();
    menu.draw();
    if (menu.page() === 'info') renderInfo();
    if (!msgBusy) renderMessage();
  }

  // ---------------------------------------------------------------- settings
  function applySettings(next) {
    settings = next || {};
    player.setVolume((settings.volume === undefined ? 80 : settings.volume) / 100);
    A.Tones.setVolume((settings.toneVolume === undefined ? 25 : settings.toneVolume) / 100);
    player.configure(audioConfig, settings.fx);
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

  function changeVolume(delta) {
    const now = settings.volume === undefined ? 80 : settings.volume;
    const next = Math.max(0, Math.min(100, Math.round((now + delta) / 5) * 5));
    if (next === now) return;
    settings.volume = next;
    player.setVolume(next / 100);
    A.Tones.play('key');
    showMessage(t('ui_volume', next + '%'), false);
    post('settings', { settings: { volume: next } });
  }

  // ---------------------------------------------------------------- menu pages
  function offHome() {
    return { labelKey: 'key_back', action: function () { A.Tones.play('menu'); menu.back(); } };
  }

  menu.define('home', function (count) {
    const keys = [
      { labelKey: 'ui_zone', ariaKey: 'ui_zone_full', action: nextZone, disabled: !state.power },
      { labelKey: 'ui_ch_prev', ariaKey: 'ui_ch_prev_full', action: function () { stepChannel(-1); }, disabled: !state.power },
      { labelKey: 'ui_ch_next', ariaKey: 'ui_ch_next_full', action: function () { stepChannel(1); }, disabled: !state.power },
    ];
    if (count >= 4) {
      keys.push({ labelKey: 'key_info', ariaKey: 'key_info_full', action: function () { A.Tones.play('menu'); menu.go('info'); } });
    }
    return keys;
  });

  menu.define('info', function (count) {
    const keys = [offHome()];
    while (keys.length < count) keys.push(null);
    return keys;
  });

  // The MENU key: the information page from the channel display, back out of
  // it again. Settings are no longer in here; they are in /radiosetting.
  function menuKey() {
    A.Tones.play('menu');
    if (menu.isHome()) menu.go('info'); else menu.back();
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
      A.Tones.play('error');
      showMessage(t('mic_error'), true);
      render();
      return;
    }
    if (!cur.open) { capture.pause(); return; }   // key released while the mic prompt was up
    cur.live = true;
    A.Tones.play(m.override ? 'override' : 'permit');
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
  const NOTIFY_TONES = { batt_low: 'battLow', batt_dead: 'battDead', no_access: 'error' };

  const handlers = {
    init: function (m) {
      strings = m.strings || {};
      access = m.access || null;
      state = Object.assign({ power: false, channelId: null, model: null }, m.state || {});
      audioConfig = m.audio || null;
      if (m.battery) battery = Object.assign(battery, m.battery);
      applyStrings();
      applySettings(m.settings);
      applyModel();
      menu.home();
      renderPanel();
      render();
    },
    settings: function (m) {
      applySettings(m.settings);
      applyModel();
      renderPanel();
      render();
    },
    battery: function (m) {
      battery.percent = m.percent;
      battery.charging = m.charging === true;
      renderBattery();
      if (menu.page() === 'info') renderInfo();
    },
    access: function (m) {
      access = m.access || null;
      applyModel();
      renderPanel();
      render();
    },
    state: function (m) {
      const before = state;
      state = Object.assign({ power: false, channelId: null, model: null }, m.state || {});
      if (before.power !== state.power) A.Tones.play(state.power ? 'power' : 'off');
      if (before.model !== state.model) applyModel();
      if (!state.power || before.channelId !== state.channelId) {
        player.closeAll();
        rx.clear();
      }
      if (!state.power) { txStop(); capture.release(); menu.home(); }
      renderPanel();
      render();
    },
    visible: function (m) {
      el.radio.hidden = !m.visible;
      if (m.visible) el.power.focus();
    },
    message: function (m) {
      const tone = NOTIFY_TONES[m.key];
      if (tone) A.Tones.play(tone);
      showMessage(String(m.text || ''), !!tone);
    },
    deny: function (m) {
      txStop();
      const reason = String(m.reason || 'tx_denied');
      if (m.canOverride) {
        // a supervisor on a busy channel: one more press takes it
        A.Tones.play('bonk');
        showMessage(t('tx_busy_override'), true);
      } else {
        A.Tones.play(reason === 'tx_busy' ? 'bonk' : 'deny');
        showMessage(t(reason), true);
      }
    },
    txStart: function (m) { txStart(m); },
    txStop: function () { txStop(); },
    rxStart: function (m) {
      if (!state.power || m.channelId !== state.channelId) return;
      player.open(m.txId, m.codec, m.mode);
      rx.set(m.txId, { label: String(m.label || '') });
      if (settings.fx !== 'off') A.Tones.play('rxOpen');
      render();
    },
    rxFrame: function (m) { player.push(m.txId, m.data); },
    rxStop: function (m) {
      const had = rx.has(m.txId);
      player.close(m.txId);
      rx.delete(m.txId);
      // the courtesy beep only follows a transmission that ended normally
      if (had && m.reason === 'released' && settings.rogerBeep !== false
        && audioConfig && audioConfig.rogerBeep !== false) {
        A.Tones.play('roger');
      }
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
  el.menu.addEventListener('click', menuKey);
  el.volUp.addEventListener('click', function () { changeVolume(5); });
  el.volDown.addEventListener('click', function () { changeVolume(-5); });

  el.softkeys.addEventListener('click', function (e) {
    const button = e.target.closest('[data-soft]');
    if (!button || button.disabled) return;
    menu.press(parseInt(button.dataset.soft, 10));
  });

  // On-screen PTT: hold with the mouse, or hold Space / Enter while focused.
  let pttPressed = false;
  function pttDown(e) { if (e) e.preventDefault(); if (!pttPressed) { pttPressed = true; post('pttDown'); } }
  function pttUp() { if (pttPressed) { pttPressed = false; post('pttUp'); } }
  el.ptt.addEventListener('mousedown', pttDown);
  window.addEventListener('mouseup', pttUp);
  el.ptt.addEventListener('blur', pttUp);
  el.ptt.addEventListener('keydown', function (e) { if ((e.key === ' ' || e.key === 'Enter') && !e.repeat) pttDown(e); });
  el.ptt.addEventListener('keyup', function (e) { if (e.key === ' ' || e.key === 'Enter') pttUp(); });

  // Escape backs out one page at a time, then hides the radio.
  window.addEventListener('keydown', function (e) {
    if (el.radio.hidden) return;
    if (e.key === 'Escape') {
      if (menu.isHome()) post('close'); else { A.Tones.play('menu'); menu.back(); }
    }
  });

  // ---------------------------------------------------------------- start
  applyModel();
  render();
  Codecs.detect().then(function (caps) { post('ready', { opus: caps.opus }); });
})();
