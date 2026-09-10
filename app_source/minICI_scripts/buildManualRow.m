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
%                   correct -- must exist in rawU.path (run
%                   surveyPodFiles/collapseRawCopies first if it doesn't;
%                   this function does not search the filesystem itself)
%   proc            surveyPodFiles output for the processed folders
%   rawU            collapseRawCopies output for the raw folders
%
%   For a multi-part deployment, call this once per part and vertically
%   concatenate the results -- rawFileNo comes straight from rawU, so parts
%   naturally get distinct numbers and combineMultipartOutputs groups/sorts
%   them correctly without any extra work:
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

rawRow = rawU(rawU.path == chosenRawPath, :);
if isempty(rawRow)
    error('buildManualRow:rawNotFound', ...
        ['chosenRawPath not found in rawU:\n  %s\n' ...
         'Was this folder actually covered by the raw survey? Re-run ' ...
         'surveyPodFiles/collapseRawCopies if not, and check for a typo ' ...
         'or capitalisation difference against what dir() shows on disk.'], chosenRawPath);
end
if height(rawRow) > 1
    rawRow = rawRow(1,:);
end

row = table(procRow.path, procRow.name, procRow.podId, procRow.stationBase, procRow.nameDate, ...
    rawRow.path, rawRow.name, rawRow.ext, rawRow.nameDate, rawRow.fileNo, rawRow.nCopies, ...
    "matched", "manually resolved -- not an automated candidate", NaT, NaT, ...
    'VariableNames', {'procPath','procName','podId','stationBase','procDate', ...
                      'rawPath','rawName','rawExt','rawDate','rawFileNo','rawNCopies', ...
                      'status','note','windowLo','windowHi'});
end