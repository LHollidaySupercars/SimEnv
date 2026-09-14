using System.Windows.Controls;
using ScottPlot;
using V8SCTiming.Core.Models;

namespace V8SCTiming.Viewer.Panels;

/// <summary>
/// AntsPanel — simplified track-position visualization: each car is placed
/// on a circle, ordered by current race position, updated as laps complete.
///
/// This is a significant simplification of the original
/// ui/views/panels/panel_ants.js, which animated cars continuously along a
/// GPS-derived track outline (or a loop-distance proportional circle)
/// between individual timing-loop crossings, using Passing event
/// interpolation. That requires per-passing live tailing (not yet wired —
/// the Viewer currently only tails completed laps) plus GPS/loop-distance
/// track config parsing. This view gives an immediate, if coarse,
/// "who's near whom on track" snapshot updated once per lap.
/// </summary>
public partial class AntsPanel : UserControl
{
    private readonly Dictionary<string, int> _position = new();
    private readonly Dictionary<string, Color> _colours = new();
    private readonly Random _rng = new(23);

    public AntsPanel()
    {
        InitializeComponent();
        Plot.Plot.Title("Track Position (lap-level snapshot)");
        Plot.Plot.Axes.Left.TickGenerator = new ScottPlot.TickGenerators.NumericManual(Array.Empty<Tick>());
        Plot.Plot.Axes.Bottom.TickGenerator = new ScottPlot.TickGenerators.NumericManual(Array.Empty<Tick>());
        Plot.Plot.HideGrid();
    }

    public void OnLap(Lap lap)
    {
        if (lap.Position == null) return;
        _position[lap.CarNumber] = lap.Position.Value;
        if (!_colours.ContainsKey(lap.CarNumber))
        {
            _colours[lap.CarNumber] = Color.FromColor(System.Drawing.Color.FromArgb(
                255, _rng.Next(60, 230), _rng.Next(60, 230), _rng.Next(60, 230)));
        }
        Redraw();
    }

    private void Redraw()
    {
        Plot.Plot.Clear();

        // Draw the circular track outline.
        var circleXs = new double[361];
        var circleYs = new double[361];
        for (var i = 0; i <= 360; i++)
        {
            var rad = i * Math.PI / 180.0;
            circleXs[i] = Math.Cos(rad);
            circleYs[i] = Math.Sin(rad);
        }
        var outline = Plot.Plot.Add.Scatter(circleXs, circleYs);
        outline.LineWidth = 2;
        outline.MarkerSize = 0;
        outline.Color = Colors.Gray;

        var ordered = _position.OrderBy(kv => kv.Value).ToList();
        var n = Math.Max(1, ordered.Count);
        for (var i = 0; i < ordered.Count; i++)
        {
            var (car, _) = ordered[i];
            var frac = (double)i / n;
            var rad = frac * 2 * Math.PI - Math.PI / 2; // start at top, go clockwise
            var x = Math.Cos(rad);
            var y = Math.Sin(rad);
            var marker = Plot.Plot.Add.Marker(x, y);
            marker.Color = _colours[car];
            marker.Size = 14;
            marker.MarkerShape = MarkerShape.FilledCircle;

            var label = Plot.Plot.Add.Text(car, x * 1.15, y * 1.15);
            label.LabelFontColor = _colours[car];
        }

        Plot.Plot.Axes.SetLimits(-1.5, 1.5, -1.5, 1.5);
        Plot.Refresh();
    }
}
