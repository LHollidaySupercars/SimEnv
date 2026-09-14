using System.Windows.Controls;
using ScottPlot;
using V8SCTiming.Core.Models;

namespace V8SCTiming.Viewer.Panels;

/// <summary>
/// SectorVariancePanel — grouped bar chart of standard deviation per sector
/// (S1/S2/S3) for each car. Ported from ui/views/panels/panel_sector_variance.js
/// (outlier threshold of 50s, matching the original, to exclude SC laps etc.).
/// </summary>
public partial class SectorVariancePanel : UserControl
{
    private const double OutlierThresholdS = 50;
    private readonly Dictionary<string, (List<double> S1, List<double> S2, List<double> S3)> _data = new();

    public SectorVariancePanel()
    {
        InitializeComponent();
        Plot.Plot.Title("Sector Variance (Std Dev)");
        Plot.Plot.YLabel("Std Dev (s)");
    }

    public void OnLap(Lap lap)
    {
        if (!_data.TryGetValue(lap.CarNumber, out var d))
        {
            d = (new List<double>(), new List<double>(), new List<double>());
            _data[lap.CarNumber] = d;
        }
        if (lap.S1 is > 0 and < OutlierThresholdS) d.S1.Add(lap.S1.Value);
        if (lap.S2 is > 0 and < OutlierThresholdS) d.S2.Add(lap.S2.Value);
        if (lap.S3 is > 0 and < OutlierThresholdS) d.S3.Add(lap.S3.Value);
        Redraw();
    }

    private static double StdDev(List<double> values)
    {
        if (values.Count < 2) return 0;
        var mean = values.Average();
        return Math.Sqrt(values.Sum(v => (v - mean) * (v - mean)) / (values.Count - 1));
    }

    private void Redraw()
    {
        Plot.Plot.Clear();
        var cars = _data.Keys.OrderBy(c => c).ToList();
        var bars = new List<Bar>();
        var groupWidth = 0.25;
        for (var i = 0; i < cars.Count; i++)
        {
            var d = _data[cars[i]];
            bars.Add(new Bar { Position = i - groupWidth, Value = StdDev(d.S1), FillColor = Colors.SteelBlue });
            bars.Add(new Bar { Position = i, Value = StdDev(d.S2), FillColor = Colors.MediumSeaGreen });
            bars.Add(new Bar { Position = i + groupWidth, Value = StdDev(d.S3), FillColor = Colors.Orange });
        }
        Plot.Plot.Add.Bars(bars.ToArray());
        var ticks = cars.Select((c, i) => new Tick(i, c)).ToArray();
        Plot.Plot.Axes.Bottom.TickGenerator = new ScottPlot.TickGenerators.NumericManual(ticks);
        Plot.Plot.Axes.AutoScale();
        Plot.Refresh();
    }
}
