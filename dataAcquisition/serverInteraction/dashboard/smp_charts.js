// ============================================================
// SMP_CHARTS.JS — V8SC Pit Wall
// Chart rendering — all tabs
// Requires: Chart.js + chartjs-plugin-zoom (loaded in index.html)
// ============================================================

const SMP_CHARTS = (() => {

  const _charts = {};

  function destroy(id) {
    if (_charts[id]) { _charts[id].destroy(); delete _charts[id]; }
  }

  // ── RICH TOOLTIP ─────────────────────────────────────────
  function tooltipLabel(ctx) {
    const d = ctx.raw;
    return [
      `${ctx.dataset.label}`,
      `Driver:  ${(d.driver||'—').replace(/_/g,' ')}`,
      `Car:     #${d.car||'—'}`,
      `Team:    ${d.team||'—'}`,
      `Session: ${d.session||'—'}`,
      `Lap:     ${d.lap ?? '—'}`,
      `x: ${Number(d.x).toFixed(3)}   y: ${Number(d.y).toFixed(3)}`,
    ];
  }

  // ── ZOOM PLUGIN CONFIG ────────────────────────────────────
  const ZOOM_PLUGIN = {
    zoom: {
      drag: { enabled: true, backgroundColor: 'rgba(0,212,255,0.1)', borderColor: 'rgba(0,212,255,0.4)', borderWidth: 1 },
      mode: 'xy',
    },
  };

  // ── READ LIMIT CONTROLS ───────────────────────────────────
  function readLimits(prefix) {
    return {
      yMin: document.getElementById(`${prefix}-ymin`)?.value ?? null,
      yMax: document.getElementById(`${prefix}-ymax`)?.value ?? null,
      clip: document.getElementById(`${prefix}-clip`)?.checked ?? false,
    };
  }

  // ── SCATTER OPTIONS ───────────────────────────────────────
  function scatterOpts(xLabel, yLabel, yMin, yMax, canvasId) {
    const yScale = {
      ...SMP_CONFIG.CHART.SCALE,
      title: { display: true, text: yLabel, color: '#5A6678', font: { size: 9, family: 'JetBrains Mono' } },
    };
    if (yMin !== null && yMin !== '') yScale.min = parseFloat(yMin);
    if (yMax !== null && yMax !== '') yScale.max = parseFloat(yMax);

    return {
      ...SMP_CONFIG.CHART.BASE,
      scales: {
        x: {
          ...SMP_CONFIG.CHART.SCALE,
          title: { display: true, text: xLabel, color: '#5A6678', font: { size: 9, family: 'JetBrains Mono' } },
        },
        y: yScale,
      },
      plugins: {
        ...SMP_CONFIG.CHART.BASE.plugins,
        tooltip: {
          ...SMP_CONFIG.CHART.BASE.plugins.tooltip,
          position: 'nearest',
          xAlign: 'left',
          yAlign: 'center',
          callbacks: { label: tooltipLabel },
        },
        zoom: ZOOM_PLUGIN,
      },
    };
  }

  // ── RESET ZOOM ────────────────────────────────────────────
  function resetZoom(canvasId) {
    if (_charts[canvasId]) _charts[canvasId].resetZoom();
  }

  // ── FALLING SPEED ─────────────────────────────────────────
  function renderFallingSpeed(canvasId, prefix) {
    destroy(canvasId);
    const ctx = document.getElementById(canvasId)?.getContext('2d');
    if (!ctx) return;
    const { yMin, yMax, clip } = readLimits(prefix);
    const datasets = SMP_DATA.sortedFallingSpeed(yMin, yMax, clip);
    if (!datasets.length) return;

    const yScale = { ...SMP_CONFIG.CHART.SCALE,
      title: { display: true, text: 'Max Speed (km/h)', color: '#5A6678', font: { size: 9 } },
    };
    if (!clip) {
      if (yMin !== null && yMin !== '') yScale.min = parseFloat(yMin);
      if (yMax !== null && yMax !== '') yScale.max = parseFloat(yMax);
    }

    _charts[canvasId] = new Chart(ctx, {
      type: 'scatter', data: { datasets },
      options: {
        ...SMP_CONFIG.CHART.BASE,
        scales: {
          x: { ...SMP_CONFIG.CHART.SCALE, type: 'linear',
            title: { display: true, text: 'Rank', color: '#5A6678', font: { size: 9 } },
            ticks: { ...SMP_CONFIG.CHART.SCALE.ticks, stepSize: 1 },
          },
          y: yScale,
        },
        plugins: {
          ...SMP_CONFIG.CHART.BASE.plugins,
          tooltip: {
            ...SMP_CONFIG.CHART.BASE.plugins.tooltip,
            position: 'nearest',
            xAlign: 'left',
            yAlign: 'center',
            callbacks: { label: tooltipLabel },
          },
          zoom: ZOOM_PLUGIN,
        },
      },
    });
  }

  // ── CUSTOM SCATTER ────────────────────────────────────────
  function renderCustomScatter(canvasId, xField, yField, prefix, plotType = 'scatter') {
    destroy(canvasId);
    const ctx = document.getElementById(canvasId)?.getContext('2d');
    if (!ctx) return;
    const { yMin, yMax, clip } = readLimits(prefix);
    const datasets = SMP_DATA.byManufacturer(xField, yField, yMin, yMax, clip);
    if (!datasets.length) return;
    _charts[canvasId] = new Chart(ctx, {
      type: plotType, data: { datasets },
      options: scatterOpts(
        xField.replace(/_/g,' '),
        yField.replace(/_/g,' '),
        clip ? null : yMin,
        clip ? null : yMax,
        canvasId,
      ),
    });
  }

  // ── TAB PLOTS (Excel-driven) ──────────────────────────────
  function renderTabPlots(plotConfigs, xField, canvasPrefix) {
    plotConfigs.forEach((cfg, i) => {
      const id     = `${canvasPrefix}_${i}`;
      const prefix = `${canvasPrefix}_${i}`;
      destroy(id);
      const ctx = document.getElementById(id)?.getContext('2d');
      if (!ctx) return;
      const { yMin, yMax, clip } = readLimits(prefix);
      const datasets = SMP_DATA.byManufacturer(xField, cfg.field, yMin, yMax, clip);
      if (!datasets.length) return;
      const xLabel = xField === 'lap_time' ? 'Lap Time (s)' : 'Lap Number';
      _charts[id] = new Chart(ctx, {
        type: cfg.plotType || 'scatter',
        data: { datasets },
        options: scatterOpts(
          xLabel,
          cfg.title,
          clip ? null : yMin,
          clip ? null : yMax,
          id,
        ),
      });
    });
  }

  // ── SINGLE TAB PLOT REPLOT ────────────────────────────────
  function renderSinglePlot(cfg, xField, canvasId) {
    destroy(canvasId);
    const ctx = document.getElementById(canvasId)?.getContext('2d');
    if (!ctx) return;
    const { yMin, yMax, clip } = readLimits(canvasId);
    const datasets = SMP_DATA.byManufacturer(xField, cfg.field, yMin, yMax, clip);
    if (!datasets.length) return;
    const xLabel = xField === 'lap_time' ? 'Lap Time (s)' : 'Lap Number';
    _charts[canvasId] = new Chart(ctx, {
      type: cfg.plotType || 'scatter',
      data: { datasets },
      options: scatterOpts(xLabel, cfg.title, clip ? null : yMin, clip ? null : yMax, canvasId),
    });
  }

  return {
    renderFallingSpeed,
    renderCustomScatter,
    renderTabPlots,
    renderSinglePlot,
    resetZoom,
    destroy,
  };
})();
