using System.Windows;
using System.Windows.Controls;
using V8SCTiming.Core.Models;

namespace V8SCTiming.Viewer.Panels;

/// <summary>
/// FuelCalcPanel — fuel sensitivity calculator (s/kg).
/// Ported from ui/views/panels/panel_fuel_calc.js. Formula:
///   sensitivity = |lapTime_A - lapTime_B| / fuel_used_kg
/// </summary>
public partial class FuelCalcPanel : UserControl
{
    private readonly Dictionary<string, List<Lap>> _lapsByCar = new();

    public FuelCalcPanel()
    {
        InitializeComponent();
    }

    public void OnLap(Lap lap)
    {
        if (lap.LapTime == null) return;
        if (!_lapsByCar.TryGetValue(lap.CarNumber, out var list))
        {
            _lapsByCar[lap.CarNumber] = list = new();
            CarCombo.Items.Add(lap.CarNumber);
        }
        list.Add(lap);

        if ((string?)CarCombo.SelectedItem == lap.CarNumber) RefreshLapCombos();
    }

    private void Recalculate(object sender, RoutedEventArgs e)
    {
        if (sender == CarCombo) RefreshLapCombos();

        if (CarCombo.SelectedItem is not string car || !_lapsByCar.TryGetValue(car, out var laps))
        {
            ResultText.Text = "";
            return;
        }
        if (LapACombo.SelectedItem is not int lapA || LapBCombo.SelectedItem is not int lapB
            || !double.TryParse(FuelInput.Text, out var fuelKg) || fuelKg <= 0)
        {
            ResultText.Text = "";
            return;
        }

        var timeA = laps.FirstOrDefault(l => l.LapNumber == lapA)?.LapTime;
        var timeB = laps.FirstOrDefault(l => l.LapNumber == lapB)?.LapTime;
        if (timeA == null || timeB == null) { ResultText.Text = "—"; return; }

        var sensitivity = Math.Abs(timeA.Value - timeB.Value) / fuelKg;
        ResultText.Text = $"{sensitivity:0.000} s/kg";
    }

    private void RefreshLapCombos()
    {
        if (CarCombo.SelectedItem is not string car || !_lapsByCar.TryGetValue(car, out var laps)) return;
        var lapNumbers = laps.Select(l => l.LapNumber).Distinct().OrderBy(n => n).ToList();
        LapACombo.ItemsSource = lapNumbers;
        LapBCombo.ItemsSource = lapNumbers;
    }
}
