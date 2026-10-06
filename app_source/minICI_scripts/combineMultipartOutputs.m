function combined = combineMultipartOutputs(R, manifest, outFolder, varargin)
%COMBINEMULTIPARTOUTPUTS Concatenate per-part minICI outputs into one file per deployment.
%
%   combined = combineMultipartOutputs(R, manifest, outFolder)
%
%   R          matchRawToProcessed output (procName, rawPath, status, rawFileNo, ...)
%   manifest   runMinICIBatch output (rawPath, outPath, status). This can
%              safely be the FULL accumulated manifest, including rows from
%              earlier/superseded runs -- see "manifest deduplication" below.
%   outFolder  destination for the combined files
%
%   Manifest deduplication
%   -----------------------
%   runMinICIBatch's manifest is an APPEND-ONLY LOG by design (it opens the
%   file in append mode every run, preserving the full history of every
%   attempt for audit purposes) -- it is not a current-state table. A raw
%   file reprocessed more than once (a bug fix, a deliberate 'Overwrite'
%   rerun) legitimately has more than one row for the same rawPath. This
%   function deduplicates to the LAST occurrence per rawPath before joining,
%   so a stale entry from before a fix can never silently outrank the
%   current, correct one -- you do not need to pre-clean the manifest
%   yourself before calling this.
%
%   Why this step exists
%   ---------------------
%   The database receives one deployment as a single concatenated detection
%   file, whether the raw data came in as file01/file02/file03 or one file.
%   runMinICIBatch, however, runs minICI_workflow once per RAW file, so a
%   3-part deployment produces 3 separate minICI output files, each covering
%   only its own slice of the deployment's time span.
%
%   Feeding those part-files straight into scanMinICIOutputs /
%   matchFilesToDeployments would fail silently: the window-containment check
%   there expects one output file to cover the WHOLE database window for that
%   deployment, and a single part only covers a fraction of it. This function
%   produces the single combined file that step actually needs, for every
%   procName the matcher marked matched_multipart. Single-file deployments are
%   copied into outFolder alongside the combined ones (same naming pattern) so
%   that after this call EVERY resolved deployment -- multi-part or not -- has
%   exactly one file sitting in one folder. Point scanMinICIOutputs at
%   outFolder as a whole directory next; there is no need to separately track
%   which deployments were multi-part and which weren't.
%
%   Safety checks before concatenating
%   -----------------------------------
%   Parts of one deployment should be back-to-back in time with no overlap. Two
%   parts sharing a (datetime, quality, species) key would silently corrupt a
%   later step that assumes that combination is unique, so this is checked and
%   any group with a collision is skipped -- reported in .conflicts, not merged.
%
%   combined columns
%       procName, combinedPath, nParts, totalRows, sourceParts (";"-joined,
%       ordered by fileNo), status ("combined" | "skipped_conflict" |
%       "skipped_incomplete" | "passthrough")
%
%   Options
%       'Suffix'       appended to the target name for the combined filename
%                      (default "_minICI_combined")
%       'Overwrite'    redo a combined file that already exists (default false)
%       'TargetNames'  table with columns {procName, targetName}, one row per
%                      deployment. When supplied, BOTH the combined file's own
%                      disk name AND its internal 'filename' CSV column (the
%                      archive format's own field, read back by
%                      scanMinICIOutputs as newFilename) are set to
%                      targetName instead of procName, for every row,
%                      overwriting whatever per-part value each part's own
%                      minICI_workflow output happened to carry.
%
%                      This matters whenever whatever matches these outputs
%                      to a deployment afterward does an exact NAME-TEXT join
%                      (e.g. buildCrosswalkFromLookup) rather than window
%                      matching (matchFilesToDeployments) -- window matching
%                      never cared what text sat in that column or what the
%                      combined file was named, so this was never needed for
%                      it. Without 'TargetNames' supplied, a multi-part
%                      deployment's combined file keeps each part's own
%                      per-part-suffixed filename text (inconsistent across
%                      rows), and the combined file itself is named after
%                      procName rather than the deployment's real dbFilename
%                      -- both silently break a name-based join even though
%                      window-based matching was never affected by either.
%
%                      Build TargetNames the same way the real output naming
%                      was derived (e.g. from idx.dbFilename via the same
%                      join used to build MatchName), not from procName
%                      itself -- procName alone lacks whatever the real
%                      target naming scheme adds (a timestamp suffix, a
%                      shard-specific convention, etc).
%
%   Part of the minICI back-fill toolset.

opts = struct('Suffix', "_minICI_combined", 'Overwrite', false, 'TargetNames', table());
opts = parseOpts(opts, varargin);

if ~isfolder(outFolder), mkdir(outFolder); end

useTargetNames = ~isempty(opts.TargetNames);
if useTargetNames
    need = ["procName","targetName"];
    missing = setdiff(need, string(opts.TargetNames.Properties.VariableNames));
    if ~isempty(missing)
        error('combineMultipartOutputs:badTargetNames', ...
            "'TargetNames' is missing column(s): %s.", strjoin(missing, ', '));
    end
end

resolved = ["matched","matched_multipart","matched_nearest"];
Rr = R(ismember(R.status, resolved) & ~ismissing(R.rawPath), :);

% The manifest is an APPEND-ONLY LOG by design (runMinICIBatch opens it in
% append mode every run, so the full history of every attempt is preserved
% for audit purposes) -- it is NOT a current-state table. A raw file
% reprocessed more than once (a bug fix, a deliberate 'Overwrite' rerun)
% legitimately has more than one row for the same rawPath. A plain
% ismember(Rr.rawPath, manifest.rawPath) join silently returns the FIRST
% match, which can be a STALE entry from before a fix -- observed in
% practice as a multi-part deployment where an early, incomplete run's
% output got picked over the later, correct one, despite both existing in
% the same manifest. Deduplicating to the LAST occurrence per rawPath here
% means every caller gets this safety automatically, rather than needing to
% remember to dedupe before every call.
[~, keepIdx] = unique(manifest.rawPath, 'last');
manifest = manifest(sort(keepIdx), :);

% attach each raw file's output path from the (now deduplicated) batch manifest
[tf, loc] = ismember(Rr.rawPath, manifest.rawPath);
Rr.outPath = strings(height(Rr),1);
Rr.outStatus = strings(height(Rr),1);
Rr.outPath(tf)   = manifest.outPath(loc(tf));
Rr.outStatus(tf) = manifest.status(loc(tf));

procs = unique(Rr.procName);
rows = cell(numel(procs),1);

for k = 1:numel(procs)
    p = procs(k);
    parts = Rr(Rr.procName == p, :);
    parts = sortrows(parts, 'rawFileNo');

    % the name used for the combined file's own disk name -- targetName if
    % supplied and found, procName otherwise (unchanged, original behaviour)
    outName = p;
    if useTargetNames
        hit = opts.TargetNames.targetName(opts.TargetNames.procName == p);
        if ~isempty(hit)
            outName = hit(1);
        else
            warning('combineMultipartOutputs:noTargetName', ...
                "No targetName found for procName '%s' -- falling back to procName for its disk filename and internal 'filename' column.", p);
        end
    end
    finalOut = fullfile(outFolder, outName + opts.Suffix + ".csv");
    ready = ["done","skipped_exists"];   % a RESUMED batch logs an already-present
                                          % file as "skipped_exists", not "done" --
                                          % both mean the output genuinely exists

    if height(parts) == 1
        if any(~ismember(parts.outStatus, ready))
            rows{k} = row(p, "", 1, NaN, parts.rawName(1), "skipped_incomplete", ...
                "raw file not yet processed by runMinICIBatch");
            continue
        end
        % single-file deployment: consolidate into outFolder alongside the
        % combined multi-part files, so every RESOLVED deployment ends up in
        % one place -- no need to track two folders/lists downstream.
        if isfile(finalOut) && ~opts.Overwrite
            rows{k} = row(p, string(finalOut), 1, NaN, parts.rawName(1), ...
                "passthrough", "already existed, not rewritten");
            continue
        end
        try
            if useTargetNames
                % rewrite the internal 'filename' column too, not just copy
                % the bytes -- a single-part deployment's own file was named
                % via MatchName, which SHOULD already equal targetName, but
                % this makes it certain rather than assumed
                Tone = readtable(parts.outPath(1), 'TextType', 'string');
                if ismember('filename', Tone.Properties.VariableNames)
                    Tone.filename = repmat(outName, height(Tone), 1);
                end
                writetable(Tone, finalOut);
            else
                copyfile(parts.outPath(1), finalOut);
            end
            rows{k} = row(p, string(finalOut), 1, NaN, parts.rawName(1), "passthrough", "");
        catch err
            rows{k} = row(p, "", 1, NaN, parts.rawName(1), "skipped_conflict", ...
                "could not copy " + parts.outPath(1) + " to outFolder: " + err.message);
        end
        continue
    end

    if any(~ismember(parts.outStatus, ready))
        missing = parts.rawName(~ismember(parts.outStatus, ready));
        rows{k} = row(p, "", height(parts), NaN, strjoin(parts.rawName,";"), ...
            "skipped_incomplete", "not yet processed: " + strjoin(missing, ", "));
        continue
    end

    % --- read every part, check for key collisions before merging --------
    T = cell(height(parts),1);
    ok = true; conflictNote = "";
    for j = 1:height(parts)
        try
            T{j} = readtable(parts.outPath(j), 'TextType', 'string');
        catch err
            ok = false;
            conflictNote = "could not read " + parts.outPath(j) + ": " + err.message;
            break
        end
    end

    if ok
        keyCols = intersect({'datetime','quality','species'}, T{1}.Properties.VariableNames);
        allKeys = strings(0,1);
        for j = 1:numel(T)
            k2 = string(T{j}.(keyCols{1}));
            for c = 2:numel(keyCols)
                k2 = k2 + "|" + string(T{j}.(keyCols{c}));
            end
            dupWithPrev = ismember(k2, allKeys);
            if any(dupWithPrev)
                ok = false;
                conflictNote = sprintf('%d row(s) in part %d collide with an earlier part on %s', ...
                    sum(dupWithPrev), j, strjoin(keyCols, ","));
                break
            end
            allKeys = [allKeys; k2]; %#ok<AGROW>
        end
    end

    if ~ok
        rows{k} = row(p, "", height(parts), NaN, strjoin(parts.rawName,";"), ...
            "skipped_conflict", conflictNote);
        continue
    end

    combinedT = vertcat(T{:});
    if ismember('datetime', combinedT.Properties.VariableNames)
        combinedT = sortrows(combinedT, {'datetime','quality'});
    end
    if useTargetNames && ismember('filename', combinedT.Properties.VariableNames)
        % THE core fix: each part's own row carried its own per-part
        % filename text (e.g. "..._file01", "..._file02") inherited from
        % whatever MatchName minICI_workflow ran under -- overwritten here so
        % every row in the combined file agrees on ONE deployment-level name,
        % which is what a name-text join (buildCrosswalkFromLookup) needs
        % and what window-matching (matchFilesToDeployments) never required.
        combinedT.filename = repmat(outName, height(combinedT), 1);
    end

    outFile = finalOut;
    if isfile(outFile) && ~opts.Overwrite
        rows{k} = row(p, string(outFile), height(parts), height(combinedT), ...
            strjoin(parts.rawName,";"), "combined", "already existed, not rewritten");
        continue
    end
    writetable(combinedT, outFile);

    rows{k} = row(p, string(outFile), height(parts), height(combinedT), ...
        strjoin(parts.rawName,";"), "combined", "");
end

combined = vertcat(rows{:});
printSummary(combined);
end

% =======================================================================
function T = row(procName, combinedPath, nParts, totalRows, sourceParts, status, note)
T = table(procName, string(combinedPath), nParts, totalRows, sourceParts, string(status), string(note), ...
    'VariableNames', {'procName','combinedPath','nParts','totalRows','sourceParts','status','note'});
end

function printSummary(combined)
fprintf('\n=== combineMultipartOutputs ===\n');
disp(groupsummary(combined, 'status'));

bad = combined(ismember(combined.status, ["skipped_conflict","skipped_incomplete"]), :);
if ~isempty(bad)
    fprintf('\n!! %d deployment(s) not combined -- resolve before matching to the database:\n', height(bad));
    disp(bad(:, {'procName','status','note'}));
end
fprintf('\n');
end

function opts = parseOpts(opts, args)
for k = 1:2:numel(args)
    name = validatestring(args{k}, fieldnames(opts));
    opts.(name) = args{k+1};
end
opts.Suffix = string(opts.Suffix);
end