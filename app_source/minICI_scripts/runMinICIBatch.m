function manifest = runMinICIBatch(fileList, outFolder, varargin)
%RUNMINICIBATCH Run minICI_workflow over a list of raw POD files, resumably.
%
%   manifest = runMinICIBatch(reprocess, "O:\...\VALKYRIEoutput\minICI")
%   manifest = runMinICIBatch(reprocess, outFolder, 'WorkflowFcn', @minICI_workflow)
%
%   fileList   string array of raw file paths (the second output of
%              matchRawToProcessed)
%   outFolder  destination for the per-file minICI CSVs; created if absent
%
%   Built for a run long enough that something will go wrong partway through:
%
%     * Resumable. A file whose output already exists is skipped, so the batch
%       can be stopped and restarted without redoing work. 'Overwrite',true
%       forces a redo.
%     * Fault tolerant. Each file runs inside try/catch, so one unreadable POD
%       file logs an error and the batch continues instead of losing the run.
%     * Logged incrementally. The manifest row is appended to disk after every
%       file, so a crash or a force-quit still leaves a complete record of what
%       was done. This is also the filename provenance the database team needs:
%       one row per raw file -> output file.
%
%   Manifest columns
%       rawPath, rawName, outPath, status, rows, bytes, seconds, errorMessage
%
%   Statuses: done, skipped_exists, error, missing_input
%
%   Options
%       'WorkflowFcn'   handle to the processing function. Default @minICI_workflow.
%       'WorkflowMode'  how that function is called (see below). Default "auto".
%       'Suffix'        appended to the input name for the output (default "_minICI")
%       'Overwrite'     redo files whose output exists (default false)
%       'ManifestFile'  path for the incremental log. Default
%                       fullfile(outFolder,"minICI_batch_manifest.csv")
%       'StopOnError'   abort on the first failure instead of logging (default false)
%       'MaxFiles'      process at most N files -- use a small value for a trial run
%       'StageLocally'  copy each raw file to local disk before calling the
%                       workflow, run against the local copy, then copy just the
%                       (small) CSV result back to outFolder (default false).
%                       Worth turning on when fileList lives on a network/VPN
%                       drive: most raw-file readers do many scattered small
%                       reads inside the file, and that pattern is dominated by
%                       per-operation round-trip latency over a network link,
%                       not bandwidth. A single bulk sequential copy pays for
%                       the network cost once instead of once per internal
%                       read, which is often the actual cause when a single
%                       file takes an unexpectedly long time to process despite
%                       not being unusually large.
%       'LocalStageFolder' where local copies go (default a subfolder of
%                       tempdir()). Cleaned up per file regardless of success.
%       'CopyRetries'   retries for each network<->local copy under
%                       'StageLocally' before giving up (default 10). Each
%                       retry uses robocopy's /Z (restartable mode) on
%                       Windows, which RESUMES an interrupted copy instead of
%                       restarting from byte 0 -- without it, a connection
%                       that reliably dies ~60-70s into a large transfer makes
%                       zero net progress no matter how many retries you allow,
%                       since every attempt dies at the same point. With /Z,
%                       retries are cumulative.
%       'CopyRetryWaitSec' seconds between copy retries (default 10)
%       'PairPaths'     table with columns rawPath, pairPath -- when the file
%                       currently being processed matches a rawPath here, its
%                       pairPath is passed as minICI_workflow's 'PairPath'.
%                       comp (findCompanionRawFiles output) renamed to
%                       {rawPath, pairPath}, filtered to companionStatus=="found",
%                       is exactly this table.
%       'MatchNames'    table with columns rawPath, matchName -- passed as
%                       minICI_workflow's 'MatchName', the string novana-bpm
%                       actually stores for this deployment (which can differ
%                       from the raw file's own base name -- exactly the
%                       problem matchRawToProcessed's procName solves). Build
%                       from R directly: R(:, {'rawPath','procName'}) renamed
%                       to {rawPath, matchName}. Not required for correctness
%                       of anything downstream in this toolset (extraction
%                       keys off deployment_fk from the crosswalk, never off
%                       the output file's own filename column), but worth
%                       setting so the output file is self-consistent.
%       'WorkflowVerbose' passed as minICI_workflow's 'Verbose' (default true)
%       'ProgressFcn'   handle called as fcn(fraction, message)
%
%   WorkflowMode
%       "minici_workflow" (default) matches minICI_workflow's actual, confirmed
%                       signature: S = minICI_workflow(inPath, 'PairPath', p,
%                       'OutputCsv', outPath, 'MatchName', m, 'Verbose', v).
%                       ONE positional argument, everything else name-value;
%                       it writes outPath itself via 'OutputCsv' and returns a
%                       struct (not a table) that this mode uses for the
%                       manifest's row count (S.n_rows) when available.
%       "writes_file"   generic fallback: called as WorkflowFcn(inPath, outPath).
%                       Not minICI_workflow's real signature -- use
%                       "minici_workflow" for that. Kept for other functions.
%       "returns_table" generic fallback: T = WorkflowFcn(inPath); this mode
%                       writes T to outPath with writetable.
%       "auto"          tries "writes_file" first, falls back to
%                       "returns_table". Avoid with minICI_workflow specifically
%                       -- neither generic mode matches its real signature, and
%                       the very error that triggers the fallback here is
%                       usually the real problem, not something to fall through.
%
%   ALWAYS trial-run first: runMinICIBatch(reprocess, out, 'MaxFiles', 3), then
%   check those three with verifyMinICIAgainstArchive before turning it loose.
%
%   Part of the minICI back-fill toolset.

opts = struct('WorkflowFcn', [], 'WorkflowMode', "minici_workflow", 'Suffix', "_minICI", ...
    'Overwrite', false, 'ManifestFile', "", 'StopOnError', false, ...
    'MaxFiles', Inf, 'StageLocally', false, 'LocalStageFolder', "", ...
    'CopyRetries', 10, 'CopyRetryWaitSec', 10, 'PairPaths', [], 'MatchNames', [], ...
    'WorkflowVerbose', true, 'ProgressFcn', []);
opts = parseOpts(opts, varargin);

if ~isempty(opts.PairPaths) && ~istable(opts.PairPaths)
    error('runMinICIBatch:badPairPaths', ...
        '''PairPaths'' must be a table with columns rawPath, pairPath (e.g. comp renamed).');
end

if opts.StageLocally && strlength(opts.LocalStageFolder) == 0
    opts.LocalStageFolder = string(fullfile(tempdir, "minICI_stage"));
end
if opts.StageLocally && ~isfolder(opts.LocalStageFolder)
    mkdir(opts.LocalStageFolder);
end

if isempty(opts.WorkflowFcn)
    if exist('minICI_workflow', 'file') ~= 2
        error('runMinICIBatch:noWorkflow', ...
            ['minICI_workflow was not found on the MATLAB path and no ' ...
             '''WorkflowFcn'' was supplied. Add its folder with addpath, or pass ' ...
             'the handle explicitly.']);
    end
    opts.WorkflowFcn = @minICI_workflow;
end

fileList = string(fileList(:));
if isinf(opts.MaxFiles)
    nRun = numel(fileList);
else
    nRun = min(numel(fileList), opts.MaxFiles);
    fprintf('Trial run: processing %d of %d file(s).\n', nRun, numel(fileList));
end
fileList = fileList(1:nRun);

if ~isfolder(outFolder), mkdir(outFolder); end
if strlength(opts.ManifestFile) == 0
    opts.ManifestFile = string(fullfile(outFolder, "minICI_batch_manifest.csv"));
end

% open the manifest in append mode so a restart adds to the existing record
newManifest = ~isfile(opts.ManifestFile);
mfid = fopen(opts.ManifestFile, 'a');
if mfid < 0
    error('runMinICIBatch:cannotWriteManifest', 'Cannot open %s', opts.ManifestFile);
end
cleanup = onCleanup(@() fclose(mfid));
if newManifest
    fprintf(mfid, 'rawPath,rawName,outPath,status,rows,bytes,seconds,errorMessage\n');
end

rows = cell(nRun,1);
tBatch = tic;
isMinICIMode = lower(string(opts.WorkflowMode)) == "minici_workflow";
for k = 1:nRun
    inPath = fileList(k);
    [~, base] = fileparts(inPath);
    pairPath  = lookupPairPath(opts.PairPaths, inPath, "pairPath");
    matchName = lookupPairPath(opts.MatchNames, inPath, "matchName");

    if isMinICIMode
        % minICI_workflow treats 'OutputCsv' as a FOLDER and names the file
        % itself as <MatchName or its own base name>_minICI.csv inside it --
        % NOT the exact file path passed in, despite the docstring calling it
        % a "CSV path". Predict that name so skip-if-exists and the manifest
        % track the file it will actually write.
        effectiveName = base;
        if strlength(matchName) > 0, effectiveName = matchName; end
        outPath = string(fullfile(outFolder, effectiveName + "_minICI.csv"));
    else
        outPath = string(fullfile(outFolder, base + opts.Suffix + ".csv"));
    end

    reportProgress(opts.ProgressFcn, k/nRun, ...
        sprintf('[%d/%d] %s', k, nRun, base));

    if ~isfile(inPath)
        rows{k} = logRow(mfid, inPath, base, outPath, "missing_input", NaN, NaN, 0, ...
            "input file not found");
        continue
    end
    if isfile(outPath) && ~opts.Overwrite
        d = dir(outPath);
        rows{k} = logRow(mfid, inPath, base, outPath, "skipped_exists", NaN, d.bytes, 0, "");
        continue
    end

    tFile = tic;
    localIn = ""; localOut = ""; localPair = "";
    nRowsFromS = NaN;
    try
        if opts.StageLocally
            [~, ib, ie] = fileparts(inPath);
            localIn = string(fullfile(opts.LocalStageFolder, ib + ie));
            try
                copyFileRobust(inPath, localIn, opts.CopyRetries, opts.CopyRetryWaitSec);
            catch cerr
                error('runMinICIBatch:stageInFailed', ...
                    'staging raw file in from network drive failed: %s', cerr.message);
            end

            usePair = pairPath;
            if strlength(pairPath) > 0
                [~, pb, pe] = fileparts(pairPath);
                localPair = string(fullfile(opts.LocalStageFolder, pb + pe));
                try
                    copyFileRobust(pairPath, localPair, opts.CopyRetries, opts.CopyRetryWaitSec);
                    usePair = localPair;
                catch cerr
                    error('runMinICIBatch:stageInFailed', ...
                        'staging pair file in from network drive failed: %s', cerr.message);
                end
            end

            if isMinICIMode
                effectiveName = base;
                if strlength(matchName) > 0, effectiveName = matchName; end
                localOut = string(fullfile(opts.LocalStageFolder, effectiveName + "_minICI.csv"));
            else
                localOut = string(fullfile(opts.LocalStageFolder, base + opts.Suffix + ".csv"));
            end
            nRowsFromS = runWorkflow(opts.WorkflowFcn, opts.WorkflowMode, localIn, localOut, ...
                usePair, matchName, opts.WorkflowVerbose);

            if isfile(localOut)
                try
                    copyFileRobust(localOut, outPath, opts.CopyRetries, opts.CopyRetryWaitSec);
                catch cerr
                    error('runMinICIBatch:stageOutFailed', ...
                        'copying result back to the network drive failed: %s', cerr.message);
                end
            end
        else
            nRowsFromS = runWorkflow(opts.WorkflowFcn, opts.WorkflowMode, inPath, outPath, ...
                pairPath, matchName, opts.WorkflowVerbose);
        end
        el = toc(tFile);

        if ~isfile(outPath)
            rows{k} = logRow(mfid, inPath, base, outPath, "error", NaN, NaN, el, ...
                "workflow returned without writing an output file");
        else
            d = dir(outPath);
            nRows = nRowsFromS;
            if isnan(nRows), nRows = countDataRows(outPath); end
            rows{k} = logRow(mfid, inPath, base, outPath, "done", nRows, d.bytes, el, "");
        end
    catch err
        el = toc(tFile);
        rows{k} = logRow(mfid, inPath, base, outPath, "error", NaN, NaN, el, err.message);
        if opts.StopOnError
            cleanupLocal(localIn, localOut, localPair);
            manifest = vertcat(rows{1:k});
            rethrow(err);
        end
    end
    cleanupLocal(localIn, localOut, localPair);
end

manifest = vertcat(rows{:});
printSummary(manifest, toc(tBatch), opts.ManifestFile);
end

% =======================================================================
function copyFileRobust(src, dst, maxRetries, waitSec)
%COPYFILEROBUST Copy one file, surviving transient network drive errors.
%
%plain copyfile has no retry logic, so a brief VPN/SMB hiccup partway through a
%multi-minute copy of a large raw file kills the whole transfer with an opaque
%"unexpected network error". On Windows this uses robocopy with /Z
%(restartable mode) and built-in retry (/R) + wait-between (/W). /Z matters
%more than the retry count: without it, a connection that reliably dies at a
%fixed point in the transfer (a session/idle timeout, not random packet loss)
%makes every retry restart from byte 0 and die at the same point again --
%observed in practice as 6 retries, 6 failures at ~60-70s each, zero net
%progress. /Z resumes from wherever the previous attempt stopped, so retries
%accumulate progress instead of repeating the same failed segment. Elsewhere
%(non-Windows) this retries copyfile itself with a pause between attempts,
%which has no equivalent resume capability.
if ispc
    [srcDir, srcName, srcExt] = fileparts(src);
    [dstDir, ~, ~] = fileparts(dst);
    if ~isfolder(dstDir), mkdir(dstDir); end
    fname = srcName + srcExt;

    cmd = sprintf('robocopy "%s" "%s" "%s" /Z /J /R:%d /W:%d /NFL /NDL /NJH /NJS', ...
        srcDir, dstDir, fname, maxRetries, waitSec);
    [status, cmdout] = system(cmd);
    % robocopy's exit code is a bitmask where 0-7 mean success (0 = nothing
    % copied because it already matched, 1 = copied OK); 8+ is a real failure.
    % This is NOT the usual "0 = success" convention -- do not simplify.
    if status >= 8
        error('copyFileRobust:robocopyFailed', 'robocopy exit code %d: %s', status, cmdout);
    end
    destFile = fullfile(dstDir, fname);
    if ~isfile(destFile)
        error('copyFileRobust:notWritten', 'robocopy reported success but %s was not created', destFile);
    end
    if destFile ~= string(dst)
        movefile(destFile, dst);   % dst may ask for a different filename than the source
    end
else
    lastErr = [];
    for attempt = 1:maxRetries
        try
            [ok, msg] = copyfile(src, dst);
            if ok, return, end
            lastErr = MException('copyFileRobust:copyfileFailed', '%s', msg);
        catch lastErr
        end
        if attempt < maxRetries, pause(waitSec); end
    end
    rethrow_or_throw(lastErr);
end
end

function rethrow_or_throw(e)
% e may be a freshly built MException (copyfile returned ok=false without
% erroring) or one actually caught (copyfile threw). throw() accepts both;
% rethrow() only accepts the latter and errors on the former.
throw(e);
end

function cleanupLocal(localIn, localOut, localPair)
if nargin < 3, localPair = ""; end
if strlength(localIn) > 0 && isfile(localIn)
    try, delete(localIn); catch, end
end
if strlength(localOut) > 0 && isfile(localOut)
    try, delete(localOut); catch, end
end
if strlength(localPair) > 0 && isfile(localPair)
    try, delete(localPair); catch, end
end
end

function v = lookupPairPath(tbl, inPath, valueCol)
v = "";
if isempty(tbl), return, end
if ~ismember(valueCol, string(tbl.Properties.VariableNames))
    error('runMinICIBatch:badLookupTable', ...
        'Expected a column named ''%s'' (plus ''rawPath'') in this table.', valueCol);
end
hit = find(tbl.rawPath == inPath, 1);
if ~isempty(hit), v = tbl.(valueCol)(hit); end
end

function nRows = runWorkflow(fcn, mode, inPath, outPath, pairPath, matchName, verbose)
if nargin < 5, pairPath = ""; end
if nargin < 6, matchName = ""; end
if nargin < 7, verbose = true; end
nRows = NaN;

switch lower(string(mode))
    case "minici_workflow"
        % S = minICI_workflow(inPath, 'PairPath', p, 'OutputCsv', outFolder,
        %                      'MatchName', m, 'Verbose', v)
        % ONE positional argument; everything else is name-value. Despite the
        % docstring calling 'OutputCsv' a "CSV path", it is actually treated
        % as a FOLDER: minICI_workflow builds its own filename inside it as
        % <MatchName or its own base name>_minICI.csv, ignoring any filename
        % in whatever path is passed. outPath here is the FULL predicted path
        % the caller already computed with matching logic -- fileparts() just
        % recovers the folder half of it to hand over.
        [outFolderForCsv, ~, ~] = fileparts(outPath);
        nv = {'OutputCsv', outFolderForCsv, 'Verbose', verbose};
        if strlength(pairPath) > 0,  nv = [nv, {'PairPath', pairPath}];   end
        if strlength(matchName) > 0, nv = [nv, {'MatchName', matchName}]; end
        S = fcn(inPath, nv{:});
        if isstruct(S) && isfield(S, 'n_rows')
            nRows = S.n_rows;
        end

    case "writes_file"
        extra = {};
        if strlength(pairPath) > 0, extra = {'PairPath', pairPath}; end
        fcn(inPath, outPath, extra{:});

    case "returns_table"
        extra = {};
        if strlength(pairPath) > 0, extra = {'PairPath', pairPath}; end
        T = fcn(inPath, extra{:});
        writetable(T, outPath);

    case "auto"
        extra = {};
        if strlength(pairPath) > 0, extra = {'PairPath', pairPath}; end
        try
            out = fcn(inPath, outPath, extra{:});
            if ~isfile(outPath) && istable(out)
                writetable(out, outPath);      % it returned the table instead
            end
        catch
            T = fcn(inPath, extra{:});         % fall back to the 1-arg form
            if istable(T)
                writetable(T, outPath);
            else
                % T is not a table and fcn(inPath,...) alone did not error,
                % so there is nothing caught here to legitimately rethrow --
                % throw() (not rethrow()) works on a freshly built
                % MException; rethrow() specifically requires one that was
                % previously thrown and caught, and errors on a fresh one.
                throw(lasterror_struct());
            end
        end

    otherwise
        error('runMinICIBatch:badMode', 'Unknown WorkflowMode "%s"', mode);
end
end

function e = lasterror_struct()
e = MException('runMinICIBatch:workflowFailed', ...
    ['minICI_workflow failed with both the 2-argument (inPath,outPath) and ' ...
     '1-argument (inPath) calling conventions. Set ''WorkflowMode'' explicitly ' ...
     'and check the function''s signature.']);
end

function n = countDataRows(f)
%COUNTDATAROWS Line count minus the header. Approximate: over-counts if any
%quoted field contains an embedded newline.
n = NaN;
try
    fid = fopen(f, 'r');
    if fid < 0, return, end
    c = onCleanup(@() fclose(fid));
    n = 0;
    while ~feof(fid)
        block = fread(fid, 1e6, '*char')';
        n = n + count(string(block), newline);
    end
    n = max(0, n - 1);
catch
    n = NaN;
end
end

function T = logRow(mfid, inPath, base, outPath, status, rows, bytes, secs, errMsg)
T = table(inPath, string(base), outPath, string(status), rows, bytes, secs, string(errMsg), ...
    'VariableNames', {'rawPath','rawName','outPath','status','rows','bytes','seconds','errorMessage'});
fprintf(mfid, '%s,%s,%s,%s,%s,%s,%.2f,%s\n', ...
    csvq(inPath), csvq(base), csvq(outPath), status, ...
    numOrEmpty(rows), numOrEmpty(bytes), secs, csvq(errMsg));
end

function s = numOrEmpty(v)
if isnan(v), s = ""; else, s = string(v); end
end

function s = csvq(s)
%CSVQ Minimal CSV quoting -- paths contain commas and spaces, error messages
%contain commas, quotes and newlines.
s = string(s);
s = replace(s, """", """""");
s = replace(s, newline, " ");
s = replace(s, sprintf('\r'), " ");
s = """" + s + """";
end

function printSummary(manifest, elapsed, manifestFile)
fprintf('\n=== runMinICIBatch ===\n');
if isempty(manifest)
    fprintf('nothing processed\n\n'); return
end
disp(groupsummary(manifest, 'status'));

done = manifest(manifest.status == "done", :);
fprintf('elapsed            : %.1f s (%.2f min)\n', elapsed, elapsed/60);
if ~isempty(done)
    fprintf('mean per file      : %.1f s\n', mean(done.seconds));
    fprintf('rows written total : %d\n', sum(done.rows(~isnan(done.rows))));
    remaining = height(manifest) - height(done);
    if remaining == 0 && ~isempty(done)
        fprintf('projected for 1000 more files: %.1f min\n', 1000*mean(done.seconds)/60);
    end
end
fprintf('manifest           : %s\n', manifestFile);

err = manifest(manifest.status == "error", :);
if ~isempty(err)
    fprintf('\n!! %d file(s) failed:\n', height(err));
    disp(err(1:min(10,height(err)), {'rawName','errorMessage'}));
end
fprintf('\n');
end

function opts = parseOpts(opts, args)
for k = 1:2:numel(args)
    name = validatestring(args{k}, fieldnames(opts));
    opts.(name) = args{k+1};
end
opts.Suffix       = string(opts.Suffix);
opts.ManifestFile = string(opts.ManifestFile);
opts.LocalStageFolder = string(opts.LocalStageFolder);
opts.WorkflowMode = string(opts.WorkflowMode);
end

function reportProgress(fcn, frac, msg)
if isempty(fcn), fprintf('%s\n', msg); return; end
try, fcn(frac, msg); catch, fprintf('%s\n', msg); end
end