function combined = combineMultipartOutputs(R, manifest, outFolder, varargin)
%COMBINEMULTIPARTOUTPUTS Concatenate per-part minICI outputs into one file per deployment.
%
%   combined = combineMultipartOutputs(R, manifest, outFolder)
%
%   R          matchRawToProcessed output (procName, rawPath, status, rawFileNo, ...)
%   manifest   runMinICIBatch output (rawPath, outPath, status)
%   outFolder  destination for the combined files
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
%       'Suffix'    appended to procName for the combined filename
%                   (default "_minICI_combined")
%       'Overwrite' redo a combined file that already exists (default false)
%
%   Part of the minICI back-fill toolset.

opts = struct('Suffix', "_minICI_combined", 'Overwrite', false);
opts = parseOpts(opts, varargin);

if ~isfolder(outFolder), mkdir(outFolder); end

resolved = ["matched","matched_multipart","matched_nearest"];
Rr = R(ismember(R.status, resolved) & ~ismissing(R.rawPath), :);

% attach each raw file's output path from the batch manifest
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
    finalOut = fullfile(outFolder, p + opts.Suffix + ".csv");
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
            copyfile(parts.outPath(1), finalOut);
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