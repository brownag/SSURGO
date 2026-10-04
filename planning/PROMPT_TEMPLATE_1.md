# Worker Prompt Template — SSURGO Pipeline Robustness

## Preamble

This plan rebuilds the SSURGO pipeline to separate data validation from pipeline execution. Two waves, two tasks.

**Before you start:**
- Read `planning/EXECUTION_PLAN.md` (this is the contract)
- Verify you have R 4.6+, renv initialized
- Confirm `data/` exists with 3292+ SSA directories

**Commit discipline:** Conventional commit format, one sentence, no phase/wave numbers.  
Example: `refactor: move SSURGO data validation to standalone script`

---

## Wave 1: Data Validation

**Task:** ensure_data.R — Download missing SSAs and validate completeness

**Acceptance command:**
```bash
cd /home/andrew/workspace/SSURGO
Rscript R/ensure_data.R
# Expected: exit 0, final output "✓ Validation passed. All 3385 SSAs present."
```

**What you're doing:**
- Standalone R script (no targets)
- Runs sequentially (one SSA at a time)
- Downloads missing 93 SSAs (currently 3292 present, expect 3385)
- Validates completion, exits 0 if all present, 1 if any failed

**Constraints:**
- Do not parallelize downloads (user constraint: "sequential, parallel is a waste of public resources")
- Do not modify soilDB
- Do not update targets metadata

**If it fails:**
- Check stderr for which SSA failed to download
- Network issue? Try `ping wss.nrcs.usda.gov` first
- Partial success (some SSAs downloaded, then failed)? Re-run; it will skip completed ones and retry failed

---

## Wave 2: Targets Pipeline

**Task:** Update SSURGO.R — replace download targets with data reader

**Acceptance command:**
```bash
cd /home/andrew/workspace/SSURGO
rm -rf _targets  # Fresh start
targets::tar_make()
# Expected: completes successfully, no download activity, ssa_list target present
targets::tar_read(ssa_list)
# Expected: character vector, length 3385, all paths start with "data/"
```

**What you're doing:**
1. Delete branched download targets (`ssa`, `ssa_combined`, `ssa_files`)
2. Add single `ssa_list` tar_target that reads from data/ and validates count
3. Update downstream target dependencies to use `ssa_list` instead of `ssa_files`
4. Add documentation comment explaining two-step workflow

**Files to change:**
- `SSURGO.R` (main entry point, 251 lines)

**Specific edits:**

**Remove** (lines ~26-31):
```r
tar_target(
    name = ssa,
    command = download_state(statesym, ssas, destdir),
    pattern = map(statesym)
),
tar_target(ssa_combined, { ... }, pattern = tar_combine(ssa)),
tar_files(ssa_files, ssa_combined),
```

**Add** (after ssurgo_duckdb_path target):
```r
# Data validation: assumes ensure_data.R has run
tar_target(ssa_list, {
  files <- list.files("data", pattern = "^wss_.*\\.zip$", 
                      recursive = TRUE, full.names = TRUE)
  if (length(files) != 3385) {
    stop(sprintf("Expected 3385 SSURGO files, found %d. Run ensure_data.R first.", 
                 length(files)))
  }
  sort(files)
})
```

**Add** (before tar_script definition or at top of list):
```r
# Two-step workflow:
#   1. Rscript R/ensure_data.R  (validates data/ completeness, downloads missing 93 SSAs)
#   2. targets::tar_make()      (processes validated data into duckdb, spatial index, etc.)
# This separation prevents wasteful re-downloads on pipeline restarts and handles partial runs robustly.
```

**Search for downstream uses of `ssa_files`:**
```bash
grep -n "ssa_files" SSURGO.R
```
Update those lines to use `ssa_list` instead (if any).

**Constraints:**
- Do not modify `download_ssurgo()` function
- Do not refactor downstream processing (createSSURGO, duckdb, spatial queries)
- Keep tar_files wrapper if needed for backward compat

**If acceptance fails:**
- `tar_make()` error? Check SSURGO.R syntax with `Rscript -e 'source("SSURGO.R")'`
- `ssa_list` returns wrong length? Verify data/ has exactly 3385 SSA directories
- Downstream target fails? Check it doesn't still reference old `ssa_files` without wrapper

---

## Documentation Task

**Task:** Add comment block to SSURGO.R explaining workflow

**What to add:** 5-10 line comment at top of file (before library calls or tar_script):

```r
# SSURGO Pipeline — Data Validation + Processing Workflow
#
# Data arrives in two stages to ensure robustness:
#   1. Pre-pipeline: Rscript R/ensure_data.R validates and completes data/
#   2. Pipeline: targets::tar_make() processes validated data
#
# This separation prevents wasteful re-downloads when the pipeline is restarted.
# Previously, interrupted runs left targets metadata inconsistent; data validation
# now runs outside targets, ensuring idempotency.
```

---

## Rollback Procedure

If anything breaks irreparably:
1. Restore SSURGO.R from git: `git checkout SSURGO.R`
2. Delete _targets: `rm -rf _targets`
3. Revert ensure_data.R: `git checkout R/ensure_data.R` (if it exists in history)
4. Re-run original pipeline as baseline

---

## Glossary

- **ensure_data.R:** Standalone validation script (not in targets DAG)
- **ssa_list:** Targets task that lists validated data/ contents
- **ssa_files:** (old) Branched download task; being removed
- **Two-step workflow:** User runs ensure_data.R, then tar_make() — explicit, debuggable

