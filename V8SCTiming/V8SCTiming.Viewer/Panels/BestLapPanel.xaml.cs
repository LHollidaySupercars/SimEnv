using System.Windows.Controls;
using V8SCTiming.Core.Models;

namespace V8SCTiming.Viewer.Panels;

/// <summary>
/// BestLapPanel — horizontal bar chart of each car's best lap, fastest first.
/// Ported from ui/views/panels/panel_best_lap.js.
/// </summary>
public partial class BestLapPanel : UserControl
{
    private readonly Dictionary<string, double> _bestLap = new();

    public BestLapPanel()
    {
        InitializeComponent();
        Plot.Plot.Title("Best Lap Comparison");
        Plot.Plot.XLabel("Time (s)");
    }

    public void OnLap(Lap lap)
    {
        if (lap.LapTime == null || lap.IsPitLap) return;
        var key = lap.CarNumber;
        if (!_bestLap.TryGetValue(key, out var cur) || lap.LapTime < cur)
        {
            _bestLap[key] = lap.LapTime.Value;
            Redraw();
        }
    }

    private void Redraw()
    {
        Plot.Plot.Clear();
        var ordered = _bestLap.OrderBy(kv => kv.Value).ToList();
        var bars = ordered.Select((kv, i) => new ScottPlot.Bar
        {
            Position = i,
            Value = kv.Value,
            Orientation = ScottPlot.Orientation.Horizontal,
        }).ToArray();
        Plot.Plot.Add.Bars(bars);
        var ticks = ordered.Select((kv, i) => new ScottPlot.Tick(i, kv.Key)).ToArray();
        Plot.Plot.Axes.Left.TickGenerator = new ScottPlot.TickGenerators.NumericManual(ticks);
        Plot.Plot.Axes.AutoScale();
        Plot.Refresh();
    }
}
