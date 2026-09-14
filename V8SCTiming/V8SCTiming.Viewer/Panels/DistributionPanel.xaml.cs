using System.Windows.Controls;
using V8SCTiming.Core.Models;

namespace V8SCTiming.Viewer.Panels;

/// <summary>
/// DistributionPanel — histogram of lap times for a selected car.
/// Ported from ui/views/panels/panel_distribution.js (fixed 0.5s bin width).
/// </summary>
public partial class DistributionPanel : UserControl
{
    private const double BinWidth = 0.5;
    private readonly Dictionary<string, List<double>> _lapsByCar = new();
    private readonly List<string> _carOrder = new();

    public DistributionPanel()
    {
        InitializeComponent();
        Plot.Plot.Title("Lap Time Distribution");
        Plot.Plot.XLabel("Lap Time (s)");
        Plot.Plot.YLabel("Count");
    }

    public void OnLap(Lap lap)
    {
        if (lap.LapTime == null || lap.IsPitLap) return;
        if (!_lapsByCar.TryGetValue(lap.CarNumber, out var list))
        {
            _lapsByCar[lap.CarNumber] = list = new();
            _carOrder.Add(lap.CarNumber);
            CarCombo.Items.Add(lap.CarNumber);
            if (CarCombo.SelectedItem == null) CarCombo.SelectedItem = lap.CarNumber;
        }
        list.Add(lap.LapTime.Value);
        if ((string?)CarCombo.SelectedItem == lap.CarNumber) Redraw();
    }

    private void CarCombo_SelectionChanged(object sender, SelectionChangedEventArgs e) => Redraw();

    private void Redraw()
    {
        Plot.Plot.Clear();
        if (CarCombo.SelectedItem is not string car || !_lapsByCar.TryGetValue(car, out var times) || times.Count == 0)
        {
            Plot.Refresh();
            return;
        }

        var min = Math.Floor(times.Min() / BinWidth) * BinWidth;
        var max = Math.Ceiling(times.Max() / BinWidth) * BinWidth;
        var binCount = Math.Max(1, (int)((max - min) / BinWidth));
        var counts = new double[binCount];
        foreach (var t in times)
        {
            var idx = Math.Min(binCount - 1, (int)((t - min) / BinWidth));
            counts[idx]++;
        }
        var xs = Enumerable.Range(0, binCount).Select(i => min + i * BinWidth + BinWidth / 2).ToArray();
        Plot.Plot.Add.Bars(xs, counts);
        Plot.Plot.Axes.AutoScale();
        Plot.Refresh();
    }
}
