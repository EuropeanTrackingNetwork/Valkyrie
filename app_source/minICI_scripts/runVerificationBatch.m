function [summary, reports] = runVerificationBatch(combined, proc, varargin)
%RUNVERIFICATIONBATCH Run verifyMinICIAgainstArchive over every resolved deployment.
%
%   [summary, reports] = runVerificationBatch(combined, proc)
%   [summary, reports] = runVerificationBatch(combined, proc, 'SaveTo', "verify_summary.csv")
%
%   combined   combineMultipartOutputs output -- rows with status "combined"
%              or "passthrough" are checked. Build this from [R; Rmanual] /
%              [manifest; manifestManual] so the manual deployments are
%              included too.
%   proc       surveyPodFiles output for the processed folders (must be the
%              SAME one used earlier -- it supplies the archive path for
%              each procName)
%
%   summary    one row per deployment:
%              procName, ok, sharedKeys, onlyInArchive, extrasInsideWindow,
%              duplicateKeysArchive, duplicateKeysNew, columnMismatches,
%              invariantOK, note
%              'note' is "pass" when ok, or an automated first-pass diagnosis
%              of what actually failed (see below) -- read it before assuming
%              a fail needs deep investigation; several categories point
%              straight at the cause.
%   reports    containers.Map, procName -> the full report struct
%              verifyMinICIAgainstArchive would have returned interactively.
%              To see the same detailed printout you'd get running it
%              directly on one file, just run it directly on that one file --
%              fast for a single file, and keeps the print logic in one place:
%                  r = verifyMinICIAgainstArchive(newFile, archiveFile);
%              or pull the stored report and inspect its fields yourself:
%                  r = reports("8010_2019_02_26_POD1981");
%                  disp(r.mismatchSamples)
%
%   Automated diagnosis categories in 'note'
%       "%d row(s) missing from new output"            -- real problem, the
%                                                          raw file may not
%                                                          cover the archive's
%                                                          full window
%       "%d unexpected extra row(s) inside archive window" -- real problem,
%                                                          check for an
%                                                          overlapping/wrong
%                                                          deployment match
%       "%d duplicate key(s) in NEW output"             -- real problem in
%                                                          the minICI output
%                                                          itself
%       "value mismatch in: <columns>"                  -- lists exactly
%                                                          which column(s)
%                                                          disagree
%       "%d row(s) with clicks but no min_ici" / vice versa -- computation
%                                                          gap worth checking
%       "min_ici count invariant failed, no other explanation found"
%                                                        -- genuinely needs a
%                                                          manual look; nothing
%                                                          else here explains it
%
%   Options
%       'SaveTo'      path for a .csv copy of summary
%       'ProgressFcn' handle called as fcn(fraction, message)
%
%   Part of the minICI back-fill toolset.

opts = struct('SaveTo', "", 'ProgressFcn', []);
opts = parseOpts(opts, varargin);

resolved = ismember(combined.status, ["combined","passthrough"]);
C = combined(resolved, :);

[tf, loc] = ismember(C.procName, proc.name);
if ~all(tf)
    warning('runVerificationBatch:noArchive', ...
        '%d deployment(s) in combined have no matching processed CSV in proc -- skipped: %s', ...
        sum(~tf), strjoin(C.procName(~tf), ', '));
end
C = C(tf, :);
archivePaths = proc.path(loc(tf));

n = height(C);
reports = containers.Map('KeyType','char','ValueType','any');

procName = strings(n,1); okCol = false(n,1); sharedKeys = zeros(n,1);
onlyInArchive = zeros(n,1); extrasInsideWindow = zeros(n,1);
dupArchive = zeros(n,1); dupNew = zeros(n,1); colMismatch = zeros(n,1);
invariantOK = false(n,1); note = strings(n,1);

for k = 1:n
    reportProgress(opts.ProgressFcn, k/n, sprintf('[%d/%d] %s', k, n, C.procName(k)));
    procName(k) = C.procName(k);

    try
        r = verifyMinICIAgainstArchive(C.combinedPath(k), archivePaths(k), 'Verbose', false);
    catch err
        note(k) = "ERROR running verification: " + err.message;
        continue
    end
    reports(char(C.procName(k))) = r; %#ok<NASGU>

    okCol(k) = r.ok;
    sharedKeys(k) = r.counts.sharedKeys;
    onlyInArchive(k) = r.counts.onlyInArchive;
    extrasInsideWindow(k) = r.counts.extrasInsideWindow;
    dupArchive(k) = r.counts.duplicateKeysArchive;
    dupNew(k) = r.counts.duplicateKeysNew;
    colMismatch(k) = sum(r.columns.mismatches(~isnan(r.columns.mismatches)));
    invariantOK(k) = r.iciChecks.countInvariantOK;

    if r.ok
        note(k) = "pass";
    else
        note(k) = diagnose(r, onlyInArchive(k), extrasInsideWindow(k), dupNew(k), colMismatch(k));
    end
end

summary = table(procName, okCol, sharedKeys, onlyInArchive, extrasInsideWindow, ...
    dupArchive, dupNew, colMismatch, invariantOK, note, ...
    'VariableNames', {'procName','ok','sharedKeys','onlyInArchive','extrasInsideWindow', ...
                      'duplicateKeysArchive','duplicateKeysNew','columnMismatches','invariantOK','note'});

printSummary(summary);

if strlength(opts.SaveTo) > 0
    writetable(summary, opts.SaveTo);
end
end

% =======================================================================
function n = diagnose(r, onlyInArchive, extrasInsideWindow, dupNew, colMismatch)
parts = strings(0,1);
if onlyInArchive > 0
    parts(end+1) = sprintf("%d row(s) missing from new output", onlyInArchive); %#ok<AGROW>
end
if extrasInsideWindow > 0
    parts(end+1) = sprintf("%d unexpected extra row(s) inside archive window", extrasInsideWindow); %#ok<AGROW>
end
if dupNew > 0
    parts(end+1) = sprintf("%d duplicate key(s) in NEW output", dupNew); %#ok<AGROW>
end
if colMismatch > 0
    badCols = r.columns.column(r.columns.mismatches > 0);
    parts(end+1) = "value mismatch in: " + strjoin(badCols, ", "); %#ok<AGROW>
end
if r.iciChecks.clicksButNoICI > 0
    parts(end+1) = sprintf("%d row(s) with clicks but no min_ici", r.iciChecks.clicksButNoICI); %#ok<AGROW>
end
if r.iciChecks.iciButNoClicks > 0
    parts(end+1) = sprintf("%d row(s) with min_ici but no clicks", r.iciChecks.iciButNoClicks); %#ok<AGROW>
end
if ~r.iciChecks.countInvariantOK && isempty(parts)
    parts(end+1) = "min_ici count invariant failed, no other explanation found -- investigate directly"; %#ok<AGROW>
end
if isempty(parts)
    parts = "FAIL but no specific cause matched -- investigate directly";
end
n = strjoin(parts, "; ");
end

function printSummary(summary)
fprintf('\n=== runVerificationBatch ===\n');
fprintf('total deployments checked : %d\n', height(summary));
fprintf('  pass                    : %d\n', sum(summary.ok));
fprintf('  fail                    : %d\n', sum(~summary.ok));
if any(~summary.ok)
    fprintf('\nfailures:\n');
    disp(summary(~summary.ok, {'procName','note'}));
end
fprintf('\n');
end

function opts = parseOpts(opts, args)
for k = 1:2:numel(args)
    name = validatestring(args{k}, fieldnames(opts));
    opts.(name) = args{k+1};
end
opts.SaveTo = string(opts.SaveTo);
end

function reportProgress(fcn, frac, msg)
if isempty(fcn), fprintf('%s\n', msg); return; end
try, fcn(frac, msg); catch, fprintf('%s\n', msg); end
end