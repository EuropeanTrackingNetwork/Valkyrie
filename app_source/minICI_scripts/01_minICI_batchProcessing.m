%% ========================================================================
%  minICI back-fill workflow
%  =========================================================================
%
%  What this script does, end to end:
%
%    1. Indexes your full detection ETN export into a compact per-deployment summary.
%
%    2. Surveys your already-processed detection files and your raw POD
%       files, and works out which raw file corresponds to each processed
%       deployment -- raw filenames are NOT reliable identifiers on their
%       own (they often carry a power-on or recovery date rather than the
%       deployment date, and the same physical file can exist in more than
%       one folder), so this uses POD serial + the deployment's real time
%       window from the database to disambiguate.
%
%    3. Runs minICI_workflow over every raw file that needs reprocessing.
%    This function is the one that processes the exact same way as VALKYRIE
%    where min_ici is included instead of bpm
%
%    4. Combines multi-part deployments (file01/file02/...) into one output
%       file per deployment.
%
%    5. Verifies every new output against what's already on record.
%
%    6. Matches the new outputs back to the database (by deployment window,
%       not filename) and produces a sparse id_pk/min_ici update file.
%
%    7. For AU only: Adds a MIN_ICI column to a separate folder of yearly
%       dataset files (a different format used for a DOI / publication
%       dataset), if you have one.
%
%  REQUIREMENTS ON YOUR MATLAB PATH
%    - minICI_workflow.m and everything it needs (its own CP3/FP3 readers,
%      angle-calculation helper, etc.)
%    - The toolset functions this script calls: buildDeploymentIndex,
%      surveyPodFiles, collapseRawCopies, matchRawToProcessed,
%      findCompanionRawFiles, runMinICIBatch, combineMultipartOutputs,
%      runVerificationBatch, scanMinICIOutputs, matchFilesToDeployments,
%      extractMinICIUpdates, and (if you use section 8) addMinICIToYearlyFolder.
%
%  HOW TO USE THIS SCRIPT
%    Fill in Section 0 ONCE for your data, then run each section in order
%    using MATLAB's "Run Section" (the sections are separated by %%).
%    This is deliberately NOT meant to run unattended top-to-bottom the
%    first time through -- several sections print a report that is worth
%    reading before moving on to the next one.
%
% =========================================================================

%% ======================== SECTION 0: CONFIGURATION =====================
%  Set every path here, once. Nothing below this section should need
%  editing for a normal run -- if you find yourself changing a path further
%  down, it probably belongs up here instead.

% --- Your database export -------------------------------------------------
% The full detection ETN export, equivalent to "novana-bpm.csv" --
% every detection-minute row, across every deployment, with the columns 
% ETN actually uses. This is the file buildDeploymentIndex and
% extractMinICIUpdates both read.
bigCsv = "O:\path\to\your\full_detection_export.csv";

% --- Folders holding your ALREADY-PROCESSED detection files --------------
% One or more folders (searched recursively) containing the per-deployment
% CSVs that already exist -- these are what tells the script WHICH
% deployments to look for a raw file for. Not every file in here is
% necessarily already uploaded to the database; that gets checked
% automatically later on, it doesn't need to be true up front. It can be
% a single or several folders, just seperate with a ;
processedFolders = [ ...
    "O:\path\to\your\processed_detection_files";
    "O:\another\path\to\processed_detection_files"
    ];

% --- Folders holding your RAW POD files -----------------------------------
% One or more folders (searched recursively) containing the raw .cp1/.cp3/
% .fp1/.fp3 files. Add as many root folders as you have -- e.g. if your
% raw archive is split across several drives or year ranges, list them all;
% surveyPodFiles searches every subfolder of each one you give it. This can
% also work on a single or several folders, depending on need.
rawFolders = [ ...
    "O:\path\to\your\raw_pod_files";
    "O:\another\path\to\raw_pod_files"
    ];

% --- Working folder for intermediate files --------------------------------
% Every .mat/.csv this script saves along the way (indexes, survey results,
% match reports, the final update file) goes here. One folder, so nothing
% is scattered across your drive.
workFolder = "O:\path\to\your\minICI_working_folder";

% --- Where the actual minICI output files get written ---------------------
outFolder      = "O:\path\to\your\minICI_output_files";        % one file per raw file
combinedFolder = "O:\path\to\your\minICI_combined_output";     % one file per DEPLOYMENT

% --- OPTIONAL: yearly dataset files for a DOI / publication dataset -------
% Only needed if you have a separate folder of yearly files, in a
% DIFFERENT format from your database export, that also needs min_ici added
% (see Section 8). Leave as-is if you don't have this.
% OBS: this was used to update files to share with Claudia for the NOVANA,
% but once min_ici is in ETN, it can as easily be extractred from there
% instead.
yearlyInputFolder  = "O:\path\to\your\yearly_dataset_files";
yearlyOutputFolder = "O:\path\to\your\yearly_dataset_files_with_minici";

% --- Folder-preference for de-duplicating raw files -----------------------
% If the same raw file exists in more than one folder (backups, a folder
% that was reorganised at some point, etc.), this says which folder to
% trust when choosing which copy to use -- listed in priority order, most
% preferred first. Adjust the substrings below to match folder names that
% are actually meaningful in YOUR archive; if you don't have duplicate
% copies of files across folders, this can be left empty ([]).
folderPreference = ["PREFERRED_FOLDER_NAME_1", "PREFERRED_FOLDER_NAME_2"];

% Make folder directories if they don't exist
if ~isfolder(workFolder), mkdir(workFolder); end
if ~isfolder(outFolder), mkdir(outFolder); end
if ~isfolder(combinedFolder), mkdir(combinedFolder); end

fprintf('Configuration set. Working folder: %s\n', workFolder);
%% ================= SECTION 1: INDEX THE ETN EXPORT =================
%  Reduces the full ETN export down to one row per deployment, with
%  each deployment's REAL first/last detection timestamp. This is what lets
%  later steps disambiguate raw files using an actual time window rather
%  than trusting a date embedded in a filename. This step reads the whole
%  file, so it's the slowest one here -- but only needs to be done once
%  (or again later, if the ETN export is refreshed).

tic;
idx = buildDeploymentIndex(bigCsv, ...
    'Delimiter', ',', 'DatetimeFormat', 'yyyy-MM-dd HH:mm:ss', ...
    'SaveTo', fullfile(workFolder, "deployment_index.mat"), ...
    'ProgressFcn', @(frac, msg) fprintf('[%.1f%%] %s\n', frac*100, msg));
toc

% Next time you run this script, if the database export hasn't changed,
% skip this section and just load the cached result instead:
%   load(fullfile(workFolder, "deployment_index.mat"), "idx")
%% ================ SECTION 2: SURVEY + DE-DUPLICATE FILES ================
%  Inventories every processed file and every raw file, and reports what
%  naming patterns are actually present -- read the printed output before
%  continuing, since it will tell you if a chunk of your raw files aren't
%  parsing (an unusual naming convention that needs handling) before you've
%  invested time in later steps.

proc = surveyPodFiles(processedFolders, ...
    'Extensions', "csv", ...
    'SaveTo', fullfile(workFolder, "processedFiles_inventory.mat"));

raw = surveyPodFiles(rawFolders, ...
    'Extensions', ["cp1","cp3","fp1","fp3"], ...
    'SaveTo', fullfile(workFolder, "rawFiles_inventory.mat"));

% Collapses duplicate copies of the same raw file (and cropped/"PART"
% variants) down to one representative each, using folderPreference above
% to choose which copy when more than one exists.
rawU = collapseRawCopies(raw, ...
    'FolderPreference', folderPreference, ...
    'SaveTo', fullfile(workFolder, "rawFiles_unique.mat"));

%% ============== SECTION 3: MATCH RAW FILES TO DEPLOYMENTS ===============
%  For every processed deployment, finds the raw file that actually belongs
%  to it -- matching on POD serial and the deployment's real time window
%  from idx, not on filename alone. Prints a summary of how many resolved
%  automatically and how many need a closer look.
%
%  READ THE PRINTED SUMMARY before continuing. Anything reported as
%  "ambiguous" or "no_raw_in_window" needs a decision:
%    - "ambiguous": two candidate raw files are equally plausible -- usually
%      needs picking the correct one by hand (see the note at the end of
%      this script).
%    - "no_raw_in_window": no raw file was found inside the expected time
%      window. Sometimes this means the raw file genuinely isn't in the
%      folders you gave it; sometimes it means the true window is wider
%      than the default padding below and needs widening. If several of
%      these share the same kind of gap (e.g. all off by a similar number of
%      days), that pattern is worth noticing -- it usually means one
%      consistent date convention issue, not many unrelated problems.

[R, reprocess] = matchRawToProcessed(proc, rawU, 'Index', idx, ...
    'RawExtensions', ["cp3","fp3"], 'WindowPad', days(45), ...
    'SaveTo', fullfile(workFolder, "match_raw_to_processed.csv"));

%% ===================== SECTION 4: FIND THE .cp1 PAIRS ====================
%  minICI_workflow needs both the classified detection file (.cp3) and its
%  raw noise/click pair (.cp1) -- it looks for the .cp1 in the SAME FOLDER
%  as the .cp3 automatically, but the pair isn't always co-located. This
%  finds the correct .cp1 for each matched .cp3 by filename, wherever it
%  actually sits, so it can be passed explicitly instead of relying on
%  same-folder auto-discovery.

comp = findCompanionRawFiles(R, rawU, "cp1", 'SaveTo', fullfile(workFolder, "cp1_companions.csv"));

pairPaths = comp(comp.companionStatus == "found", {'matchedPath','companionPath'});
pairPaths = renamevars(pairPaths, {'matchedPath','companionPath'}, {'rawPath','pairPath'});

% A deployment split across more than one raw file (file01, file02, ...)
% needs a DISTINCT output name per part -- otherwise every part would
% predict the same output filename, and only the first one to finish would
% actually get processed; the rest would look "already done" and be
% skipped. This builds that per-part naming automatically; single-part
% deployments are left with their plain name.
[~, ~, g] = unique(R.procName);
counts = accumarray(g, 1);
isMultiPart = counts(g) > 1;

matchNameVal = R.procName;
matchNameVal(isMultiPart) = R.procName(isMultiPart) + "_file" + compose("%02d", R.rawFileNo(isMultiPart));

matchNames = table(R.rawPath, matchNameVal, 'VariableNames', {'rawPath','matchName'});

%% =================== SECTION 5: RUN minICI_workflow ======================
%  Actually reprocesses every raw file that needs it. Already-processed
%  files are skipped automatically on a re-run, so it's safe to re-run this
%  section after an interruption without redoing finished work.
%
%  This is usually the slowest step besides Section 1 -- consider trialling
%  it on a handful of files first (runMinICIBatch(reprocess(1:3), ...))
%  before committing to the full list, especially the first time you run
%  this against your own data.

tic;
manifest = runMinICIBatch(reprocess, outFolder, 'PairPaths', pairPaths, 'MatchNames', matchNames);
toc

%% ============ SECTION 6: COMBINE MULTI-PART DEPLOYMENTS ==================
%  Your database presumably receives one deployment as a single file, even
%  when the raw data came in as several parts -- this merges each
%  deployment's parts (if any) into one output file, and copies single-part
%  deployments across unchanged, so every deployment ends up as exactly one
%  file in combinedFolder.

combined = combineMultipartOutputs(R, manifest, combinedFolder);

% This should print an EMPTY table -- anything listed here needs attention
% (usually: a part hasn't finished processing yet, or two parts disagree
% on timing in a way that looks like they shouldn't be combined) before
% moving on.
disp(combined(combined.status ~= "combined" & combined.status ~= "passthrough", :))

%% =========== SECTION 7: VERIFY EVERY OUTPUT, THEN BUILD THE UPDATE =======
%  Two checks, then the actual deliverable.

% 7a. Compare every new output against its existing processed file. Read
%     the printed failures list, if any, before trusting the batch --
%     "note" gives an automated first-pass diagnosis for each failure
%     rather than just a pass/fail flag.
[summary, reports] = runVerificationBatch(combined, proc, ...
    'SaveTo', fullfile(workFolder, "verify_summary.csv"));

% 7b. Match the new outputs to your database by their REAL time window
%     (not by filename), to get each deployment's own database identifier.
%     Deployments that haven't been uploaded to the database yet will
%     correctly show up here as unmatched -- that's expected, not an error;
%     there's nothing to update in the database for them until they are.
S = scanMinICIOutputs(combinedFolder, 'SaveTo', fullfile(workFolder, "minici_scan.mat"));
X = matchFilesToDeployments(S, idx, 'SaveTo', fullfile(workFolder, "crosswalk.csv"));

% 7c. Build the actual update file: one row per (id_pk, min_ici) for every
%     deployment that matched. This is what goes to whoever maintains your
%     database -- a sparse, targeted update, not a full-table replacement.
%     Every written row is independently re-verified (clicks/milliseconds
%     must agree) before being written, so a bad match can't silently
%     corrupt the update file.
rep = extractMinICIUpdates(bigCsv, X, ...
    fullfile(workFolder, "min_ici_updates.csv"), ...
    'BigDelimiter', ',', 'BigDatetimeFormat', 'yyyy-MM-dd HH:mm:ss', ...
    'ProgressFcn', @(f,msg) fprintf('%s\n', msg));

% Check before treating this as done:
%   rep.unmatchedTargets  should be 0
%   rep.checkMismatch     should be 0
%   rep.duplicateKeys     should be 0, UNLESS you've separately confirmed
%                         your database itself has duplicate rows for some
%                         deployment -- in that case a small non-zero count
%                         here is expected and correct, not a bug.

%% ========= SECTION 8 (OPTIONAL): ADD min_ici TO YEARLY DATASET FILES =====
%  Only relevant if you separately maintain yearly dataset files in a
%  different format (e.g. for a DOI / data-publication process) that also
%  need a min_ici value added. Skip this section entirely if that doesn't
%  apply to you.
%
%  This does NOT generate those yearly files from scratch -- it adds a
%  MIN_ICI column to files that already exist, produced by whatever process
%  already builds them. If your yearly format's quality field uses a
%  different encoding than a fixed 3=Hi/2=Mod/1=Lo, pass 'QualityMap' with
%  your own mapping.

summary8 = addMinICIToYearlyFolder(yearlyInputFolder, ...
    fullfile(workFolder, "min_ici_updates.csv"), ...
    yearlyOutputFolder);

% Check before trusting the output:
%   unmatchedQualityCodes should be 0 for every year
%   duplicateRowsRemoved should be near 0 for years that don't overlap any
%     database duplication you already know about, and roughly matching the
%     duplicate count for any year that does


%% ============================ IF SOMETHING NEEDS FIXING BY HAND =========
%  Real datasets usually have a handful of cases the automated matching
%  can't resolve on its own -- two similarly-dated files for the same POD
%  with no way to tell them apart from the filename alone, for instance.
%  That's normal, not a sign anything is broken elsewhere.
%
%  For those cases:
%    - buildManualRow lets you build a single corrected row by hand once
%      you've identified the right raw file
%    - re-run findCompanionRawFiles / the multi-part naming step on just
%      the corrected row(s), then feed them through runMinICIBatch and
%      combineMultipartOutputs the same way as everything else, so they end
%      up in the exact same combinedFolder and get covered by the same
%      verification and update steps
%
%  Always re-run Section 7a (verification) on anything fixed by hand before
%  trusting it -- the same check that validates the automated results is
%  what catches a wrong manual guess too.