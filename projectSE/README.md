# projectSE

Systems and software engineering workspace. Contains infrastructure code for parallel execution of the SMP data pipeline, and reference/experimental scripts.

---

## Sub-folders

### `parallelization/`

MATLAB parallel worker scripts that implement the parallel execution path of the SMP data acquisition pipeline. These are the worker-side counterparts to the entry points in `dataAcquisition/parseEventData/executionScripts/`.

| File | Purpose |
|---|---|
| `smp_compile_parallel_test.m` | Test harness for the parallel compilation workflow — equivalent to `execute_main_report_parallel.m` but isolated for testing. |
| `smp_compile_worker.m` | Per-team parallel worker: loads `.ld` files, computes custom/gated channels, slices laps, and computes lap stats for one team. Called via `parfor` or `parfeval`. |
| `smp_pitstop_worker.m` | Parallel worker for pit stop detection — runs `smp_pitstop_detect` on a single team's data. |
| `smp_save_worker.m` | Parallel worker for saving compiled team data to disk from within a `parfor` block (required because `parfor` workers cannot directly write shared state). |
| `smp_recompute_vch_parallel.m` | Recomputes virtual channel statistics across all teams in parallel. |

**Relationship to the main pipeline:**
The `smp_compile_worker.m` / `smp_pitstop_worker.m` / `smp_save_worker.m` trio is orchestrated by `execute_main_report_parallel.m` in `dataAcquisition/parseEventData/executionScripts/`. A MATLAB Parallel Computing Toolbox licence is required.

---

### `ODE_Example/`

| File | Purpose |
|---|---|
| `ODE_Example/imaginaryODE.m` | Teaching example demonstrating how to integrate an ODE with complex (imaginary) state variables by splitting real/imaginary components into a real-valued state vector. Pedagogical only — not referenced by any production code. |

---

## Notes

- The `parallelization/` workers are kept here rather than inside `dataAcquisition/` to maintain a clean separation between the pipeline library functions and the parallel execution infrastructure.
- Adding new parallel workers: follow the pattern in `smp_compile_worker.m` — accept a single team's data struct as input, process it, and return a result struct. Never write to shared disk paths directly from a worker.
