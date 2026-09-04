# minICI back-fill toolset

MATLAB functions for (1) verifying that the minICI re-run reproduces the detection
files already in the database, and (2) mapping the minICI output onto the full
detection export so only `min_ici` has to be re-uploaded.

All functions are plain functions with an optional `'ProgressFcn'` so they can be
called straight from App Designer callbacks. Nothing uses globals or the base
workspace.

---

## 1. Verification result for the two files supplied

`GB1_2011_11_09_POD1685_file01_minICI.csv` vs `GB1_2011_06_23_POD1685.csv`,
joined on `datetime + quality + species`:

| | |
|---|---|
| shared keys | **456,108** (every row of the archive file) |
| rows in archive missing from the new output | **0** |
| columns compared | temperature, angle, number_clicks_total, number_clicks_filtered, DPM, milliseconds, time_lost_percentage, species, recorded |
| mismatching values | **0 across all 9 columns** |
| extra rows in the new output | 15,027 = 5,009 minutes x 3 quality classes |

The extras are entirely outside the archive's window — 8,121 rows before
`2011-06-23 10:05` and 6,906 after `2011-10-07 00:00`, none inside. The archived
export was trimmed to the in-water period; the minICI script exports the whole POD
file including the power-on and post-recovery minutes. **These rows have no database
row to attach to and must be dropped before upload**, which the toolset does using
the deployment's own first/last timestamp.

`min_ici` is internally consistent: 10,091 values in total, non-null on exactly the
rows where `number_clicks_filtered > 0` and `DPM = 1`, never elsewhere. Restricted to
the archive window there are **10,043 values, and the archive has exactly 10,043
click-positive rows**. That count invariant is the strongest single check available
and it passes; it is reused later as the confirmation test for each file-to-deployment
match. Values vary between the three quality classes for the same minute, as they
should if the ICI is computed from that class's filtered trains.

### Four things worth fixing before the bulk run

1. **`BPM` is not in the new output.** The archive has it (1,554 rows with `BPM = 1`)
   and the database has `detection_bpm`. Harmless if only `min_ici` is ever written
   back, but it means the new files are not a drop-in replacement for a detection
   file, and it cannot be verified for the files being re-run.
2. **Missing `min_ici` is written as the literal text `NaN`.** Most bulk loaders
   reject that in a numeric column. Write an empty field instead.
3. **Drop `min_ici_raw` before handover.** It is identical to `min_ici` except it
   carries `0` where there is no measurement, and `0` is a value a real ICI can never
   take. Two columns that differ only in how they encode "no data" is exactly the
   ambiguity that ends up in the database.
4. **Sanity-check the high tail biologically.** Values look like microseconds
   (median 31,290 us = 31 ms, plausible for NBHF). The maximum is 936,680 us =
   0.94 s, and rows with only 5 filtered clicks show minimum ICIs of 260-290 ms.
   Confirm those come from genuinely sparse trains rather than from the minimum
   being taken across a train boundary.

### Why filenames cannot be matched as strings

The same file carries three different names in the three places it appears:

| where | value |
|---|---|
| archive `filename` (station + deployment date) | `GB1 2011 06 23 POD1685` |
| archive `PODfile` (station + power-on date) | `GB1A 2011 06 21 POD1685 file01` |
| minICI `filename` (from disk, recovery date) | `GB1 2011 11 09 POD1685 file01` |

Three different dates and two different station codes for one deployment. Matching
therefore uses the POD serial (stable everywhere), the time window, and the count
invariant — the filename date is only ever used to break ties and for reporting.

---

## 2. Files

| file | what it does |
|---|---|
| `verifyMinICIAgainstArchive.m` | compares one minICI output against one archived detection file and prints a pass/fail report |
| `inspectBigFile.m` | reads the real on-disk delimiter and datetime format of the 13 GB export from raw bytes — run this before the two functions below |
| `buildDeploymentIndex.m` | **pass 1** over the 13 GB export; reduces it to one row per source file (window, row counts, click-positive counts) |
| `scanMinICIOutputs.m` | summarises a folder of minICI outputs (window, counts, the timestamps carrying an ICI) |
| `matchFilesToDeployments.m` | builds the crosswalk minICI file -> `deployment_fk`, with a status per row |
| `extractMinICIUpdates.m` | **pass 2** over the export; writes `id_pk,min_ici,...` for verified matches only |
| `parsePodName.m` | pulls station / POD serial / file index / date out of any of the naming variants |

---

## 3. Workflow

### Spot-check a few files first

```matlab
report = verifyMinICIAgainstArchive( ...
    "GB1_2011_11_09_POD1685_file01_minICI.csv", ...
    "GB1_2011_06_23_POD1685.csv");

if ~report.ok
    disp(report.columns)
    disp(report.mismatchSamples)
end
```

`report.ok` tolerates extra rows outside the archive window and nothing else. Extras
*inside* the window, any archive row missing from the new output, a value mismatch,
or a failed ICI count invariant all fail it.

### Bulk run

```matlab
big = "all_detections.csv";

% pass 1 - once, then cached. Hours on 13 GB; the result is a few thousand rows.
idx = buildDeploymentIndex(big, 'SaveTo', "deployment_index.mat");

% the new outputs
S = scanMinICIOutputs("D:\minici_out", 'SaveTo', "minici_scan.mat");

% crosswalk - inspect this before going further
X = matchFilesToDeployments(S, idx, 'SaveTo', "crosswalk.csv");
disp(groupsummary(X, 'status'))

% pass 2 - only status=="matched" rows are used
rep = extractMinICIUpdates(big, X, "min_ici_updates.csv", ...
    'UnmatchedCsv', "min_ici_unmatched.csv");
```

`min_ici_updates.csv` is what the database team gets:

```
id_pk,min_ici,deployment_fk,datetime,quality,species,source_file,db_filename
```

`id_pk` alone is enough for the `UPDATE`; the other columns are there so the update
can be independently verified before it is applied, and `source_file` gives the
per-detection filename provenance you wanted to keep.

### Size of the upload

`min_ici` is non-null only where `number_clicks_filtered > 0` — 10,091 of 471,135
rows, about 2%, in the file checked here. Rows with no measurement need no update at
all; they are already NULL. So the update file is roughly 2% of the database, not
100% of it, and the whole target set fits in memory during pass 2.

---

## 4. Checks that catch a wrong match

A crosswalk error is the failure mode that would quietly corrupt the database, so
three independent things have to agree before a row is written:

1. **Window containment** — the deployment's `[first,last]` datetime must sit inside
   the POD file's window. A neighbouring deployment of the same POD will not fit.
2. **Count invariant** — the number of `min_ici` values inside the deployment window
   must equal the deployment's count of click-positive rows. Wrong file, wrong count.
3. **Per-row agreement** — `number_clicks_filtered` and `milliseconds` must match
   between the database row and the minICI row for every single row written. Rows
   that disagree are counted and sampled, never written.

`matchFilesToDeployments` also warns when one `deployment_fk` has database files with
overlapping time ranges, because `(deployment_fk, datetime, quality, species)` is not
unique in that case; `extractMinICIUpdates` errors out rather than guessing.

Rows in the crosswalk with a status other than `matched` are a review queue:
`ambiguous`, `window_mismatch`, `count_mismatch`, `no_candidate`, `no_podid`. Expect a
handful — POD files split across `file01`/`file02`, PODs redeployed at the same
station within a day, names where the serial is absent.

---

## 5. Wiring into the App Designer app

Each function takes `'ProgressFcn'` as a handle called with `(fraction, message)`:

```matlab
function ButtonPushed(app, event)
    d = uiprogressdlg(app.UIFigure, 'Title', 'Indexing detection export', ...
                      'Indeterminate', 'off', 'Cancelable', 'off');
    prog = @(f, msg) updateDlg(d, f, msg);
    try
        app.Index = buildDeploymentIndex(app.BigCsvPath, 'ProgressFcn', prog);
        app.IndexTable.Data = app.Index;
    catch err
        uialert(app.UIFigure, err.message, 'Indexing failed');
    end
    close(d);
end

function updateDlg(d, f, msg)
    if ~isnan(f), d.Value = max(0, min(1, f)); end
    d.Message = msg;
end
```

Pass 1 on 13 GB is long enough that it should run once and be cached to `.mat` —
`buildDeploymentIndex(..., 'SaveTo', ...)` writes both a `.mat` and a `.csv` copy —
with the app loading the cache when it exists.

---

## 6. Confirmed real file format

Running `inspectBigFile` on the actual export (not an Excel paste) found a bug in
the tool itself: the file quotes every field (`"id_pk","deployment_fk",...`), and
the raw byte-scanning logic wasn't stripping that quoting before checking the date
pattern, so a leading `"` broke the ISO-date regex anchor and it reported
`"unknown"` even though the sample dates were unambiguous. Fixed by stripping a
layer of matching quotes off every split token before pattern-matching. This only
affected `inspectBigFile`'s own analysis -- `readtable`/`tabularTextDatastore`
handle standard quoted CSV natively regardless.

With that fixed, the real format is unambiguous:

- **comma-delimited**, every field double-quoted, 30 columns matching the header
  list from the start of this conversation
- **datetime is ISO**, `yyyy-MM-dd HH:mm:ss`, with seconds -- ISO order carries no
  day/month ambiguity, unlike the earlier guess based on the Excel paste
- `temperature`/`angle` come through as decimals (`"18.0"`) rather than the
  archive CSVs' integers -- harmless, both are cast to `double` before comparison
- `recorded` is `"True"`/`"False"` (title case), not used in any comparison here

Run pass 1 with the format given explicitly:

```matlab
idx = buildDeploymentIndex("O:\Tech_Novana-Marsvin\DTO\novana-bpm.csv", ...
    'Delimiter', ',', 'DatetimeFormat', 'yyyy-MM-dd HH:mm:ss', ...
    'SaveTo', 'deployment_index.mat');
```

If a different site's export turns out to use a different delimiter or date
order, run `inspectBigFile` on that file too rather than assuming it matches --
the whole reason the tool reads raw bytes instead of trusting a paste or a
previous run's format is that this can vary file to file.

There was also a real bug, independent of the format questions: `groupsummary(T,
groupvars, methods, datavars)` does not pair `methods` and `datavars` element-wise —
it applies **every** method to **every** variable (a full cross product). Passing
`{'sum','min','max'}` against `{'clickPos','hasICI','dt'}` therefore tried
`sum(dt)`, and `sum` can't be applied to a datetime column, which is the error you
hit. `buildDeploymentIndex` now runs the numeric sums and the datetime min/max as two
separate `groupsummary` calls and joins the results back together on the group keys;
the same bug existed a second time in the internal `rollup` helper and has been fixed
the same way.

## 8. Bulk processing: finding the files to reprocess

Three more functions cover the front half of the job -- working out which raw POD
files need rerunning, and rerunning them.

| file | what it does |
|---|---|
| `surveyPodFiles.m` | recursively inventories a folder tree and reports the naming patterns actually present |
| `matchRawToProcessed.m` | pairs each already-processed detection file with its source raw POD file |
| `runMinICIBatch.m` | runs `minICI_workflow` over the resulting list, resumably, with a manifest |

### Survey first

The raw `CP1/CP3/FP1/FP3` names may not follow the convention the processed names
do -- that mismatch is the whole problem -- so read the patterns off the disk
before matching anything:

```matlab
proc = surveyPodFiles([ ...
    "O:\Tech_Novana-Marsvin\DTO\VALKYRIEoutput\2011-2017\Detection files"
    "O:\Tech_Novana-Marsvin\DTO\VALKYRIEoutput\2017-2021\Split files"], ...
    'Extensions', "csv", 'SaveTo', "proc_inventory.mat");

raw = surveyPodFiles([ ...
    "O:\Tech_Novana-Marsvin\CPODS\DATA\2011-2016"
    "O:\Tech_Novana-Marsvin\CPODS\DATA\2017-2021"], ...
    'Extensions', ["cp1","cp3","fp1","fp3"], 'SaveTo', "raw_inventory.mat");
```

Read both printed reports before continuing. They show how many POD serials
parsed, what the unparseable names look like, which extensions are present, and
whether any `(podId, fileNo, ext)` combination appears twice. If a lot of raw
names don't parse, `parsePodName` needs another pattern added before matching
will work -- send me a sample and I'll extend it.

### Match, using the database index

```matlab
load deployment_index.mat idx     % from pass 1

[R, reprocess] = matchRawToProcessed(proc, raw, ...
    'Index', idx, ...
    'RawExtensions', ["cp3","fp3"], ...
    'SaveTo', "raw_to_processed.csv");
```

Passing `'Index'` matters. Without it, matching compares two filename dates whose
meanings differ (deployment vs power-on vs recovery) and has to use a wide
tolerance. With it, a raw file is accepted when its name date falls near the
deployment's *real* first/last detection timestamps from the database -- which is
what actually disambiguates a POD that was deployed repeatedly at the same
station.

`file01`/`file02` parts of one deployment come back as `matched_multipart` and are
all included in `reprocess`; that is not treated as ambiguity. Genuine ambiguity
is excluded and listed for review.

### Run the batch

Trial-run three files, verify them, then go wide:

```matlab
outFolder = "O:\Tech_Novana-Marsvin\DTO\VALKYRIEoutput\minICI";

manifest = runMinICIBatch(reprocess, outFolder, 'MaxFiles', 3, ...
    'ProgressFcn', @(f,msg) fprintf('[%.0f%%] %s\n', 100*f, msg));

% check one against its archived detection file before trusting the rest
verifyMinICIAgainstArchive(manifest.outPath(1), "<matching archive file>.csv");

% then the rest -- already-done files are skipped, so this resumes cleanly
manifest = runMinICIBatch(reprocess, outFolder);
```

The batch is built for a long run: each file is skipped if its output already
exists (so it resumes after an interruption), each runs inside try/catch (so one
bad POD file doesn't lose the run), and the manifest row is appended to disk after
every file (so a crash still leaves a complete record). The manifest is also the
raw-file-to-output-file provenance the database team needs.

`minICI_workflow`'s calling convention is set with `'WorkflowMode'` --
`"writes_file"` for `minICI_workflow(inPath, outPath)`, `"returns_table"` for
`T = minICI_workflow(inPath)`. The default `"auto"` tries both, but set it
explicitly once you know which it is.

## 9. Assumptions to confirm against the real export

These are guesses from the header list; all are options on the relevant function.

- `datetime` in the export is at minute resolution and its exact format is
  resolved by `inspectBigFile`, not assumed — see section 6.
- NULL `min_ici` in the export appears as an empty field, `NULL`, or `NaN` — all three
  are treated as missing.
- `detections_file_train_duration_filename` holds the `GB1 2011 06 23 POD1685` style
  name (`'FilenameVar'`; switch to `detections_file_det_env_filename` if not).
- `quality` uses the same three labels as the detection files (`Hi`/`Mod`/`Lo`) and
  `species` the same codes (`NBHF`). Both are upper-cased before comparison, so case
  differences are safe; different vocabularies are not.
- `(deployment_fk, datetime, quality, species)` uniquely identifies a database row.
  The overlap warning in `matchFilesToDeployments` is there because this is the one
  assumption that could silently be false.
- `recorded` in the export reads `TRUE`/`FALSE` (from the pasted sample), versus
  `0`/`1` in the archive CSVs. Not currently compared anywhere in this toolset, so
  no fix was needed for it, but worth knowing if it's ever used later — and worth
  re-checking on the real file for the same reason as everything else in section 6.

The MATLAB code has not been executed — there is no MATLAB in the environment it was
written in. The comparison logic behind section 1 was run against your two CSVs
directly, so those numbers are real; the functions themselves need a first run on a
single file before the bulk pass.
