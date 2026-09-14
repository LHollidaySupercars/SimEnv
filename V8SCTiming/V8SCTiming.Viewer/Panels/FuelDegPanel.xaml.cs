using System.Windows.Controls;
using ScottPlot;
using V8SCTiming.Core.Models;

namespace V8SCTiming.Viewer.Panels;

/// <summary>
/// FuelDegPanel — tyre degradation scatter: lap time vs laps-since-pit
/// (a proxy for stint progress), one series per car, with a linear
/// regression trendline. Simplified from ui/views/panels/panel_fuel_deg.js
/// (fuel-corrected pace / lap exclusion UI not yet ported).
/// </summary>
public partial class FuelDegPanel : UserControl
{
    private readonly Dictionary<string, List<(double X, double Y)>> _points = new();
    private readonly Dictionary<string, Color> _colours = new();
    private readonly Random _rng = new(13);

    public FuelDegPanel()
    {
        InitializeComponent();
        Plot.Plot.Title("Tyre Degradation (lap time vs. laps since pit)");
        Plot.Plot.XLabel("Laps Since Pit");
        Plot.Plot.YLabel("Lap Time (s)");
    }

    public void OnLap(Lap lap)
    {
        if (lap.LapTime == null || lap.IsPitLap) return;
        if (!_points.TryGetValue(lap.CarNumber, out var list))
        {
            _points[lap.CarNumber] = list = new();
            _colours[lap.CarNumber] = Color.FromColor(System.Drawing.Color.FromArgb(
                255, _rng.Next(60, 230), _rng.Next(60, 230), _rng.Next(60, 230)));
        }
        list.Add((lap.LapsSincePit, lap.LapTime.Value));
        Redraw();
    }

    private void Redraw()
    {
        Plot.Plot.Clear();
        foreach (var (car, points) in _points)
        {
            var xs = points.Select(p => p.X).ToArray();
            var ys = points.Select(p => p.Y).ToArray();
            var scatter = Plot.Plot.Add.ScatterPoints(xs, ys);
            scatter.LegendText = car;
            scatter.Color = _colours[car];

            if (points.Count >= 2)
            {
                var (slope, intercept) = LinearRegression(xs, ys);
                var xMin = xs.Min();
                var xMax = xs.Max();
                var line = Plot.Plot.Add.Line(xMin, slope * xMin + intercept, xMax, slope * xMax + intercept);
                line.Color = _colours[car];
                line.LinePattern = LinePattern.Dashed;
            }
        }
        Plot.Plot.ShowLegend();
        Plot.Refresh();
    }

    private static (double Slope, double Intercept) LinearRegression(double[] xs, double[] ys)
    {
        var n = xs.Length;
        var sumX = xs.Sum();
        var sumY = ys.Sum();
        var sumXY = xs.Zip(ys, (x, y) => x * y).Sum();
        var sumXX = xs.Sum(x => x * x);
        var denom = n * sumXX - sumX * sumX;
        if (Math.Abs(denom) < 1e-9) return (0, ys.Average());
        var slope = (n * sumXY - sumX * sumY) / denom;
        var intercept = (sumY - slope * sumX) / n;
        return (slope, intercept);
    }
}
