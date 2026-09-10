function rep = buildPublicationExport(bigCsv, updatesCsv, outCsv, varargin)
%BUILDPUBLICATIONEXPORT Full novana_bpm replacement CSV for DOI/publication.
%
%   rep = buildPublicationExport(bigCsv, updatesCsv, outCsv)
%
%   This is a DIFFERENT deliverable from extractMinICIUpdates, but built
%   DIRECTLY FROM ITS OUTPUT rather than re-deriving anything. This one is the
%   FULL table: every row of bigCsv, in the same column order and CSV quoting
%   style, with:
%     - detection_bpm REMOVED (the app no longer produces it)
%     - min_ici FILLED IN wherever extractMinICIUpdates found a value
%     - every other column passed through UNCHANGED, byte-for-byte where
%       possible (read and re-emitted as text, not reparsed/reformatted, so
%       passthrough columns cannot silently drift in precision or format)
%
%   bigCsv       the full novana_bpm export (comma-delimited, quoted fields,
%                ISO datetimes -- see inspectBigFile)
%   updatesCsv   the id_pk,min_ici,... CSV produced by extractMinICIUpdates,
%                covering EVERY reprocessed file -- the full batch AND the 6
%                hand-resolved deployments. Run extractMinICIUpdates on the
%                complete set FIRST; a partial updatesCsv quietly produces a
%                partial publication file with no visible sign anything is
%                missing, the wrong failure mode for something going out
%                under a DOI.
%   outCsv       destination path (full path -- see note in this toolset's
%                history about relative paths landing in the wrong place).
%                Needs roughly as much free disk space as bigCsv itself.
%
%   Why key off id_pk instead of re-matching
%   ------------------------------------------
%   extractMinICIUpdates already did the hard part once: it matched every row
%   by (deployment_fk, datetime, quality), cross-checked number_clicks_filtered
%   and milliseconds before accepting each value, and resolved everything down
%   to id_pk -- the database's actual unique row identifier. Re-deriving that
%   matching a second time here, independently, would risk the published file
%   and the database update silently disagreeing if the two pieces of logic
%   ever diverged. Keying off id_pk instead means both deliverables come from
%   the exact same validated mapping by construction -- a plain lookup, not a
%   second round of matching.
%
%   rep fields
%       totalRows        rows read from bigCsv (== rows written -- a full
%                         passthrough, not a sparse update)
%       rowsFilled        rows where min_ici was substituted
%       updateRows        rows read from updatesCsv
%       unusedUpdateRows  id_pk values from updatesCsv never found in bigCsv --
%                         should be EXACTLY 0 (id_pk is a true unique key, so
%                         this is exact, not approximate); investigate if not
%       columnsDropped    confirms detection_bpm was found and removed
%
%   Options
%       'ReadSize'      rows per chunk (default 200000)
%       'BigDelimiter'  default "," (confirmed via inspectBigFile)
%       'ProgressFcn'   handle called as fcn(fraction, message)
%
%   Part of the minICI back-fill toolset.

opts = struct('ReadSize', 200000, 'BigDelimiter', ",", 'ProgressFcn', []);
opts = parseOpts(opts, varargin);

%% ---- load the already-validated id_pk -> min_ici mapping ------------------
reportProgress(opts.ProgressFcn, 0, 'Loading the id_pk/min_ici update file...');
U = readtable(updatesCsv, 'TextType', 'string');
need = ["id_pk","min_ici"];
missingCols = setdiff(need, string(U.Properties.VariableNames));
if ~isempty(missingCols)
    error('buildPublicationExport:badUpdatesFile', ...
        'updatesCsv is missing column(s): %s. Is this extractMinICIUpdates'' output?', ...
        strjoin(missingCols, ', '));
end

idKeys = string(U.id_pk);
minVals = double(U.min_ici);
updateMap = containers.Map(cellstr(idKeys), num2cell(minVals));
idxMap    = containers.Map(cellstr(idKeys), num2cell(1:height(U)));
updateRows = height(U);
usedMask = false(updateRows,1);
reportProgress(opts.ProgressFcn, 0.05, sprintf('%d update row(s) loaded.', updateRows));

%% ---- stream the full file, passthrough + substitute -----------------------
ds = tabularTextDatastore(bigCsv, 'TextType', 'string', 'ReadSize', opts.ReadSize, ...
    'Delimiter', char(opts.BigDelimiter));
allVars = string(ds.VariableNames);
outVars = allVars(lower(allVars) ~= "detection_bpm");
if numel(outVars) == numel(allVars)
    warning('buildPublicationExport:noBpmColumn', ...
        '''detection_bpm'' was not found in %s -- nothing to drop; check the column name.', bigCsv);
end
ds.SelectedVariableNames = cellstr(allVars);   % read everything; drop bpm at write time

% Force every column to STRING type. Without this, a numeric-looking column
% like temperature ("0.0", "18.0" in the source) gets auto-detected as double
% and silently reformatted on the way back out (0.0 -> "0"), which breaks the
% byte-for-byte passthrough this function exists to guarantee.
ds.VariableTypes(:) = {'string'};

if ~ismember("id_pk", allVars)
    error('buildPublicationExport:noIdPk', '''id_pk'' column not found in %s.', bigCsv);
end

fid = fopen(outCsv, 'w');
if fid < 0, error('buildPublicationExport:cannotWrite', 'Cannot open %s', outCsv); end
cleanupFid = onCleanup(@() fclose(fid));
fwrite(fid, joinQuoted(outVars) + newline, 'char');

totalRows = 0; rowsFilled = 0; chunkNo = 0;

while hasdata(ds)
    C = read(ds); chunkNo = chunkNo + 1;
    n = height(C);
    totalRows = totalRows + n;

    outMinIci = C.min_ici;   % passthrough by default -- untouched original text
    filled = false(n,1);
    ids = cellstr(C.id_pk);

    for i = 1:n
        if ~isKey(updateMap, ids{i}), continue, end
        outMinIci(i) = string(sprintf('%.10g', updateMap(ids{i})));
        filled(i) = true;
        usedMask(idxMap(ids{i})) = true;
    end

    C.min_ici = outMinIci;
    rowsFilled = rowsFilled + sum(filled);

    writeChunk(fid, C, outVars);

    reportProgress(opts.ProgressFcn, NaN, sprintf( ...
        'Chunk %d: %d rows (%d filled) -- %d total so far', chunkNo, n, sum(filled), totalRows));
end

%% ---- report ----------------------------------------------------------
rep = struct();
rep.totalRows       = totalRows;
rep.rowsFilled      = rowsFilled;
rep.updateRows      = updateRows;
rep.unusedUpdateRows = sum(~usedMask);   % exact: id_pk is a true unique key
rep.columnsDropped  = setdiff(allVars, outVars);

fprintf('\n=== buildPublicationExport ===\n');
fprintf('rows read / written        : %d / %d\n', totalRows, totalRows);
fprintf('min_ici values filled      : %d\n', rowsFilled);
fprintf('update rows offered        : %d\n', updateRows);
fprintf('update rows never matched  : %d   (must be 0 -- exact, not approximate)\n', rep.unusedUpdateRows);
fprintf('column(s) dropped          : %s\n', strjoin(rep.columnsDropped, ', '));
fprintf('output                     : %s\n', outCsv);
if rep.unusedUpdateRows > 0
    fprintf(['\n!! Some id_pk values in updatesCsv were never seen in bigCsv. This should be\n' ...
             '   impossible if updatesCsv was produced from THIS SAME bigCsv -- check you are\n' ...
             '   pointing at the same export extractMinICIUpdates actually ran against.\n']);
end
fprintf('\n');
end

% =======================================================================
function s = joinQuoted(vals)
q = """" + replace(string(vals), """", """""") + """";
s = strjoin(q, ",");
end

function writeChunk(fid, C, outVars)
n = height(C);
cols = strings(n, numel(outVars));
for c = 1:numel(outVars)
    v = C.(char(outVars(c)));
    if ~isstring(v), v = string(v); end
    v(ismissing(v)) = "";
    isEmpty = (v == "");
    q = """" + replace(v, """", """""") + """";
    q(isEmpty) = "";   % the source file leaves empty fields completely
                        % unquoted (e.g. "0.0"||||"2026-..." -- nothing
                        % between the delimiters, not ""), so an empty
                        % min_ici must match that exactly, not become a
                        % quoted empty string
    cols(:,c) = q;
end
rowStr = cols(:,1);
for c = 2:size(cols,2)
    rowStr = rowStr + "," + cols(:,c);
end
blob = strjoin(rowStr, newline) + newline;
fwrite(fid, blob, 'char');
end

function opts = parseOpts(opts, args)
for k = 1:2:numel(args)
    name = validatestring(args{k}, fieldnames(opts));
    opts.(name) = args{k+1};
end
opts.BigDelimiter = string(opts.BigDelimiter);
end

function reportProgress(fcn, frac, msg)
if isempty(fcn), fprintf('%s\n', msg); return; end
try, fcn(frac, msg); catch, fprintf('%s\n', msg); end
end