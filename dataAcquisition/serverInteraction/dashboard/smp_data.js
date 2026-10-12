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

  // ── EVENT-CODE MATCHING ──────────────────────────────────
  // EVENT_ORDER (smp_config.js) lists bare track codes (e.g. 'QLR'),
  // but real event names uploaded via smp_compile_event_upload.m are
  // stamped as 'E09_QLR' (event number + track code, from the COM
  // folder name). A literal string-equality match therefore NEVER
  // matched any real event, silently breaking both the auto-load-N-
  // most-recent-events startup feature and the known/unknown event
  // sort in getAllUniqueEvents(). Match tolerantly instead: an order
  // code matches an event name if it equals it outright, or if the
  // event name ends with '_' + code (case-insensitive) — covering the
  // 'ENN_XXX' naming convention without requiring EVENT_ORDER to be
  // rewritten with full 'ENN_' prefixes each season.
  function eventMatchesCode(eventName, code) {
    if (!eventName || !code) return false;
    const e = eventName.toUpperCase();
    const c = code.toUpperCase();
    return e === c || e.endsWith('_' + c);
  }

  function findOrderIndex(eventName, order) {
    return order.findIndex(code => eventMatchesCode(eventName, code));
  }

  // ── EVENT NUMBER (chronological, straight from the name) ────
  // Event names are stamped 'E<NN>_<TRACK>' (e.g. 'E09_QLR') — the
  // leading number IS the calendar order for the season (events are
  // numbered as they're scheduled), so "most recent" can be determined
  // directly from the event name itself without needing EVENT_ORDER to
  // be kept up to date as the schedule moves around year to year.
  // EVENT_ORDER is still used as a tie-break/fallback for event names
  // that don't follow the 'ENN_' convention.
  function getEventNumber(eventName) {
    if (!eventName) return null;
    const m = eventName.match(/^E(\d+)_/i);
    return m ? parseInt(m[1], 10) : null;
  }

  // Sort event names most-recent-first: by event number descending when
  // available, falling back to EVENT_ORDER position for anything without
  // a recognised 'ENN_' prefix.
  function sortEventsMostRecentFirst(eventNames, order) {
    return [...eventNames].sort((a, b) => {
      const na = getEventNumber(a);
      const nb = getEventNumber(b);
      if (na !== null && nb !== null) return nb - na;
      if (na !== null) return -1;   // numbered events sort before unnumbered
      if (nb !== null) return 1;
      return findOrderIndex(a, order) - findOrderIndex(b, order);
    });
  }

  // ── FETCH: lightweight event list (cheap — dbo.Sessions only) ────
  async function fetchEventNames() {
    const url = new URL(SMP_CONFIG.FUNCTION_URL);
    url.searchParams.set('meta', 'events');

    const resp = await fetch(url.toString(), { headers: authHeaders() });
    if (resp.status === 401) {
      if (typeof SMP_AUTH !== 'undefined') await SMP_AUTH.login();
      throw new Error('Unauthorised — please log in again');
    }
    if (!resp.ok) throw new Error('Event list request failed');
    const data = await resp.json();
    return Array.isArray(data.events) ? data.events : [];
  }

  // ── FETCH: lightweight channel list (cheap — dbo.LapStats/Channels only) ──
  async function fetchChannelNames() {
    const url = new URL(SMP_CONFIG.FUNCTION_URL);
    url.searchParams.set('meta', 'channels');

    const resp = await fetch(url.toString(), { headers: authHeaders() });
    if (resp.status === 401) {
      if (typeof SMP_AUTH !== 'undefined') await SMP_AUTH.login();
      throw new Error('Unauthorised — please log in again');
    }
    if (!resp.ok) throw new Error('Channel list request failed');
    const data = await resp.json();
    return Array.isArray(data.channels) ? data.channels : [];
  }

  // ── SYNC: merge server-reported channels into SMP_CONFIG.ALL_CHANNELS ────
  // Keeps the channel pickers up to date with whatever channels have
  // actually been uploaded, instead of relying solely on the static list
  // baked in by smp_generate_config.m. Non-fatal on failure — the static
  // list already in smp_config.js remains as a fallback.
  async function syncChannelsFromServer() {
    const serverChannels = await fetchChannelNames();
    const existing = new Set(SMP_CONFIG.ALL_CHANNELS || []);
    let added = 0;
    serverChannels.forEach(ch => {
      if (!existing.has(ch)) {
        SMP_CONFIG.ALL_CHANNELS.push(ch);
        existing.add(ch);
        added++;
      }
    });
    return added;
  }

  // ── FETCH: startup — last N events only ──────────────────
  // Never fetches the whole database unfiltered: asks the server which
  // events exist (cheap ?meta=events call), picks the N most recent by
  // event number, and fetches ONLY those events' data via scoped,
  // filtered requests. (Previously called fetchFromFunction() with no
  // params — pulling every row for every event ever uploaded — which
  // only "worked" because a low server-side row cap silently truncated
  // the result; raising that cap to fix the truncation instead caused
  // 500s from the resulting oversized unfiltered query.)
  async function fetchRecent() {
    const order = SMP_CONFIG.EVENT_ORDER;
    const n     = SMP_CONFIG.AUTO_LOAD_EVENTS;

    const existingEvents = await fetchEventNames();
    const sorted = sortEventsMostRecentFirst(existingEvents, order);
    const toLoad = sorted.slice(0, n);

    const results = await Promise.all(toLoad.map(ev => fetchFromFunction({ event: ev })));
    _all = results.flat();
    toLoad.forEach(ev => _loadedEvents.add(ev));

    if (_all.length > SMP_CONFIG.ROW_WARNING_THRESHOLD) showRowWarning(_all.length);

    _filtered = [..._all];
    if (_onUpdate) _onUpdate(_filtered);
    return _all;
  }

  // ── FETCH: single event on demand ────────────────────────
  // Performs a real scoped fetch and appends to the accumulated
  // in-memory set (data for other events is no longer eagerly loaded).
  async function fetchEvent(eventName, notify = true) {
    if (_loadedEvents.has(eventName)) return;

    const items = await fetchFromFunction({ event: eventName });
    _all = _all.concat(items);
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
  function applyFilters(events, sessions, teams, years, mfrs) {
    _filtered = _all.filter(r => {
      if (events.length   && !events.includes(r.event))         return false;
      if (sessions.length && !sessions.includes(r.session))     return false;
      if (teams.length    && !teams.includes(r.team))           return false;
      if (years.length    && !years.includes(r.year))           return false;
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
    // Chronological (oldest-first) order for the filter dropdown — sort
    // by event number ascending when available, falling back to
    // EVENT_ORDER position for anything without a recognised 'ENN_' prefix.
    const known   = evs.filter(e => getEventNumber(e) !== null || findOrderIndex(e, order) !== -1)
                        .sort((a, b) => {
                          const na = getEventNumber(a), nb = getEventNumber(b);
                          if (na !== null && nb !== null) return na - nb;
                          if (na !== null) return -1;
                          if (nb !== null) return 1;
                          return findOrderIndex(a, order) - findOrderIndex(b, order);
                        });
    const unknown = evs.filter(e => getEventNumber(e) === null && findOrderIndex(e, order) === -1).sort();
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
    fetchChannelNames, syncChannelsFromServer,
    applyFilters, reset,
    getAll, getFiltered, getLoadedEvents,
    getAllUniqueEvents, getAllUnique, getUnique,
    getMathOps, onUpdate, fmtTime, mfrColor,
    byManufacturer, sortedFallingSpeed,
  };
})();
