
%% Match ETN detection output to minICI detections

%% Re-process a handful of files and verify

% path to a raw pod file (CP3 or FP3)
raw_file = "O:\Tech_Novana-Marsvin\CPODS\DATA\2011-2016\GreatBelt_RawData\GB1\GB1A\GB1 2011 11 09 POD1685 file01.CP3";

% % This will take the raw file and run it through the same processing as
% within Valkyrie but will add minICI as a column instead of bpm
detection_minICI = minICI_workflow(raw_file);

% % The output can be compared to the correpsonding VALKYRIE detection output

%% Check a few files before moving on to bulk processing
% % This will show a comparison between two files and how well they match.
% If there a places they don't match this will be displayed.
Det_minICI = "O:\Tech_Novana-Marsvin\DTO\VALKYRIEoutput\minICI_files\GB1 2011 11 09 POD1685 file01_minICI.csv";
Det_bpm = "O:\Tech_Novana-Marsvin\DTO\VALKYRIEoutput\2011-2017\Detection files\GB1_2011_06_23_POD1685.csv";

report = verifyMinICIAgainstArchive( ...
    Det_minICI, ...
    Det_bpm);

if ~report.ok
    disp(report.columns)
    disp(report.mismatchSamples)
end



%% Make an index file for the ETN detection file
% % This step can take a long time
% % Output is one row per source (deployment_fk)

% path to the ETN detection document
% % This is a very large file (13GB) 
novana_bpm = "O:\Tech_Novana-Marsvin\DTO\novana-bpm.csv";

tic;
idx = buildDeploymentIndex(novana_bpm, ...
    'Delimiter', ',', 'DatetimeFormat', 'yyyy-MM-dd HH:mm:ss', ...
    'SaveTo', 'O:\Tech_Novana-Marsvin\DTO\deployment_index.mat', ...
    'ProgressFcn', @(frac, msg) fprintf('[%.1f%%] %s\n', frac*100, msg));
toc

%% Get filenames from folders
% % We now have extracted an index from the full novana_bpm and verified
% that the minICI_workflow works to process the raw files. 

% % Next step is to get the filenames for all processed files (with bpm)
% and all raws file, to compare which raw files needs to be reprocessed.

proc = surveyPodFiles([ ...
    "O:\Tech_Novana-Marsvin\DTO\VALKYRIEoutput\2011-2017\Detection files\Split files"
    "O:\Tech_Novana-Marsvin\DTO\VALKYRIEoutput\2017-2021\Split files"], ...
    'Extensions', "csv", 'SaveTo', "O:\Tech_Novana-Marsvin\DTO\minICI_updates\processedFiles_inventory.mat");

raw = surveyPodFiles([ ...
    "O:\Tech_Novana-Marsvin\CPODS\DATA\2011-2016"
    "O:\Tech_Novana-Marsvin\CPODS\DATA\Bornholm 2018-2019\CP1 all"
    "O:\Tech_Novana-Marsvin\CPODS\DATA\2017-2021"], ...
    'Extensions', ["cp1","cp3","fp1","fp3"], 'SaveTo', "O:\Tech_Novana-Marsvin\DTO\minICI_updates\rawFiles_inventory.mat");

%% Match using novana_bpm index
% load("O:\Tech_Novana-Marsvin\DTO\deployment_index.mat")

% Keep only one copy if more with exact same name exists
rawU = collapseRawCopies(raw, ...
    'FolderPreference', ["NOVANA_2017-21", "RawData"], ...
    'SaveTo', "O:\Tech_Novana-Marsvin\DTO\minICI_updates\rawFiles_unique.mat");

[R, reprocess] = matchRawToProcessed(proc, rawU, 'Index', idx, ...
    'RawExtensions', ["cp3","fp3"], 'WindowPad', days(45), ...
    'SaveTo', "O:\Tech_Novana-Marsvin\DTO\minICI_updates\match_raw_to_processed.csv");
% Will save a file with info on what matched, and where there were some
% ambiguity - good thing to go thorugh it before used to batch process


%% Give summary of minICI files in folder
minICIpath = "O:\Tech_Novana-Marsvin\DTO\VALKYRIEoutput\minICI_files";

% % This step can only run once a bulk of the raw data has been reprocessed
% to get the minICI
S = scanMinICIOutputs(minICIpath, 'SaveTo', "O:\Tech_Novana-Marsvin\DTO\VALKYRIEoutput\matchedICIfiles\minici_scan.mat");

%% Match the new minICI files to the index
% % Look into where some miss matches may arise
% % Be sure to check before moving on

% load index if it is not already
% load("O:\Tech_Novana-Marsvin\DTO\deployment_index.mat")
X = matchFilesToDeployments(S, idx, 'SaveTo', "O:\Tech_Novana-Marsvin\DTO\VALKYRIEoutput\matchedICIfiles\crosswalk.csv");
disp(groupsummary(X, 'status'))

%% Make new csv with only verified matches
rep = extractMinICIUpdates(novana_bpm, X, "O:\Tech_Novana-Marsvin\DTO\VALKYRIEoutput\matchedICIfiles\min_ici_updates.csv", ...
    'UnmatchedCsv', "O:\Tech_Novana-Marsvin\DTO\VALKYRIEoutput\matchedICIfiles\min_ici_unmatched.csv");