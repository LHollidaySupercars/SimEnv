using System.Windows.Controls;

namespace V8SCTiming.Viewer.Panels;

/// <summary>
/// TrackInfoPanel — displays static track/event data from the Supercars
/// timing feed's &lt;New&gt; snapshot (track-info session event).
/// Ported from ui/views/panels/panel_track_info.js. NOTE: session-event
/// tailing (flag/track-info/etc.) is not yet wired into the Viewer's
/// DbTailService, which currently only polls laps — this panel is a
/// placeholder ready to be filled in once that's added.
/// </summary>
public partial class TrackInfoPanel : UserControl
{
    public TrackInfoPanel()
    {
        InitializeComponent();
    }

    public void SetInfo(string text) => Body.Text = text;
}
