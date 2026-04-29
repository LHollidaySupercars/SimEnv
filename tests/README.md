# tests

MATLAB `matlab.unittest` test suite for the SMP data pipeline. Covers both unit-level function tests and end-to-end integration tests against real MoTeC `.ld` files.

---

## Running the Tests

```matlab
% Run everything (CI-compatible — exits with code 1 on failure)
run run_all_tests

% Unit tests only
run run_unit_tests

% Integration tests only
run run_integration_tests
```

`run_all_tests.m` calls `exit(1)` on any failure, making it compatible with CI pipelines (GitHub Actions, Azure DevOps, etc.).

---

## Structure

```
tests/
├── unit/          — Self-contained function tests (no .ld files required)
├── integration/   — End-to-end tests against real .ld test data
├── testData/      — One .ld file per manufacturer (real session data)
└── fixtures/      — Static fixture data (placeholder, currently empty)
```

---

## Unit Tests (`unit/`)

| File | What it tests |
|---|---|
| `test_lap_stats.m` | `lap_stats()` — builds synthetic in-memory lap structs and verifies min/max/mean/std calculations. No `.ld` file required. |
| `test_get_colour.m` | `get_colour()` — verifies correct colour is returned for each manufacturer and driver alias. |
| `test_smp_colours.m` | `smp_colours()` — verifies manufacturer colour config struct is well-formed. |
| `test_smp_filter.m` | `smp_filter()` — verifies filtering logic across event/session/team/manufacturer dimensions. |

---

## Integration Tests (`integration/`)

Each test class loads a real `.ld` file and verifies the full pipeline output (driver name, car number, venue, session, lap count, best lap time to ±0.5 s, presence of key channels).

| File | Manufacturer | Test data source |
|---|---|---|
| `test_compile_ford.m` | Ford | `testData/01_FRD/testData_AGP_T8R_Q6_7.ld` — Car 888, Will Brown, AGP Q6/7 |
| `test_compile_gm.m` | GM (Chevrolet) | `testData/02_GM/testData_AGP_T18_Q6.ld` — AGP Q6 |
| `test_compile_toy.m` | Toyota | `testData/03_TOY/testData_AGP_WAU_Q6.ld` — WAU team, AGP Q6 |
| `test_scan_folders.m` | All | Verifies `smp_scan_folders` correctly discovers `.ld` files in the `testData/` tree. |
| `smp_test_load_and_slice.m` | Shared helper | Shared fixture helper — loads a `.ld` file, slices laps, returns results for assertion. |

All three manufacturer test files are from the 2026 Albert Park Grand Prix (AGP), Qualifying session 6.

---

## Adding New Tests

- **Unit tests:** subclass `matlab.unittest.TestCase`, place in `unit/`, use `verifyEqual`, `verifyTrue`, etc.
- **Integration tests:** follow the pattern in `test_compile_ford.m` — load the relevant `.ld` from `testData/`, call `smp_test_load_and_slice`, assert key properties.
- **New test data:** place one `.ld` file per scenario in a numbered subfolder under `testData/` (e.g., `04_XX/`).
