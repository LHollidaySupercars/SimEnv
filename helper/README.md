# helper

A collection of standalone interactive analysis tools, GUI applications, and debug scripts. These are not part of the main SMP data pipeline — they are used ad-hoc for investigation, diagnostics, and visualisation during development or race weekend analysis.

---

## Files

| File | Purpose |
|---|---|
| `align_to.m` | Resamples a channel onto another channel's time base (nearest-neighbour or linear interpolation; binary-safe). |
| `binary_browser.m` | Raw binary file browser — useful for inspecting unknown file formats. |
| `diagnose_channels.m` | Deep MoTeC `.ld` binary diagnostic. Dumps hex content and all channel values to `C:\temp\channel_diagnose.txt`. Used when `motec_ld_reader` fails to parse a file correctly. |
| `singleLapInvestigation.m` | Script to load a `.ld` file, slice laps, find the fastest lap, and plot damper PSD spectra. Entry point for one-off single-lap deep dives. |
| `visualizeVehicleGeometry.m` | Vehicle geometry visualisation — plots suspension hardpoint positions in 3D. |
| `visualizeVehicleGeometryApp.m` | Interactive MATLAB App version of the vehicle geometry visualiser. |

### `debuggingScript/`

Scripts used during specific debugging investigations, kept for reference.

| File | Purpose |
|---|---|
| `debuggingScript/tyreRadius/tyreRadiusPlots.m` | Debug plots comparing virtual channel rolling radius against raw wheel speed and force channels using live `.ld` session data. Requires a `data` struct already loaded in the workspace. |

---

## Notes

- None of these files are called by the main pipeline (`parseEventData`, `serverInteraction`, etc.).
- Files here require data to already be loaded in the MATLAB workspace or a specific file path to be set before running.
- `align_to.m` is a utility that may be useful across multiple projects.
