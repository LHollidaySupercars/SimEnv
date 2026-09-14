using System.Collections.ObjectModel;
using System.Windows.Controls;
using V8SCTiming.Core.Models;

namespace V8SCTiming.Viewer.Panels;

/// <summary>
/// OvertakesPanel — detects lap-to-lap position swaps between two cars and
/// logs each as an overtake, flagging whether either car was within the pit
/// window (lapsSincePit &lt;= 2) at the time. Ported from
/// ui/views/panels/panel_overtakes.js's lap-level fallback mode (the
/// original's sub-lap Passing-loop sector detection for Supercars data is a
/// follow-up item — see README.md).
/// </summary>
public partial class OvertakesPanel : UserControl
{
    public class Row
    {
        public int Lap { get; init; }
        public string CarA { get; init; } = ""; // now-ahead car
        public string CarB { get; init; } = ""; // now-behind car
        public int PosAfterA { get; init; }
        public int PosAfterB { get; init; }
        public string PitAssisted { get; init; } = "";
    }

    private const int PitWindow = 2;
    private readonly Dictionary<int, Dictionary<string, Lap>> _byLap = new();
    public ObservableCollection<Row> Rows { get; } = new();

    public OvertakesPanel()
    {
        InitializeComponent();
        Grid.ItemsSource = Rows;
    }

    public void OnLap(Lap lap)
    {
        if (lap.Position == null) return;

        if (!_byLap.TryGetValue(lap.LapNumber, out var thisLapPositions))
            _byLap[lap.LapNumber] = thisLapPositions = new();
        thisLapPositions[lap.CarNumber] = lap;

        if (!_byLap.TryGetValue(lap.LapNumber - 1, out var prevLapPositions)) return;

        // Compare this car's position now vs. its position last lap, and find
        // any car that swapped places with it.
        if (!prevLapPositions.TryGetValue(lap.CarNumber, out var prevLap) || prevLap.Position == null) return;
        if (prevLap.Position == lap.Position) return;

        foreach (var (otherCar, otherPrevLap) in prevLapPositions)
        {
            if (otherCar == lap.CarNumber || otherPrevLap.Position == null) continue;
            if (!thisLapPositions.TryGetValue(otherCar, out var otherThisLap) || otherThisLap.Position == null) continue;

            // Overtake: A was behind B last lap, now A is ahead of B.
            var wasBehind = prevLap.Position > otherPrevLap.Position;
            var nowAhead = lap.Position < otherThisLap.Position;
            if (wasBehind && nowAhead)
            {
                var pitAssisted = lap.LapsSincePit <= PitWindow || otherThisLap.LapsSincePit <= PitWindow;
                Rows.Add(new Row
                {
                    Lap = lap.LapNumber,
                    CarA = lap.CarNumber,
                    CarB = otherCar,
                    PosAfterA = lap.Position.Value,
                    PosAfterB = otherThisLap.Position.Value,
                    PitAssisted = pitAssisted ? "Yes" : "No",
                });
            }
        }
    }
}
