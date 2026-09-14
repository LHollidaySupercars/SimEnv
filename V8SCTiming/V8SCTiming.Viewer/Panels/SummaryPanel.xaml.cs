using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Windows.Controls;
using V8SCTiming.Core.Models;

namespace V8SCTiming.Viewer.Panels;

/// <summary>
/// SummaryPanel — per-driver best/avg/worst/std-dev lap time, best sectors,
/// top speed. Ported from ui/views/panels/panel_summary.js (column-sort UI
/// not yet ported).
/// </summary>
public partial class SummaryPanel : UserControl
{
    public class Row : INotifyPropertyChanged
    {
        public event PropertyChangedEventHandler? PropertyChanged;
        private void Raise(string name) => PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(name));

        public string CarNumber { get; init; } = "";
        public List<double> Laps { get; } = new();

        private double? _bestS1, _bestS2, _bestS3, _topSpeed;
        public double? BestS1 { get => _bestS1; set { _bestS1 = value; Raise(nameof(BestS1)); } }
        public double? BestS2 { get => _bestS2; set { _bestS2 = value; Raise(nameof(BestS2)); } }
        public double? BestS3 { get => _bestS3; set { _bestS3 = value; Raise(nameof(BestS3)); } }
        public double? TopSpeed { get => _topSpeed; set { _topSpeed = value; Raise(nameof(TopSpeed)); } }

        public double? Best => Laps.Count > 0 ? Laps.Min() : null;
        public double? Avg => Laps.Count > 0 ? Laps.Average() : null;
        public double? Worst => Laps.Count > 0 ? Laps.Max() : null;
        public double? StdDev
        {
            get
            {
                if (Laps.Count < 2) return null;
                var mean = Laps.Average();
                return Math.Sqrt(Laps.Sum(v => (v - mean) * (v - mean)) / (Laps.Count - 1));
            }
        }
        public int Count => Laps.Count;

        public void Refresh()
        {
            Raise(nameof(Best)); Raise(nameof(Avg)); Raise(nameof(Worst)); Raise(nameof(StdDev)); Raise(nameof(Count));
        }
    }

    private readonly Dictionary<string, Row> _rows = new();
    public ObservableCollection<Row> Rows { get; } = new();

    public SummaryPanel()
    {
        InitializeComponent();
        Grid.ItemsSource = Rows;
    }

    public void OnLap(Lap lap)
    {
        if (!_rows.TryGetValue(lap.CarNumber, out var row))
        {
            row = new Row { CarNumber = lap.CarNumber };
            _rows[lap.CarNumber] = row;
            Rows.Add(row);
        }

        if (lap.LapTime != null && !lap.IsPitLap) row.Laps.Add(lap.LapTime.Value);
        if (lap.S1 != null && (row.BestS1 == null || lap.S1 < row.BestS1)) row.BestS1 = lap.S1;
        if (lap.S2 != null && (row.BestS2 == null || lap.S2 < row.BestS2)) row.BestS2 = lap.S2;
        if (lap.S3 != null && (row.BestS3 == null || lap.S3 < row.BestS3)) row.BestS3 = lap.S3;
        if (lap.SpeedTrap != null && (row.TopSpeed == null || lap.SpeedTrap > row.TopSpeed)) row.TopSpeed = lap.SpeedTrap;
        row.Refresh();
    }
}
