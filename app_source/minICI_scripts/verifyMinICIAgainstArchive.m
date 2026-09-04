function report = verifyMinICIAgainstArchive(newFile, archiveFile, varargin)
%VERIFYMINICIAGAINSTARCHIVE Check a minICI re-run against the archived detection file.
%
%   report = verifyMinICIAgainstArchive(newFile, archiveFile)
%   report = verifyMinICIAgainstArchive(newFile, archiveFile, 'ReportFile', 'out.csv')
%
%   newFile      CSV produced by the minICI script (match_key, filename, pod_file,
%                datetime, quality, min_ici, min_ici_raw, species, ...)
%   archiveFile  the detection CSV that was originally uploaded to the database
%                (DETECTION_DATE_TIME, TEMPERATURE, ANGLE, ...)
%
%   The two files are joined on datetime + quality + species -- NOT on filename,
%   because the archive name uses the deployment date and the minICI name uses
%   whatever date is in the POD filename.
%
%   Rows present only in the new file are reported separately rather than counted
%   as failures: the archived exports were trimmed to the in-water window, while
%   the minICI script exports the whole POD file. Extras that fall INSIDE the
%   archive window, or any row missing from the new file, are real problems.
%
%   report fields
%       .ok               true if every shared column matches on every shared key
%       .columns          per-column comparison table
%       .counts           row/key counts, extras split into before/inside/after
%       .mismatchSamples  up to 20 example rows per mismatching column
%       .iciChecks        min_ici sanity checks (see below)
%       .files            the two paths and the parsed name components
%
%   Part of the minICI back-fill toolset.

arguments_in = struct('ReportFile', "", 'MaxSamples', 20, 'ProgressFcn', []);
arguments_in = parseOpts(arguments_in, varargin);
tick = @(msg) reportProgress(arguments_in.ProgressFcn, msg);

%% ---- read -------------------------------------------------------------
tick('Reading new minICI file...');
N = readMinICIFile(newFile);
tick('Reading archived detection file...');
A = readArchiveFile(archiveFile);

report = struct();
report.files = struct('newFile', string(newFile), 'archiveFile', string(archiveFile), ...
    'newName', parsePodName(N.filename(1)), 'archiveName', parsePodName(A.filename(1)));

%% ---- keys ------------------------------------------------------------
tick('Building keys...');
kN = detectionKey(N.datetime, N.quality, N.species);
kA = detectionKey(A.datetime, A.quality, A.species);

dupN = numel(kN) - numel(unique(kN));
dupA = numel(kA) - numel(unique(kA));

[inBoth_A, locN] = ismember(kA, kN);
onlyInArchive = ~inBoth_A;
onlyInNew     = ~ismember(kN, kA);

aWinStart = min(A.datetime);
aWinEnd   = max(A.datetime);
extraDt   = N.datetime(onlyInNew);

report.counts = struct( ...
    'archiveRows',      height(A), ...
    'newRows',          height(N), ...
    'duplicateKeysArchive', dupA, ...
    'duplicateKeysNew',     dupN, ...
    'sharedKeys',       sum(inBoth_A), ...
    'onlyInArchive',    sum(onlyInArchive), ...
    'onlyInNew',        sum(onlyInNew), ...
    'extrasBeforeWindow', sum(extraDt <  aWinStart), ...
    'extrasInsideWindow', sum(extraDt >= aWinStart & extraDt <= aWinEnd), ...
    'extrasAfterWindow',  sum(extraDt >  aWinEnd), ...
    'archiveWindow',    [aWinStart aWinEnd], ...
    'newWindow',        [min(N.datetime) max(N.datetime)]);

%% ---- column-by-column on the shared keys -----------------------------
tick('Comparing shared columns...');
idxA = find(inBoth_A);
idxN = locN(inBoth_A);

pairs = { ...
    'temperature',            'temperature'
    'angle',                  'angle'
    'number_clicks_total',    'number_clicks_total'
    'number_clicks_filtered', 'number_clicks_filtered'
    'detection_positive_minutes','detection_positive_minutes'
    'milliseconds',           'milliseconds'
    'time_lost_percentage',   'time_lost_percentage'
    'recorded',               'recorded'
    'species',                'species'};

names = strings(0,1); nMis = []; pct = []; present = strings(0,1);
report.mismatchSamples = struct();

for p = 1:size(pairs,1)
    cA = pairs{p,1}; cN = pairs{p,2};
    if ~ismember(cA, A.Properties.VariableNames) || ~ismember(cN, N.Properties.VariableNames)
        names(end+1,1) = string(cA);            %#ok<AGROW>
        nMis(end+1,1)  = NaN;                   %#ok<AGROW>
        pct(end+1,1)   = NaN;                   %#ok<AGROW>
        present(end+1,1) = "missing from one file"; %#ok<AGROW>
        continue
    end
    va = A.(cA)(idxA);
    vn = N.(cN)(idxN);
    if isstring(va) || iscellstr(va) %#ok<ISCLSTR>
        bad = ~strcmp(string(va), string(vn));
    else
        bad = ~(va == vn | (isnan(double(va)) & isnan(double(vn))));
    end
    names(end+1,1)   = string(cA);              %#ok<AGROW>
    nMis(end+1,1)    = sum(bad);                %#ok<AGROW>
    pct(end+1,1)     = 100*mean(bad);           %#ok<AGROW>
    present(end+1,1) = "compared";              %#ok<AGROW>

    if any(bad)
        s = find(bad); s = s(1:min(arguments_in.MaxSamples, numel(s)));
        report.mismatchSamples.(cA) = table( ...
            A.datetime(idxA(s)), A.quality(idxA(s)), va(s), vn(s), ...
            'VariableNames', {'datetime','quality','archive','new'});
    end
end

report.columns = table(names, present, nMis, pct, ...
    'VariableNames', {'column','status','mismatches','pctMismatch'});

%% ---- columns that exist only in the archive ---------------------------
archiveOnlyCols = setdiff(A.Properties.VariableNames, ...
    [N.Properties.VariableNames, {'filename','pod_file','datetime','quality'}]);
report.archiveOnlyColumns = string(archiveOnlyCols);

%% ---- min_ici sanity ---------------------------------------------------
tick('Checking min_ici...');
hasICI  = ~ismissing(N.min_ici);
clicks  = N.number_clicks_filtered > 0;
inWin   = N.datetime >= aWinStart & N.datetime <= aWinEnd;

report.iciChecks = struct( ...
    'nWithICI',              sum(hasICI), ...
    'nWithICI_inWindow',     sum(hasICI & inWin), ...
    'archiveClickPositive',  sum(A.number_clicks_filtered > 0), ...
    'clicksButNoICI',        sum(clicks & ~hasICI), ...
    'iciButNoClicks',        sum(~clicks & hasICI), ...
    'minValue',              min(N.min_ici(hasICI)), ...
    'medianValue',           median(N.min_ici(hasICI)), ...
    'maxValue',              max(N.min_ici(hasICI)));
% the key invariant: every archived row with filtered clicks must get a value
report.iciChecks.countInvariantOK = ...
    report.iciChecks.nWithICI_inWindow == report.iciChecks.archiveClickPositive;

%% ---- verdict ----------------------------------------------------------
report.ok = report.counts.onlyInArchive == 0 ...
    && report.counts.extrasInsideWindow == 0 ...
    && report.counts.duplicateKeysNew == 0 ...
    && all(report.columns.mismatches(~isnan(report.columns.mismatches)) == 0) ...
    && report.iciChecks.clicksButNoICI == 0 ...
    && report.iciChecks.iciButNoClicks == 0 ...
    && report.iciChecks.countInvariantOK;

printReport(report);

if strlength(arguments_in.ReportFile) > 0
    writetable(report.columns, arguments_in.ReportFile);
end
end

% =======================================================================
function T = readMinICIFile(f)
opts = detectImportOptions(f, 'TextType', 'string');
opts = setvartype(opts, intersect({'filename','pod_file','quality','species','match_key'}, ...
    opts.VariableNames), 'string');
opts = setvartype(opts, intersect({'min_ici','min_ici_raw'}, opts.VariableNames), 'double');
T = readtable(f, opts);
T.datetime = toDatetime(T.datetime);
end

function T = readArchiveFile(f)
opts = detectImportOptions(f, 'TextType', 'string');
T = readtable(f, opts);
% normalise the archive's upper-case headers onto the new file's names
map = { ...
    'DETECTION_DATE_TIME',   'datetime'
    'QUALITY',               'quality'
    'SPECIES',               'species'
    'TEMPERATURE',           'temperature'
    'ANGLE',                 'angle'
    'NUMBER_CLICKS_TOTAL',   'number_clicks_total'
    'NUMBER_CLICKS_FILTERED','number_clicks_filtered'
    'DPM',                   'detection_positive_minutes'
    'MILLISECONDS',          'milliseconds'
    'BPM',                   'detection_bpm'
    'TIME_LOST_PERCENTAGE',  'time_lost_percentage'
    'RECORDED',              'recorded'
    'PODfile',               'pod_file'};
for k = 1:size(map,1)
    if ismember(map{k,1}, T.Properties.VariableNames)
        T.Properties.VariableNames{map{k,1}} = map{k,2};
    end
end
T.datetime = toDatetime(T.datetime);
end

function dt = toDatetime(v)
if isdatetime(v)
    dt = v;
else
    dt = datetime(string(v), 'InputFormat', 'yyyy-MM-dd HH:mm:ss');
end
dt.Format = 'yyyy-MM-dd HH:mm:ss';
end

function k = detectionKey(dt, quality, species)
%DETECTIONKEY Canonical within-file row key. Minute resolution: the database
%holds one row per minute per quality per species.
k = string(dt, 'yyyy-MM-dd HH:mm:ss') + "|" + upper(string(quality)) + "|" + upper(string(species));
end

function opts = parseOpts(opts, args)
for k = 1:2:numel(args)
    name = validatestring(args{k}, fieldnames(opts));
    opts.(name) = args{k+1};
end
if isstring(opts.ReportFile) == false, opts.ReportFile = string(opts.ReportFile); end
end

function reportProgress(fcn, msg)
if ~isempty(fcn), fcn(msg); end
end

function printReport(r)
c = r.counts;
fprintf('\n=== minICI verification ===\n');
fprintf('new     : %s\n', r.files.newFile);
fprintf('archive : %s\n', r.files.archiveFile);
fprintf('POD id  : new %d / archive %d\n', r.files.newName.podId, r.files.archiveName.podId);
fprintf('window  : archive %s -> %s\n', c.archiveWindow(1), c.archiveWindow(2));
fprintf('          new     %s -> %s\n', c.newWindow(1), c.newWindow(2));
fprintf('rows    : archive %d, new %d, shared keys %d\n', c.archiveRows, c.newRows, c.sharedKeys);
fprintf('missing from new (FAIL if >0)   : %d\n', c.onlyInArchive);
fprintf('extra inside window (FAIL if >0): %d\n', c.extrasInsideWindow);
fprintf('extra before / after window     : %d / %d  (expected: POD on/off periods)\n', ...
    c.extrasBeforeWindow, c.extrasAfterWindow);
fprintf('\n');
disp(r.columns);
if ~isempty(r.archiveOnlyColumns)
    fprintf('columns in archive but not in minICI output: %s\n', strjoin(r.archiveOnlyColumns, ', '));
end
i = r.iciChecks;
fprintf('\nmin_ici: %d values (%d in window); archive click-positive rows %d; invariant %s\n', ...
    i.nWithICI, i.nWithICI_inWindow, i.archiveClickPositive, string(i.countInvariantOK));
fprintf('         clicks but no ICI %d, ICI but no clicks %d\n', i.clicksButNoICI, i.iciButNoClicks);
fprintf('         range %g .. %g us (median %g)\n', i.minValue, i.maxValue, i.medianValue);
fprintf('\nVERDICT: %s\n\n', string(r.ok));
end
