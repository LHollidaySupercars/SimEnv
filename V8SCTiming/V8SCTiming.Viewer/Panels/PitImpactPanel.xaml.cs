using System.Windows.Controls;
using ScottPlot;
using V8SCTiming.Core.Models;

namespace V8SCTiming.Viewer.Panels;

/// <summary>
/// PitImpactPanel — lap-time trajectory before/after each pit stop for a
/// selected car, one series per stop (X = laps relative to the pit lap).
/// Ported from ui/views/panels/panel_pit_impact.js (fixed window of 4 laps
/// either side; the original's adjustable window control is a follow-up).
/// </summary>
public partial class PitImpactPanel : UserControl
{
    private const int Window = 4;
    private readonly Dictionary<string, List<Lap>> _lapsByCar = new();

    public PitImpactPanel()
    {
        InitializeComponent();
        Plot.Plot.Title("Pit Stop Impact");
        Plot.Plot.XLabel("Laps Relative to Pit Stop");
        Plot.Plot.YLabel("Lap Time (s)");
    }

    public void OnLap(Lap lap)
    {
        if (!_lapsByCar.TryGetValue(lap.CarNumber, out var list))
        {
            _lapsByCar[lap.CarNumber] = list = new();
            CarCombo.Items.Add(lap.CarNumber);
            if (CarCombo.SelectedItem == null) CarCombo.SelectedItem = lap.CarNumber;
        }
        list.Add(lap);
        if ((string?)CarCombo.SelectedItem == lap.CarNumber) Redraw();
    }

    private void Refresh(object sender, SelectionChangedEventArgs e) => Redraw();

    private void Redraw()
    {
        Plot.Plot.Clear();
        if (CarCombo.SelectedItem is not string car || !_lapsByCar.TryGetValue(car, out var laps))
        {
            Plot.Refresh();
            return;
        }

        var ordered = laps.OrderBy(l => l.LapNumber).ToList();
        var pitLaps = ordered.Where(l => l.IsPitLap).Select(l => l.LapNumber).ToList();

        var stopIdx = 0;
        foreach (var pitLap in pitLaps)
        {
            stopIdx++;
            var window = ordered.Where(l => l.LapNumber >= pitLap - Window && l.LapNumber <= pitLap + Window && l.LapTime != null).ToList();
            if (window.Count == 0) continue;
            var xs = window.Select(l => (double)(l.LapNumber - pitLap)).ToArray();
            var ys = window.Select(l => l.LapTime!.Value).ToArray();
            var line = Plot.Plot.Add.Scatter(xs, ys);
            line.LegendText = $"Stop {stopIdx} (lap {pitLap})";
        }
        Plot.Plot.ShowLegend();
        Plot.Plot.Axes.AutoScale();
        Plot.Refresh();
    }
}
