# V8SC Timing — Native Windows Edition

A native Windows rewrite of the original Electron/Mac `v8sc-timing` app, built with
**WPF (.NET 8, C#)** — no Electron, no Chromium runtime. Consists of two programs
sharing one SQLite database:

- **V8SCTiming.Logger** — a standalone, always-on background process. Connects to
  a configured timing feed (Supercars TCP live feed, OpenF1 REST API, or a saved
  replay file) and is the **sole writer** to the shared SQLite database. It
  archives every raw message it receives (`raw_messages` table) plus every parsed
  lap/passing, so it keeps recording whether or not the Viewer is open.
- **V8SCTiming.Viewer** — the WPF desktop app you interact with. It only ever
  **reads** from the same SQLite database (via WAL-mode polling), so there's never
  a conflict over who owns the data.

## Solution layout

```
V8SCTiming.sln
V8SCTiming.Core/      Shared library: feed adapters, SQLite access, config loaders
V8SCTiming.Logger/    Console app — run this first, leave it running during a session
V8SCTiming.Viewer/    WPF app — the timing display
config/               cars.json, profiles.json, tracks/, championships.json (same format as the original)
publish/              Self-contained win-x64 builds (see "Publishing" below)
```

## Running from source

```powershell
# 1. Start the Logger against a profile from config/profiles.json (e.g. "supercars-live", "openf1-live", "replay")
cd V8SCTiming.Logger
dotnet run -- supercars-live ..\config ..\v8sctiming.db

# 2. In another terminal, start the Viewer (reads the same v8sctiming.db)
cd V8SCTiming.Viewer
dotnet run
```

The Viewer's session dropdown lists every session the Logger has ever recorded
(open or closed) — pick one to live-tail it or review it after the fact.

## Publishing a distributable build

```powershell
dotnet publish V8SCTiming.Logger -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true -o publish\Logger
dotnet publish V8SCTiming.Viewer -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true -o publish\Viewer
```

Copy `config/` next to each published `.exe` (already done for you in this repo's
`publish/` folder). No .NET runtime install is required on the target machine —
everything is bundled into the single `.exe`.

## Current panel coverage

Ported and verified end-to-end (Logger → SQLite → Viewer, live-tailing):
**Scoreboard, Lap Times, Best Lap, Position, Pit Stops.**

The original Mac app has ~20 panels total. The remaining ones (Gap, Distribution,
Fuel Calc, Fuel/Deg, Pit Impact, Sector Breakdown/Progression/Variance, Speed Trap,
Strategy, Summary, Track Info, Undercut, Overtakes, Ants) are not yet ported. The
architecture is established — each panel is a small `UserControl` with an
`OnLap(Lap)` method wired into a `MainWindow` tab — so `Panels/ScoreboardPanel.*`
or `Panels/BestLapPanel.*` are good templates for adding the rest.

## Data sources

See the original `DATA_SOURCES.md` and `TIMING_FEED.md` in `D:\v8sc-timing-main`
for the field-reliability notes (outing, isPitLap conventions, etc.) — the C#
adapters preserve the same quirks/derivations documented there.
