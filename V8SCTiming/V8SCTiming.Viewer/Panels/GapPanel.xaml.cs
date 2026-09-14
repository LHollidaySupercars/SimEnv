using System.Windows.Controls;
using ScottPlot;
using V8SCTiming.Core.Models;

namespace V8SCTiming.Viewer.Panels;

/// <summary>
/// GapPanel — cumulative race-time gap to the race leader, per lap.
/// Ported from ui/views/panels/panel_gap.js. Simplified from the original's
/// reference-car selector to always compare against the current leader
/// (lowest cumulative time), which is the most common use case.
/// </summary>
public partial class GapPanel : UserControl
{
    private readonly Dictionary<string, double> _cumTime = new();
    private readonly Dictionary<string, List<(double Lap, double Gap)>> _series = new();
    private readonly Dictionary<string, Color> _colours = new();
    private readonly Random _rng = new(11);

    public GapPanel()
    {
        InitializeComponent();
        Plot.Plot.Title("Gap to Leader");
        Plot.Plot.XLabel("Lap");
        Plot.Plot.YLabel("Gap (s)");
    }

    public void OnLap(Lap lap)
    {
        if (lap.LapTime == null) return;
        _cumTime[lap.CarNumber] = _cumTime.GetValueOrDefault(lap.CarNumber, 0) + lap.LapTime.Value;

        var leaderTime = _cumTime.Values.Min();
        var gap = _cumTime[lap.CarNumber] - leaderTime;

        if (!_series.TryGetValue(lap.CarNumber, out var list))
        {
            _series[lap.CarNumber] = list = new();
            _colours[lap.CarNumber] = Color.FromColor(System.Drawing.Color.FromArgb(
                255, _rng.Next(60, 230), _rng.Next(60, 230), _rng.Next(60, 230)));
        }
        list.Add((lap.LapNumber, gap));
        Redraw();
    }

    private void Redraw()
    {
        Plot.Plot.Clear();
        foreach (var (car, points) in _series)
        {
            var ordered = points.OrderBy(p => p.Lap).ToArray();
            var line = Plot.Plot.Add.Scatter(ordered.Select(p => p.Lap).ToArray(), ordered.Select(p => p.Gap).ToArray());
            line.LegendText = car;
            line.Color = _colours[car];
        }
        Plot.Plot.ShowLegend();
        Plot.Refresh();
    }
}
