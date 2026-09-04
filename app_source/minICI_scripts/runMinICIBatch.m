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
%       'ProgressFcn'   handle called as fcn(fraction, message)
%
%   WorkflowMode
%       "writes_file"   called as WorkflowFcn(inPath, outPath); the function is
%                       expected to write outPath itself
%       "returns_table" called as T = WorkflowFcn(inPath); this function writes
%                       T to outPath with writetable
%       "auto"          tries "writes_file" first, and if outPath was not created
%                       but a table came back, treats it as "returns_table".
%                       Set the mode explicitly once you know which it is.
%
%   ALWAYS trial-run first: runMinICIBatch(reprocess, out, 'MaxFiles', 3), then
%   check those three with verifyMinICIAgainstArchive before turning it loose.
%
%   Part of the minICI back-fill toolset.

opts = struct('WorkflowFcn', [], 'WorkflowMode', "auto", 'Suffix', "_minICI", ...
    'Overwrite', false, 'ManifestFile', "", 'StopOnError', false, ...
    'MaxFiles', Inf, 'ProgressFcn', []);
opts = parseOpts(opts, varargin);

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
for k = 1:nRun
    inPath = fileList(k);
    [~, base] = fileparts(inPath);
    outPath = string(fullfile(outFolder, base + opts.Suffix + ".csv"));

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
    try
        runWorkflow(opts.WorkflowFcn, opts.WorkflowMode, inPath, outPath);
        el = toc(tFile);

        if ~isfile(outPath)
            rows{k} = logRow(mfid, inPath, base, outPath, "error", NaN, NaN, el, ...
                "workflow returned without writing an output file");
        else
            d = dir(outPath);
            rows{k} = logRow(mfid, inPath, base, outPath, "done", ...
                countDataRows(outPath), d.bytes, el, "");
        end
    catch err
        el = toc(tFile);
        rows{k} = logRow(mfid, inPath, base, outPath, "error", NaN, NaN, el, err.message);
        if opts.StopOnError
            manifest = vertcat(rows{1:k});
            rethrow(err);
        end
    end
end

manifest = vertcat(rows{:});
printSummary(manifest, toc(tBatch), opts.ManifestFile);
end

% =======================================================================
function runWorkflow(fcn, mode, inPath, outPath)
switch lower(string(mode))
    case "writes_file"
        fcn(inPath, outPath);
    case "returns_table"
        T = fcn(inPath);
        writetable(T, outPath);
    case "auto"
        try
            out = fcn(inPath, outPath);
            if ~isfile(outPath) && istable(out)
                writetable(out, outPath);      % it returned the table instead
            end
        catch
            T = fcn(inPath);                   % fall back to the 1-arg form
            if istable(T), writetable(T, outPath); else, rethrow(lasterror_struct()); end
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
opts.WorkflowMode = string(opts.WorkflowMode);
end

function reportProgress(fcn, frac, msg)
if isempty(fcn), fprintf('%s\n', msg); return; end
try, fcn(frac, msg); catch, fprintf('%s\n', msg); end
end
