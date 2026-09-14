using System.Collections.ObjectModel;
using System.Windows.Controls;
using V8SCTiming.Core.Models;

namespace V8SCTiming.Viewer.Panels;

/// <summary>
/// UndercutPanel — simplified undercut readiness view: each car's rolling
/// last-5-lap average and best recent lap, useful for eyeballing whether a
/// car has the pace advantage needed for an undercut to work.
///
/// This is a substantially simplified version of the original
/// ui/views/panels/panel_undercut.js, which ran a full two-car pit-strategy
/// simulation (fuel/tyre-service time models, warm-up deltas, phase-based
/// gap projection) driven by manual "Car A / Car B / stop type" selection.
/// That simulation UI is a follow-up item — this view provides the
/// underlying pace data needed to reason about it manually in the meantime.
/// </summary>
public partial class UndercutPanel : UserControl
{
    public class Row
    {
        public string CarNumber { get; init; } = "";
        public double? Last5Avg { get; set; }
        public double? BestRecent { get; set; }
    }

    private readonly Dictionary<string, List<double>> _recentLaps = new();
    private readonly Dictionary<string, Row> _rows = new();
    public ObservableCollection<Row> Rows { get; } = new();

    public UndercutPanel()
    {
        InitializeComponent();
        Grid.ItemsSource = Rows;
    }

    public void OnLap(Lap lap)
    {
        if (lap.LapTime == null || lap.IsPitLap) return;

        if (!_recentLaps.TryGetValue(lap.CarNumber, out var list))
        {
            _recentLaps[lap.CarNumber] = list = new();
            var row = new Row { CarNumber = lap.CarNumber };
            _rows[lap.CarNumber] = row;
            Rows.Add(row);
        }
        list.Add(lap.LapTime.Value);
        if (list.Count > 5) list.RemoveAt(0);

        var r = _rows[lap.CarNumber];
        r.Last5Avg = list.Average();
        r.BestRecent = list.Min();
        Grid.Items.Refresh();
    }
}
