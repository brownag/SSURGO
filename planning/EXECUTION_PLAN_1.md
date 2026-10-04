# SSURGO Pipeline Robustness Plan

## Goal & Scope

**Goal:**  
Rebuild the SSURGO targets pipeline to be robust against download failures, reuse existing data (3292/3385 SSAs already downloaded), and separate data validation from pipeline execution. Remove download tasks from the targets DAG to prevent wasteful re-downloads on pipeline restarts.

**In scope:**
- Download missing 93 SSAs (26 SC, 67 SD) via standalone script
- Create pre-pipeline data validation (`ensure_data.R`)
- Remove `ssa`, `ssa_combined`, `ssa_files` download-based targets from SSURGO.R
- Replace with single tar_target that reads from data/ and validates completeness
- Rebuild targets metadata from existing data/ without re-downloading
- Ensure pipeline is idempotent: data validation → pipeline execution (two explicit steps)

**Out of scope (explicit deferrals):**
- Modifying soilDB or downloadSSURGO internals
- Refactoring downstream SSURGO processing (createSSURGO, duckdb, spatial ops)
- Full end-to-end testing of all 3385 SSAs post-download
- Parallel download optimization

**Constraints (verbatim from user):**
- "take download_ssurgo out of the pipeline"
- "relying on a script that gets and confirms complete data/ before beginning"
- "sequential" download (do not parallelize)

---

## Decision Log

| Date | Decision | Rationale |
|------|----------|-----------|
| 2026-10-02 | Delete incomplete `_targets/` and rebuild | Previous run was killed mid-execution; metadata corrupted. Clean rebuild ensures consistency. |
| 2026-10-02 | Download missing SSAs sequentially | Sequential is more reliable; parallel would waste public resources. |
| 2026-10-02 | Two-step workflow: `ensure_data.R`, then `SSURGO.R` | Explicit separation allows inspection between steps, easier debugging, clear failure points. |
| 2026-10-02 | Single tar_target for data validation (not branched) | Simpler than 60-state branching; reads from data/ instead of downloading. |
| 2026-10-02 | New target returns file paths (backward compatible) | Downstream tasks need minimal changes; same contract as old `ssa_files`. |
| 2026-10-02 | Add documentation block to SSURGO.R | Explain two-step workflow and lessons learned to prevent future confusion. |

---

## Wave Table & Task DAG

**Single wave, two independent pipelines (sequential user execution):**

```
Wave 1: Data Validation
├── ensure_data (script, standalone)
│   └── Pre-condition: data/ exists with 3292+ SSAs
│   └── Action: download missing 93, validate completeness
│   └── Output: exit 0 if all 3385 present; exit 1 if failures
│
Wave 2: Targets Pipeline (runs after Wave 1 succeeds)
├── ssa_list (tar_target, reads data/)
│   └── Pre-condition: ensure_data completed successfully
│   └── Action: list all data/*/wss_*.zip, validate 3385 count
│   └── Output: character vector of file paths
├── ssa_files (tar_files, wraps ssa_list)
├── ssurgo_create_duckdb → ssurgo_duckdb → ... (downstream)
```

---

## Task Specifications

### Task 1: ensure_data.R (pre-pipeline script)

**File:** `R/ensure_data.R`  
**Type:** Standalone R script (not a targets task)  
**Execution:** `Rscript R/ensure_data.R`

**Spec:**
- Read expected SSAs via `get_area_symbols()` (3385 total, excludes US + MXNL001)
- Check downloaded directories in `data/` (currently 3292)
- Identify missing SSAs (93: 26 SC, 67 SD)
- Download missing sequentially via `download_ssurgo()` with error handling
- Validate final state: all 3385 directories present
- Exit 0 if complete; exit 1 + stderr message if any download failed

**Constraints:**
- Do not parallelize downloads
- Do not modify soilDB or downloadSSURGO
- Do not update targets metadata
- Log each download with area symbol and outcome

**Reference implementation:** `R/ensure_data.R` (already created)

**Acceptance:**
```bash
Rscript R/ensure_data.R
# Exit code 0, final message: "✓ Validation passed. All 3385 SSAs present."
```

---

### Task 2: Update SSURGO.R — replace download targets with data reader

**File:** `SSURGO.R`  
**Type:** Targets script modification  
**Changes needed:**
1. Delete lines defining `ssa`, `ssa_combined`, `ssa_files` targets
2. Add new `ssa_list` tar_target that:
   - Lists all `data/*/wss_*_*.zip` files
   - Validates count == 3385
   - Returns sorted character vector of paths
   - Depends on nothing (assumes data/ is pre-populated)
3. Replace `ssa_files` dependency in downstream targets with `ssa_list`
4. Add comment block (5-10 lines) explaining two-step workflow

**Files in scope:**
- `SSURGO.R` (lines 26-31: ssa/ssa_combined/ssa_files targets)
- Downstream target dependencies (search for `ssa_files`)

**Grep anchor:**
```
tar_target(name = ssa,
tar_files(ssa_files, ssa_combined)
```

**Spec prose:**
Replace branched download architecture with simple data reader. New `ssa_list` target:
```r
tar_target(ssa_list, {
  # List all downloaded SSURGO ZIP files
  files <- list.files("data", pattern = "^wss_.*\\.zip$", 
                      recursive = TRUE, full.names = TRUE)
  if (length(files) != 3385) {
    stop(sprintf("Expected 3385 ZIP files, found %d. Run ensure_data.R first.", 
                 length(files)))
  }
  sort(files)
})
```

**Constraints:**
- Do not modify download_ssurgo.R or soilDB calls
- Do not refactor downstream tasks (createSSURGO, etc.)
- Keep ssa_files as tar_files wrapper for backward compat

**Acceptance:**
```bash
Rscript R/ensure_data.R  # Passes
targets::tar_make()      # Succeeds with new ssa_list target
targets::tar_read(ssa_list) # Returns character vector, length 3385
```

---

### Task 3: Add documentation comment to SSURGO.R

**File:** `SSURGO.R` (top section, before tar_script)  
**Type:** Comment block  
**Content:** (5-10 lines) explaining:
- Why data validation is separate (robustness, no re-downloads)
- Two-step workflow: `Rscript R/ensure_data.R` first, then `targets::tar_make()`
- Lesson: incomplete runs (e.g., killed mid-execution) left targets metadata inconsistent; pre-validation prevents this

**Acceptance:**  
Comment is present and accurate

---

## Hazard Notes (from recon)

1. **Incomplete _targets/ from killed run:** Deleted before Phase 4. Fresh rebuild will be clean.
2. **Network sensitivity:** `ensure_data.R` depends on soilDB connectivity. If WSS is down, script will fail with clear error message.
3. **File I/O race:** If data/ is modified between `ensure_data.R` check and `tar_make()` start, count may drift. Accepted risk (user controls two-step execution).
4. **3379 vs 3385 discrepancy:** Data currently has 3379 directories but expects 3385. `ensure_data.R` validates and downloads the 6 difference (not 93 as initially stated; recount pending).

---

## Right-Sizing & Wave Rules

✓ Task 1 (ensure_data): <12 steps, single concern (data validation)  
✓ Task 2 (update SSURGO.R): <12 steps, localized changes (3 targets removed, 1 added, 1 wrapper)  
✓ Task 3 (documentation): Trivial (comment block)  
✓ Files are disjoint: Task 1 is R/ensure_data.R (new), Task 2 is SSURGO.R (existing)  
✓ No cross-wave dependencies: Wave 2 depends on Wave 1 user action, not targets-tracked  

---

## Acceptance Criteria

**Wave 1 (ensure_data.R):**
- Script runs without errors
- All 3385 SSA directories present in data/
- Exit code 0

**Wave 2 (targets pipeline):**
- `tar_make()` completes successfully
- `tar_read(ssa_list)` returns sorted character vector, length 3385
- Downstream targets (ssurgo_create_duckdb, etc.) complete without reference errors
- No re-download of existing data/ files observed

