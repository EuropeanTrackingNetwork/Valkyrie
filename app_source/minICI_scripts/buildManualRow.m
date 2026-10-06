function row = buildManualRow(procName, chosenRawPath, proc, rawU)
%BUILDMANUALROW Build one R-compatible row for a manually-chosen raw file.
%
%   row = buildManualRow(procName, chosenRawPath, proc, rawU)
%
%   Produces a single-row table with the exact same columns as
%   matchRawToProcessed's output R, status set to "matched", so it can be
%   vertically concatenated with R (or with other manual rows) and fed
%   straight into runMinICIBatch / combineMultipartOutputs /
%   runVerificationBatch without any special-casing downstream.
%
%   procName        the processed deployment's own name, e.g.
%                   "KF4_2012_02_11_POD1691" -- must exist in proc.name
%   chosenRawPath   full path to the raw .cp3/.fp3 file you've determined is
%                   correct
%   proc            surveyPodFiles output for the processed folders
%   rawU            collapseRawCopies output for the raw folders
%
%   chosenRawPath is looked up in rawU first (the common case: your pick IS
%   the representative collapseRawCopies already kept). If it's not there --
%   which happens whenever the same-named file exists in more than one
%   folder and collapseRawCopies happened to keep a DIFFERENT copy as the
%   canonical one -- this falls back to reading the file directly off disk
%   (parsePodName + a real isfile/dir check) and builds the row from that
%   instead. A manual pick is an intentional override of collapseRawCopies'
%   choice, so it should work on any real file, not only the one that
%   happened to survive deduplication.
%
%   For a multi-part deployment, call this once per part and vertically
%   concatenate the results:
%
%       row1 = buildManualRow("KF1_2012_02_13_POD1693", ".../KF1C ... file01.CP3", proc, rawU);
%       row2 = buildManualRow("KF1_2012_02_13_POD1693", ".../KF1C ... file02.CP3", proc, rawU);
%       Rmanual = [row1; row2];
%
%   Part of the minICI back-fill toolset.

procRow = proc(proc.name == procName, :);
if isempty(procRow)
    error('buildManualRow:procNotFound', 'procName "%s" not found in proc.', procName);
end
if height(procRow) > 1
    procRow = procRow(1,:);
end

chosenRawPath = string(chosenRawPath);
rawRow = rawU(rawU.path == chosenRawPath, :);

if ~isempty(rawRow)
    if height(rawRow) > 1, rawRow = rawRow(1,:); end
    rawName = rawRow.name; rawExt = rawRow.ext; rawDate = rawRow.nameDate;
    rawFileNo = rawRow.fileNo; rawNCopies = rawRow.nCopies;
else
    % Not in rawU -- collapseRawCopies kept a different copy of this same
    % name as the representative. Build fresh from the real file on disk
    % rather than requiring it to already be that representative.
    if ~isfile(chosenRawPath)
        error('buildManualRow:rawNotFound', ...
            ['chosenRawPath does not exist on disk and is not in rawU:\n  %s\n' ...
             'Check for a typo/extension mismatch against what dir() shows for this folder.'], ...
             chosenRawPath);
    end
    warning('buildManualRow:notInRawU', ...
        ['%s exists on disk but is not the copy collapseRawCopies kept for this name -- ' ...
         'building this row directly from the file instead of overriding that choice. ' ...
         'rawNCopies is unknown (NaN) since this bypasses collapseRawCopies entirely.'], ...
         chosenRawPath);

    [~, base, extDot] = fileparts(chosenRawPath);
    rawExt = lower(erase(string(extDot), "."));
    P = parsePodName(string(base));
    rawName = string(base);
    rawDate = P.nameDate;
    rawFileNo = P.fileNo;
    rawNCopies = NaN;
end

row = table(procRow.path, procRow.name, procRow.podId, procRow.stationBase, procRow.nameDate, ...
    chosenRawPath, rawName, rawExt, rawDate, rawFileNo, rawNCopies, ...
    "matched", "manually resolved -- not an automated candidate", NaT, NaT, ...
    'VariableNames', {'procPath','procName','podId','stationBase','procDate', ...
                      'rawPath','rawName','rawExt','rawDate','rawFileNo','rawNCopies', ...
                      'status','note','windowLo','windowHi'});
end