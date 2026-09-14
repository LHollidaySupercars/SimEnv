using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Windows.Controls;
using V8SCTiming.Core.Models;

namespace V8SCTiming.Viewer.Panels;

/// <summary>
/// ScoreboardPanel — per-car best sector times, theoretical best, and last lap.
/// Ported from ui/views/panels/panel_scoreboard.js. Column-toggle UI is left
/// for a later pass; core best-of tracking and live update behaviour matches
/// the original.
/// </summary>
public partial class ScoreboardPanel : UserControl, INotifyPropertyChanged
{
    public event PropertyChangedEventHandler? PropertyChanged;

    public class Row : INotifyPropertyChanged
    {
        public event PropertyChangedEventHandler? PropertyChanged;
        private void Raise(string name) => PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(name));

        public string CarNumber { get; init; } = "";
        private string? _driver;
        public string? Driver { get => _driver; set { _driver = value; Raise(nameof(Driver)); } }
        private double? _bestS1;
        public double? BestS1 { get => _bestS1; set { _bestS1 = value; Raise(nameof(BestS1)); } }
        private double? _bestS2;
        public double? BestS2 { get => _bestS2; set { _bestS2 = value; Raise(nameof(BestS2)); } }
        private double? _bestS3;
        public double? BestS3 { get => _bestS3; set { _bestS3 = value; Raise(nameof(BestS3)); } }
        public double? TheoBest => (BestS1 != null && BestS2 != null && BestS3 != null) ? BestS1 + BestS2 + BestS3 : null;
        private double? _lastLap;
        public double? LastLap { get => _lastLap; set { _lastLap = value; Raise(nameof(LastLap)); Raise(nameof(TheoBest)); } }
    }

    private readonly Dictionary<string, Row> _rows = new();
    public ObservableCollection<Row> Rows { get; } = new();

    public ScoreboardPanel()
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

        if (lap.S1 != null && (row.BestS1 == null || lap.S1 < row.BestS1)) row.BestS1 = lap.S1;
        if (lap.S2 != null && (row.BestS2 == null || lap.S2 < row.BestS2)) row.BestS2 = lap.S2;
        if (lap.S3 != null && (row.BestS3 == null || lap.S3 < row.BestS3)) row.BestS3 = lap.S3;
        if (lap.LapTime != null) row.LastLap = lap.LapTime;
        if (lap.DriverName != null) row.Driver = lap.DriverName;
    }
}
