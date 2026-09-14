using System.Collections.ObjectModel;
using System.Windows.Controls;
using V8SCTiming.Core.Models;

namespace V8SCTiming.Viewer.Panels;

/// <summary>
/// PitStopSummaryPanel — one row per pit stop per car, derived from isPitLap
/// laps. Ported from ui/views/panels/panel_pitstop_summary.js (core columns;
/// inline compound/fuel editing left for a later pass).
/// </summary>
public partial class PitStopSummaryPanel : UserControl
{
    public class Row
    {
        public string CarNumber { get; init; } = "";
        public int StopNumber { get; init; }
        public int PitLap { get; init; }
        public int Outing { get; init; }
        public double? PitDuration { get; init; }
        public string? Tyre { get; init; }
    }

    private readonly Dictionary<string, int> _stopCount = new();
    public ObservableCollection<Row> Rows { get; } = new();

    public PitStopSummaryPanel()
    {
        InitializeComponent();
        Grid.ItemsSource = Rows;
    }

    public void OnLap(Lap lap)
    {
        if (!lap.IsPitLap) return;
        var stopNum = _stopCount.GetValueOrDefault(lap.CarNumber, 0) + 1;
        _stopCount[lap.CarNumber] = stopNum;
        Rows.Add(new Row
        {
            CarNumber = lap.CarNumber,
            StopNumber = stopNum,
            PitLap = lap.LapNumber,
            Outing = lap.Outing,
            PitDuration = lap.PitDuration,
            Tyre = lap.Tyre,
        });
    }
}
