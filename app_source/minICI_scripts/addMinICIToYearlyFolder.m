function summary = addMinICIToYearlyFolder(inFolder, minICIUpdatesFile, outFolder, varargin)
%ADDMINICITOYEARLYFOLDER Add MIN_ICI to every yearly DOI dataset file in a folder.
%
%   summary = addMinICIToYearlyFolder("...\yearly", "min_ici_updates.csv", "...\yearly_with_minici")
%
%   Loads the min_ici lookup ONCE (via buildMinICILookup) and reuses it for
%   every year -- re-reading and re-keying the update file per file would be
%   pure repeated overhead.
%
%   Resumable and fault-tolerant, same pattern as runMinICIBatch: a year whose
%   output already exists is skipped unless 'Overwrite' is set, and each file
%   runs inside try/catch so one bad file logs an error instead of losing the
%   whole run.
%
%   summary columns
%       inFile, outFile, totalRows, rowsFilled, dateOnlyTimeCount,
%       unmatchedQualityCodes, seconds, status, note
%
%   Check before handing anything over:
%     - rowsFilled should be > 0 for years overlapping the deployments this
%       project covered, and legitimately 0 for years it didn't touch
%     - unmatchedQualityCodes should be 0 everywhere; non-zero means a quality
%       value outside the mapping
%
%   Options
%       'FilePattern'  which files to process (default "*.csv")
%       'Suffix'       appended to each input name for the output
%                      (default "_with_minici")
%       'Overwrite'    redo files whose output exists (default false)
%       'Deduplicate'  remove exact full-row duplicates before the join
%                      (default true) -- passed through to
%                      addMinICIToYearlyDataset for every file
%       'QualityMap'   Nx2 cell array overriding {3,"Hi";2,"Mod";1,"Lo"}
%       'ProgressFcn'  handle called as fcn(fraction, message)
%
%   Part of the minICI back-fill toolset.

opts = struct('FilePattern', "*.csv", 'Suffix', "_with_minici", ...
    'Overwrite', false, 'Deduplicate', true, 'QualityMap', [], 'ProgressFcn', []);
opts = parseOpts(opts, varargin);

if ~isfolder(inFolder)
    error('addMinICIToYearlyFolder:noFolder', 'Not a folder: %s', inFolder);
end
if ~isfolder(outFolder), mkdir(outFolder); end

d = dir(fullfile(inFolder, opts.FilePattern));
d = d(~[d.isdir]);
if isempty(d)
    error('addMinICIToYearlyFolder:noFiles', ...
        'No files matching %s in %s', opts.FilePattern, inFolder);
end
files = string(fullfile({d.folder}, {d.name}))';

fprintf('Building the min_ici lookup once for %d file(s)...\n', numel(files));
L = buildMinICILookup(minICIUpdatesFile, opts.QualityMap);
fprintf('  %d lookup entries.\n', numel(L.keys));

n = numel(files);
inFile = strings(n,1); outFileCol = strings(n,1);
totalRows = nan(n,1); dupRemoved = nan(n,1); rowsFilled = nan(n,1); dateOnly = nan(n,1);
unmatchedQual = nan(n,1); secs = nan(n,1);
status = strings(n,1); note = strings(n,1);

tBatch = tic;
for k = 1:n
    inFile(k) = files(k);
    [~, base, ext] = fileparts(files(k));
    outPath = string(fullfile(outFolder, base + opts.Suffix + ext));
    outFileCol(k) = outPath;

    reportProgress(opts.ProgressFcn, k/n, sprintf('[%d/%d] %s', k, n, base));

    if isfile(outPath) && ~opts.Overwrite
        status(k) = "skipped_exists";
        continue
    end

    try
        r = addMinICIToYearlyDataset(files(k), "", outPath, 'Lookup', L, 'Deduplicate', opts.Deduplicate);
        totalRows(k)     = r.totalRows;
        dupRemoved(k)    = r.duplicateRowsRemoved;
        rowsFilled(k)    = r.rowsFilled;
        dateOnly(k)      = r.dateOnlyTimeCount;
        unmatchedQual(k) = r.unmatchedQualityCodes;
        secs(k)          = r.seconds;
        status(k)        = "done";
        fprintf('  %s: %d rows (%d duplicate removed), %d filled (%.1f s)\n', ...
            base, r.totalRows, r.duplicateRowsRemoved, r.rowsFilled, r.seconds);
    catch err
        status(k) = "error";
        note(k)   = err.message;
        fprintf('  %s: ERROR -- %s\n', base, err.message);
    end
end

summary = table(inFile, outFileCol, totalRows, dupRemoved, rowsFilled, dateOnly, unmatchedQual, secs, status, note, ...
    'VariableNames', {'inFile','outFile','totalRows','duplicateRowsRemoved','rowsFilled','dateOnlyTimeCount', ...
                      'unmatchedQualityCodes','seconds','status','note'});

printSummary(summary, toc(tBatch));
end

% =======================================================================
function printSummary(summary, elapsed)
fprintf('\n=== addMinICIToYearlyFolder ===\n');
disp(groupsummary(summary, 'status'));
done = summary(summary.status == "done", :);
fprintf('elapsed              : %.1f s (%.2f min)\n', elapsed, elapsed/60);
if ~isempty(done)
    fprintf('total rows processed : %d\n', sum(done.totalRows));
    fprintf('total duplicate rows removed : %d\n', sum(done.duplicateRowsRemoved));
    fprintf('total min_ici filled : %d\n', sum(done.rowsFilled));
    if any(done.unmatchedQualityCodes > 0)
        fprintf('!! file(s) with unmapped quality codes:\n');
        disp(done(done.unmatchedQualityCodes > 0, {'inFile','unmatchedQualityCodes'}));
    end
end
bad = summary(summary.status == "error", :);
if ~isempty(bad)
    fprintf('\n%d file(s) failed:\n', height(bad));
    disp(bad(:, {'inFile','note'}));
end
fprintf('\n');
end

function opts = parseOpts(opts, args)
for k = 1:2:numel(args)
    name = validatestring(args{k}, fieldnames(opts));
    opts.(name) = args{k+1};
end
opts.FilePattern = string(opts.FilePattern);
opts.Suffix      = string(opts.Suffix);
end

function reportProgress(fcn, frac, msg)
if isempty(fcn), fprintf('%s\n', msg); return; end
try, fcn(frac, msg); catch, fprintf('%s\n', msg); end
end