using System.Windows.Controls;
using ScottPlot;
using V8SCTiming.Core.Models;

namespace V8SCTiming.Viewer.Panels;

/// <summary>
/// SpeedTrapPanel — speed trap readings (km/h) per lap, one series per car.
/// Ported from ui/views/panels/panel_speed_trap.js.
/// </summary>
public partial class SpeedTrapPanel : UserControl
{
    private readonly Dictionary<string, List<(double Lap, double Speed)>> _series = new();
    private readonly Dictionary<string, Color> _colours = new();
    private readonly Random _rng = new(17);

    public SpeedTrapPanel()
    {
        InitializeComponent();
        Plot.Plot.Title("Speed Trap");
        Plot.Plot.XLabel("Lap");
        Plot.Plot.YLabel("Speed (km/h)");
    }

    public void OnLap(Lap lap)
    {
        if (lap.SpeedTrap == null) return;
        if (!_series.TryGetValue(lap.CarNumber, out var list))
        {
            _series[lap.CarNumber] = list = new();
            _colours[lap.CarNumber] = Color.FromColor(System.Drawing.Color.FromArgb(
                255, _rng.Next(60, 230), _rng.Next(60, 230), _rng.Next(60, 230)));
        }
        list.Add((lap.LapNumber, lap.SpeedTrap.Value));
        Redraw();
    }

    private void Redraw()
    {
        Plot.Plot.Clear();
        foreach (var (car, points) in _series)
        {
            var ordered = points.OrderBy(p => p.Lap).ToArray();
            var line = Plot.Plot.Add.Scatter(ordered.Select(p => p.Lap).ToArray(), ordered.Select(p => p.Speed).ToArray());
            line.LegendText = car;
            line.Color = _colours[car];
        }
        Plot.Plot.ShowLegend();
        Plot.Refresh();
    }
}
