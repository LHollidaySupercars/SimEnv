using System.Windows.Controls;
using ScottPlot;
using V8SCTiming.Core.Models;

namespace V8SCTiming.Viewer.Panels;

/// <summary>
/// PositionPanel — race position vs lap number, one line per car.
/// Ported from ui/views/panels/panel_position.js (Y-axis inverted so P1 is at top).
/// </summary>
public partial class PositionPanel : UserControl
{
    private readonly Dictionary<string, List<(double Lap, double Pos)>> _series = new();
    private readonly Dictionary<string, Color> _colours = new();
    private readonly Random _rng = new(7);

    public PositionPanel()
    {
        InitializeComponent();
        Plot.Plot.Title("Race Position");
        Plot.Plot.XLabel("Lap");
        Plot.Plot.YLabel("Position");
        Plot.Plot.Axes.InvertY(); // P1 at top, matching the original chart
    }

    public void OnLap(Lap lap)
    {
        if (lap.Position == null) return;
        if (!_series.TryGetValue(lap.CarNumber, out var list))
        {
            _series[lap.CarNumber] = list = new();
            _colours[lap.CarNumber] = Color.FromColor(System.Drawing.Color.FromArgb(
                255, _rng.Next(60, 230), _rng.Next(60, 230), _rng.Next(60, 230)));
        }
        list.Add((lap.LapNumber, lap.Position.Value));
        Redraw();
    }

    private void Redraw()
    {
        Plot.Plot.Clear();
        foreach (var (car, points) in _series)
        {
            var ordered = points.OrderBy(p => p.Lap).ToArray();
            var line = Plot.Plot.Add.Scatter(ordered.Select(p => p.Lap).ToArray(), ordered.Select(p => p.Pos).ToArray());
            line.LegendText = car;
            line.Color = _colours[car];
        }
        Plot.Plot.ShowLegend();
        Plot.Refresh();
    }
}
