using System.Windows.Controls;
using ScottPlot;
using V8SCTiming.Core.Models;

namespace V8SCTiming.Viewer.Panels;

/// <summary>
/// SectorProgressionPanel — S1/S2/S3 line series vs lap number for a selected car.
/// Ported from ui/views/panels/panel_sector_progression.js.
/// </summary>
public partial class SectorProgressionPanel : UserControl
{
    private readonly Dictionary<string, List<Lap>> _lapsByCar = new();

    public SectorProgressionPanel()
    {
        InitializeComponent();
        Plot.Plot.Title("Sector Progression");
        Plot.Plot.XLabel("Lap");
        Plot.Plot.YLabel("Sector Time (s)");
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
        AddSeries(ordered, l => l.S1, "S1", Colors.SteelBlue);
        AddSeries(ordered, l => l.S2, "S2", Colors.MediumSeaGreen);
        AddSeries(ordered, l => l.S3, "S3", Colors.Orange);
        Plot.Plot.ShowLegend();
        Plot.Plot.Axes.AutoScale();
        Plot.Refresh();
    }

    private void AddSeries(List<Lap> laps, Func<Lap, double?> selector, string label, Color colour)
    {
        var pts = laps.Where(l => selector(l) != null).Select(l => (X: (double)l.LapNumber, Y: selector(l)!.Value)).ToList();
        if (pts.Count == 0) return;
        var line = Plot.Plot.Add.Scatter(pts.Select(p => p.X).ToArray(), pts.Select(p => p.Y).ToArray());
        line.LegendText = label;
        line.Color = colour;
    }
}
