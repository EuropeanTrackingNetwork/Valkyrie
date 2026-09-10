# Reprocess files to get minICI

## Active files

| file | role |
|---|---|
| `parsePodName.m` | shared dependency -- parses station/POD serial/date/fileNo from any filename convention encountered (deployment-dated, power-on-dated, recovery-dated) |
| `surveyPodFiles.m` | inventories the raw and processed folders, reports naming patterns found |
| `collapseRawCopies.m` | reduces duplicate copies and `PART`-cropped variants of the same raw file to one representative |
| `buildDeploymentIndex.m` | pass 1 over `novana-bpm.csv` -- reduces it to one row per (deployment_fk, filename, species) with real time windows |
| `matchRawToProcessed.m` | matches raw files to already-processed deployments (POD serial + date window + deployment-identity grouping) |
| `findCompanionRawFiles.m` | finds the `.cp1` companion for each matched `.cp3`, by canonical filename |
| `runMinICIBatch.m` | runs `minICI_workflow` over the raw files, resumably, with a manifest |
| `combineMultipartOutputs.m` | consolidates multi-part deployments (file01/file02/...) into one output file each |
| `scanMinICIOutputs.m` | summarises the saved minICI output files |
| `matchFilesToDeployments.m` | matches those outputs to `deployment_fk` using the database's real time windows |
| `extractMinICIUpdates.m` | pass 2 over `novana-bpm.csv` -- produces the `id_pk,min_ici` file for the database team |
| `buildPublicationExport.m` | produces the full replacement CSV for the DOI/publication dataset, keyed off `extractMinICIUpdates`' own validated output |
| `verifyMinICIAgainstArchive.m` | spot-check: compares one minICI output against what's already in the database |
| `runVerificationBatch.m` | runs the spot-check over every resolved deployment, producing one summary table with automated diagnosis for any failures |

## Confirmed facts this workflow depends on

- `novana-bpm.csv`: comma-delimited, every field double-quoted, ISO datetimes
  (`yyyy-MM-dd HH:mm:ss`, with seconds). Every function below defaults to this.
- `minICI_workflow(filePath, 'PairPath', p, 'OutputCsv', folder, 'MatchName', m, 'Verbose', v)`
  -- ONE positional argument, everything else name-value. `'OutputCsv'` is a
  **folder**, not a file path -- the function names the file itself as
  `<MatchName or its own base name>_minICI.csv` inside it. Returns a struct
  (`S.n_rows`, `S.data`, ...), not a table.
- A `.cp1`/`.cp3` pair for one physical recording shares the same base
  filename; `minICI_workflow` looks for it in the same folder as whatever it's
  given, and takes `'PairPath'` explicitly for when it isn't there.
- The database's unique row identifier is `id_pk`. `(deployment_fk, datetime,
  quality)` is the join key used to find it, since the raw/processed files
  carry no `id_pk` of their own.

## Workflow

### 1. Survey and deduplicate

```matlab
% % Make sure to change the folder paths to where the processed and raw files are saved
% First find all the processed files
proc = surveyPodFiles([ ...
    "Folder\path\one"
    "Folder\path\two"], ...
    'Extensions', "csv", 'SaveTo', "processedFiles_inventory.mat");

raw = surveyPodFiles([ ...
    "Folder\path\one"
    "Folder\path\two"
    "Folder\path\three"], ...
    'Extensions', ["cp1","cp3","fp1","fp3"], 'SaveTo', "rawFiles_inventory.mat");

rawU = collapseRawCopies(raw, ...
    'FolderPreference', ["Folder_to_prefer", "Over_this_folder"], ...
    'SaveTo', "rawFiles_unique.mat");
```

### 2. Build the database index (once; cache it)

```matlab
idx = buildDeploymentIndex("File\path\to\ETN\extraction.csv", ...
    'Delimiter', ',', 'DatetimeFormat', 'yyyy-MM-dd HH:mm:ss', ...
    'SaveTo', "deployment_index.mat");
% later: load("deployment_index.mat", "idx")
```

### 3. Match raw files to deployments, and find each one's `.cp1`

```matlab
% Set the days() window to the number of days that would make sense
[R, reprocess] = matchRawToProcessed(proc, rawU, 'Index', idx, ...
    'RawExtensions', ["cp3","fp3"], 'WindowPad', days(45), ...
    'SaveTo', "match_raw_to_processed.csv");
% go through the printed ambiguous/no_raw_in_window cases before continuing

comp = findCompanionRawFiles(R, rawU, "cp1", 'SaveTo', "cp1_companions.csv");

pairPaths = renamevars(comp(comp.companionStatus=="found", {'matchedPath','companionPath'}), ...
    {'matchedPath','companionPath'}, {'rawPath','pairPath'});
matchNames = renamevars(R(:, {'rawPath','procName'}), {'procName'}, {'matchName'});
```

Any deployments left ambiguous after this need a manual decision -- pick the
correct `rawPath` by hand, fold it into `R`/`reprocess`/`pairPaths`/`matchNames`
the same way as everything else (status set to `"matched"`) so it goes through
`runMinICIBatch` and `combineMultipartOutputs` alongside the rest, rather than
as an untracked one-off.

### 4. Run the batch

```matlab
outFolder = "O:\Tech_Novana-Marsvin\DTO\VALKYRIEoutput\minICI_files";

manifest = runMinICIBatch(reprocess, outFolder, 'MaxFiles', 3, ...
    'PairPaths', pairPaths, 'MatchNames', matchNames);
% spot-check with verifyMinICIAgainstArchive before trusting the rest

manifest = runMinICIBatch(reprocess, outFolder, 'PairPaths', pairPaths, 'MatchNames', matchNames);
% already-done files are skipped, so this resumes cleanly after any interruption
```

On a slow/VPN network drive, add `'StageLocally', true` (stages both the raw
file and its pair locally, copies just the small result back).

### 5. Combine multi-part deployments

```matlab
combinedFolder = "O:\Tech_Novana-Marsvin\DTO\VALKYRIEoutput\minICI_combined";
combined = combineMultipartOutputs(R, manifest, combinedFolder);
disp(combined(~ismember(combined.status, ["combined","passthrough"]), :))  % must be empty
```

Every resolved deployment -- single-file or multi-part -- ends up as one file
in `combinedFolder` after this step.

### 5b. Verify every deployment against what's already in the database

```matlab
[summary, reports] = runVerificationBatch(combined, proc, 'SaveTo', "verify_summary.csv");
```

One table, one row per deployment, instead of reading 202 pages of console
output. `summary.note` is `"pass"` for anything that matches, or an automated
first-pass diagnosis for anything that doesn't -- several failure categories
(rows missing, extra rows, duplicate keys, which column disagrees) point
straight at the cause without any digging. To see the full detailed printout
for one specific deployment, either pull it from `reports` (`reports("procName")`)
or just re-run `verifyMinICIAgainstArchive` directly on that one file.

A duplicated archive file (same row appearing more than once in what's already
in the database -- seen once already with `FF2_2019_09_17_POD1981`) is
detected and corrected for automatically now, so it won't show up as a false
failure here; `dedupeArchiveFileInPlace.m` is available if a genuinely
duplicated archive file needs fixing at the source.

### 6. Match outputs to the database and produce both deliverables

```matlab
S = scanMinICIOutputs(combinedFolder, 'SaveTo', "minici_scan.mat");
X = matchFilesToDeployments(S, idx, 'SaveTo', "crosswalk.csv");

% deliverable 1: sparse update for the database team
rep1 = extractMinICIUpdates("O:\Tech_Novana-Marsvin\DTO\novana-bpm.csv", X, ...
    "min_ici_updates.csv", 'BigDelimiter', ',', 'BigDatetimeFormat', 'yyyy-MM-dd HH:mm:ss');
% check: unmatchedTargets, duplicateKeys, checkMismatch all 0

% deliverable 2: full publication/DOI export, built from deliverable 1
rep2 = buildPublicationExport("O:\Tech_Novana-Marsvin\DTO\novana-bpm.csv", ...
    "min_ici_updates.csv", "novana-bpm_published.csv");
% check: unusedUpdateRows is exactly 0
```

Run step 6 only once `X` covers everything -- the full batch and the manually
resolved deployments. A partial run produces a partial deliverable with no
visible sign anything is missing.