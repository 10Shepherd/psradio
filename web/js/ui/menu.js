/*
 * The softkey menu: which labels sit above the keys and what each one does.
 *
 * A page is a function that returns one entry per key, which lets a label
 * change with the radio's state (MENU becomes BACK inside a menu, a key is
 * disabled while the radio is off). Pages are declared by app.js; nothing in
 * here knows what a channel or a setting is.
 *
 *   menu.define('home', function () { return [ {label: 'ZONE', action: fn} ]; });
 *   menu.press(0);        // the player pressed the first softkey
 *   menu.go('settings');  // open a page, remembering where we came from
 *   menu.back();          // one page back towards home
 */
(function () {
  'use strict';
  const UI = (window.PSRUI = window.PSRUI || {});

  const MIN_KEYS = 3;
  const MAX_KEYS = 4;

  function Menu(options) {
    options = options || {};
    this.builders = {};
    this.stack = ['home'];
    this.softkeys = MIN_KEYS;
    this.onDraw = options.onDraw || function () {};
    this.onPage = options.onPage || function () {};
  }

  Menu.prototype.define = function (id, builder) {
    this.builders[id] = builder;
  };

  Menu.prototype.page = function () {
    return this.stack[this.stack.length - 1];
  };

  Menu.prototype.isHome = function () {
    return this.stack.length === 1;
  };

  // 3 or 4, from the radio model.
  Menu.prototype.setSoftkeys = function (count) {
    const n = Math.max(MIN_KEYS, Math.min(MAX_KEYS, count | 0));
    if (n === this.softkeys) return false;
    this.softkeys = n;
    return true;
  };

  // The entries for the current page, padded out to the key count so the
  // display and the buttons always line up.
  Menu.prototype.keys = function () {
    const builder = this.builders[this.page()];
    const entries = (builder ? builder(this.softkeys) : []) || [];
    const keys = entries.slice(0, this.softkeys);
    while (keys.length < this.softkeys) keys.push(null);
    return keys;
  };

  Menu.prototype.press = function (index) {
    const entry = this.keys()[index];
    if (!entry || entry.disabled || typeof entry.action !== 'function') return false;
    entry.action();
    return true;
  };

  Menu.prototype.go = function (id) {
    if (!this.builders[id] || this.page() === id) return false;
    this.stack.push(id);
    this.onPage(this.page());
    this.draw();
    return true;
  };

  Menu.prototype.back = function () {
    if (this.stack.length <= 1) return false;
    this.stack.pop();
    this.onPage(this.page());
    this.draw();
    return true;
  };

  Menu.prototype.home = function () {
    if (this.stack.length <= 1) return false;
    this.stack = ['home'];
    this.onPage(this.page());
    this.draw();
    return true;
  };

  Menu.prototype.draw = function () {
    this.onDraw(this.keys(), this.page());
  };

  UI.Menu = Menu;
})();
