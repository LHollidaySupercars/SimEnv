// ============================================================
// SMP_DATA.JS — V8SC Pit Wall
// Progressive loading: last N events on startup, rest on demand
// Data source: Azure Function (replaces PocketBase REST API)
// Auth token injected by SMP_AUTH after Entra ID login
// ============================================================

const SMP_DATA = (() => {

  let _all      = [];
  let _filtered = [];
  let _loadedEvents = new Set();
  let _onUpdate = null;

  // ── BUILD FETCH HEADERS ───────────────────────────────────
  // Injects Entra ID bearer token if available from SMP_AUTH
  function authHeaders() {
    const token = (typeof SMP_AUTH !== 'undefined') ? SMP_AUTH.getToken() : null;
    const headers = { 'Content-Type': 'application/json' };
    if (token) headers['Authorization'] = 'Bearer ' + token;
    return headers;
  }

  // ── FETCH ALL DATA FROM AZURE FUNCTION ───────────────────
  // Replaces PocketBase paginated fetch.
  // The Function returns { items: [...], totalItems: N }
  async function fetchFromFunction(params = {}) {
    const url = new URL(SMP_CONFIG.FUNCTION_URL);
    if (params.event)   url.searchParams.set('event',   params.event);
    if (params.session) url.searchParams.set('session', params.session);

    const resp = await fetch(url.toString(), { headers: authHeaders() });

    if (resp.status === 401) {
      // Token expired — trigger re-login
      if (typeof SMP_AUTH !== 'undefined') await SMP_AUTH.login();
      throw new Error('Unauthorised — please log in again');
    }

    if (!resp.ok) throw new Error('HTTP ' + resp.status);

    const data = await resp.json();
    return data.items || [];
  }

  // ── FETCH: startup — last N events only ──────────────────
  async function fetchRecent() {
    const order = SMP_CONFIG.EVENT_ORDER;
    const n     = SMP_CONFIG.AUTO_LOAD_EVENTS;

    // Step 1: get all distinct events from loaded data
    // For first load we fetch everything and filter client-side
    // This avoids a separate metadata call to the Function
    const allItems = await fetchFromFunction();

    // Step 2: find which events exist in the data
    const existingEvents = new Set(allItems.map(r => r.event).filter(Boolean));

    // Step 3: intersect with EVENT_ORDER and sort by calendar position
    const sorted = order.filter(e => existingEvents.has(e));

    // Step 4: take last N events (most recent by calendar)
    const toLoad = sorted.slice(0, n);

    // Step 5: filter allItems to only the events we want for initial load
    // Store everything so on-demand loads for other events are instant
    _all = allItems;
    toLoad.forEach(ev => _loadedEvents.add(ev));

    if (_all.length > SMP_CONFIG.ROW_WARNING_THRESHOLD) showRowWarning(_all.length);

    // Show only the N most recent events initially
    _filtered = _all.filter(r => toLoad.includes(r.event));
    if (_onUpdate) _onUpdate(_filtered);
    return _all;
  }

  // ── FETCH: single event on demand ────────────────────────
  // Since all data is already loaded in fetchRecent,
  // this just filters from the in-memory cache.
  async function fetchEvent(eventName, notify = true) {
    if (_loadedEvents.has(eventName)) return;

    // Data is already in _all from the initial full fetch
    // Just mark it as loaded so the UI knows it's available
    _loadedEvents.add(eventName);

    if (_all.length > SMP_CONFIG.ROW_WARNING_THRESHOLD) showRowWarning(_all.length);
    if (notify) { _filtered = [..._all]; if (_onUpdate) _onUpdate(_filtered); }
  }

  // ── ROW WARNING ───────────────────────────────────────────
  function showRowWarning(count) {
    let el = document.getElementById('row-warning');
    if (!el) {
      el = document.createElement('div');
      el.id = 'row-warning';
      el.style.cssText = 'position:fixed;bottom:16px;right:16px;z-index:500;' +
        'background:rgba(255,107,0,0.92);color:#fff;font-family:JetBrains Mono,monospace;' +
        'font-size:11px;padding:10px 16px;border-radius:3px;letter-spacing:1px;' +
        'display:flex;align-items:center;gap:12px;';
      document.body.appendChild(el);
    }
    el.innerHTML = `⚠ ${count.toLocaleString()} rows — performance may degrade ` +
      `<button onclick="this.parentElement.remove()" style="background:transparent;` +
      `border:1px solid rgba(255,255,255,0.5);color:#fff;padding:2px 8px;border-radius:2px;` +
      `cursor:pointer;font-family:inherit;font-size:10px">DISMISS</button>`;
  }

  // ── FILTER ────────────────────────────────────────────────
  function applyFilters(events, sessions, teams, mfrs) {
    _filtered = _all.filter(r => {
      if (events.length   && !events.includes(r.event))         return false;
      if (sessions.length && !sessions.includes(r.session))     return false;
      if (teams.length    && !teams.includes(r.team))           return false;
      if (mfrs.length     && !mfrs.includes(r.manufacturer))    return false;
      return true;
    });
    if (_onUpdate) _onUpdate(_filtered);
  }

  function reset() { _filtered = [..._all]; if (_onUpdate) _onUpdate(_filtered); }

  // ── ACCESSORS ─────────────────────────────────────────────
  function getAll()          { return _all; }
  function getFiltered()     { return _filtered; }
  function getLoadedEvents() { return [..._loadedEvents]; }
  function onUpdate(fn)      { _onUpdate = fn; }

  function getAllUniqueEvents() {
    const order   = SMP_CONFIG.EVENT_ORDER;
    const evs     = [...new Set(_all.map(r => r.event).filter(Boolean))];
    const known   = evs.filter(e => order.includes(e)).sort((a,b) => order.indexOf(a) - order.indexOf(b));
    const unknown = evs.filter(e => !order.includes(e)).sort();
    return [...known, ...unknown];
  }

  function getAllUnique(field) {
    return [...new Set(_all.map(r => r[field]).filter(Boolean))].sort();
  }

  function getUnique(field) {
    return [...new Set(_filtered.map(r => r[field]).filter(Boolean))].sort();
  }

  // ── DERIVE MATH OPS from loaded data ─────────────────────
  function getMathOps() {
    const known = ['max','min','mean','mean_nz'];
    if (!_all.length) return known;
    const keys = Object.keys(_all[0]);
    const found = new Set();
    keys.forEach(k => known.forEach(op => { if (k.endsWith('_' + op)) found.add(op); }));
    return known.filter(op => found.has(op));
  }

  // ── FORMAT HELPERS ────────────────────────────────────────
  function fmtTime(s) {
    if (!s && s !== 0) return '—';
    const m = Math.floor(s / 60);
    return m + ':' + (s % 60).toFixed(3).padStart(6, '0');
  }

  function mfrColor(mfr, prop) {
    return (SMP_CONFIG.MFR[mfr] || SMP_CONFIG.MFR.default)[prop];
  }

  // ── SCATTER BY MANUFACTURER ───────────────────────────────
  function byManufacturer(xField, yField, yMin, yMax, clip) {
    const mfrs = ['Ford', 'Chevrolet', 'Toyota'];
    return mfrs.map(mfr => {
      let rows = _filtered.filter(r =>
        r.manufacturer === mfr &&
        r[xField] != null && isFinite(r[xField]) &&
        r[yField] != null && isFinite(r[yField]) && r[yField] !== 0
      );
      if (clip) {
        if (yMin !== null && yMin !== '') rows = rows.filter(r => r[yField] >= parseFloat(yMin));
        if (yMax !== null && yMax !== '') rows = rows.filter(r => r[yField] <= parseFloat(yMax));
      }
      return {
        label: mfr,
        data: rows.map(r => ({
          x: r[xField], y: r[yField],
          driver: r.driver, car: r.car_number,
          team: r.team, session: r.session, lap: r.lap_number,
        })),
        backgroundColor: mfrColor(mfr, 'bg'),
        borderColor:     mfrColor(mfr, 'bd'),
        borderWidth: 0.5,
        pointRadius:      SMP_CONFIG.CHART.POINT_RADIUS,
        pointHoverRadius: SMP_CONFIG.CHART.POINT_HOVER,
      };
    }).filter(ds => ds.data.length > 0);
  }

  // ── SORTED FALLING SPEED ──────────────────────────────────
  function sortedFallingSpeed(yMin, yMax, clip) {
    let rows = _filtered.filter(r => r.ground_speed_max > 0 && isFinite(r.ground_speed_max));
    if (clip) {
      if (yMin !== null && yMin !== '') rows = rows.filter(r => r.ground_speed_max >= parseFloat(yMin));
      if (yMax !== null && yMax !== '') rows = rows.filter(r => r.ground_speed_max <= parseFloat(yMax));
    }
    const driverSet = [...new Set(rows.map(r => r.driver).filter(Boolean))];
    const mfrs = ['Ford', 'Chevrolet', 'Toyota'];
    return mfrs.map(mfr => {
      const points = [];
      driverSet.forEach(driver => {
        let dr = rows.filter(r => r.driver === driver && r.manufacturer === mfr);
        dr = [...dr].sort((a,b) => b.ground_speed_max - a.ground_speed_max);
        dr.forEach((r, i) => points.push({
          x: i + 1, y: r.ground_speed_max,
          driver: r.driver, car: r.car_number,
          team: r.team, session: r.session, lap: r.lap_number,
        }));
      });
      return {
        label: mfr, data: points,
        backgroundColor: mfrColor(mfr, 'bg'),
        borderColor:     mfrColor(mfr, 'bd'),
        borderWidth: 0,
        pointRadius:      SMP_CONFIG.CHART.POINT_RADIUS_SMALL,
        pointHoverRadius: 3,
      };
    }).filter(ds => ds.data.length > 0);
  }

  return {
    fetchRecent, fetchEvent,
    applyFilters, reset,
    getAll, getFiltered, getLoadedEvents,
    getAllUniqueEvents, getAllUnique, getUnique,
    getMathOps, onUpdate, fmtTime, mfrColor,
    byManufacturer, sortedFallingSpeed,
  };
})();
