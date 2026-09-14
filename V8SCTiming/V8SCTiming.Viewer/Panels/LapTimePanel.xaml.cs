using System.Windows.Controls;
using ScottPlot;
using V8SCTiming.Core.Models;

namespace V8SCTiming.Viewer.Panels;

/// <summary>
/// LapTimePanel — lap time line chart, one series per car.
/// Ported from ui/views/panels/panel_laptime.js (Chart.js) to ScottPlot.
/// </summary>
public partial class LapTimePanel : UserControl
{
    private readonly Dictionary<string, List<(double Lap, double Time)>> _series = new();
    private readonly Dictionary<string, Color> _colours = new();
    private readonly Random _rng = new(1);

    public LapTimePanel()
    {
        InitializeComponent();
        Plot.Plot.Title("Lap Times");
        Plot.Plot.XLabel("Lap");
        Plot.Plot.YLabel("Time (s)");
    }

    public void OnLap(Lap lap)
    {
        if (lap.LapTime == null) return; // skip in/out laps, matches original behaviour

        if (!_series.TryGetValue(lap.CarNumber, out var list))
        {
            _series[lap.CarNumber] = list = new List<(double, double)>();
            _colours[lap.CarNumber] = Color.FromColor(System.Drawing.Color.FromArgb(
                255, _rng.Next(60, 230), _rng.Next(60, 230), _rng.Next(60, 230)));
        }
        list.Add((lap.LapNumber, lap.LapTime.Value));
        Redraw();
    }

    private void Redraw()
    {
        Plot.Plot.Clear();
        foreach (var (car, points) in _series)
        {
            var ordered = points.OrderBy(p => p.Lap).ToArray();
            var xs = ordered.Select(p => p.Lap).ToArray();
            var ys = ordered.Select(p => p.Time).ToArray();
            var line = Plot.Plot.Add.Scatter(xs, ys);
            line.LegendText = car;
            line.Color = _colours[car];
        }
        Plot.Plot.ShowLegend();
        Plot.Refresh();
    }
}
