using System.Windows.Controls;
using ScottPlot;
using V8SCTiming.Core.Models;

namespace V8SCTiming.Viewer.Panels;

/// <summary>
/// SectorBreakdownPanel — stacked bar chart per lap: S1 + S2 + S3.
/// Ported from ui/views/panels/panel_sector_breakdown.js.
/// </summary>
public partial class SectorBreakdownPanel : UserControl
{
    private readonly Dictionary<string, List<Lap>> _lapsByCar = new();

    public SectorBreakdownPanel()
    {
        InitializeComponent();
        Plot.Plot.Title("Sector Time Breakdown");
        Plot.Plot.XLabel("Lap");
        Plot.Plot.YLabel("Time (s)");
    }

    public void OnLap(Lap lap)
    {
        if (lap.IsPitLap || lap.S1 == null || lap.S2 == null || lap.S3 == null) return;
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
        var s1Bars = new List<Bar>();
        var s2Bars = new List<Bar>();
        var s3Bars = new List<Bar>();
        foreach (var lap in ordered)
        {
            s1Bars.Add(new Bar { Position = lap.LapNumber, Value = lap.S1!.Value, ValueBase = 0, FillColor = Colors.SteelBlue });
            s2Bars.Add(new Bar { Position = lap.LapNumber, Value = lap.S1.Value + lap.S2!.Value, ValueBase = lap.S1.Value, FillColor = Colors.MediumSeaGreen });
            s3Bars.Add(new Bar { Position = lap.LapNumber, Value = lap.S1.Value + lap.S2.Value + lap.S3!.Value, ValueBase = lap.S1.Value + lap.S2.Value, FillColor = Colors.Orange });
        }
        Plot.Plot.Add.Bars(s1Bars.ToArray());
        Plot.Plot.Add.Bars(s2Bars.ToArray());
        Plot.Plot.Add.Bars(s3Bars.ToArray());
        Plot.Plot.Axes.AutoScale();
        Plot.Refresh();
    }
}
