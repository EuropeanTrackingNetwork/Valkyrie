function S = minICI_workflow(filePath, opts)
% MINICI_WORKFLOW  One-stop workflow to extract min_ici from a CP3 or FP3 file.
%
%   S = minICI_workflow(filePath)
%   S = minICI_workflow(filePath, 'PairPath', p, 'OutputCsv', c, ...)
%
% Give it the full path of a single detection file. It picks the right reader
% based on the extension (.CP3 -> CP3read_DTO, .FP3 -> FP3read_DTO), locates
% the paired .CP1/.FP1 noise file, runs CP3read_2_etn, and returns everything
% needed to join the result back onto novana-bpm.csv.
%
% INPUT
%   filePath   Full path to a .CP3 or .FP3 file (case-insensitive extension).
%
% NAME-VALUE OPTIONS
%   'PairPath'   Full path to the .CP1/.FP1 partner. Default '' = look for a
%                file with the same base name in the same folder.
%   'MatchName'  Name to use in the filename part of match_key. Default '' =
%                the file's own base name. Set this when novana-bpm stores a
%                different string than the file is called on disk - the POD
%                exports here are named e.g. "KF2O 2022 04 29 POD912 file01"
%                while novana-bpm holds "GB5 2012 11 15 POD909", with no
%                trailing " fileNN". Check your own files before batching.
%   'OutputCsv'  If non-empty, S.data is also written to this CSV path.
%   'Verbose'    true (default) prints progress to the command window.
%
% OUTPUT  S, a scalar struct:
%   S.source_file    full path of the CP3/FP3 file that was read
%   S.pair_file      full path of the CP1/FP1 file that was read
%   S.pod_type       'CPOD' or 'FPOD'
%   S.filename       base name without extension. This is the value that
%                    appears in novana-bpm's
%                    detections_file_train_duration_filename /
%                    detections_file_det_env_filename columns.
%   S.n_minutes      number of minutes read from the file
%   S.n_rows         height(S.data) = 3 * n_minutes (one row per quality class)
%   S.first_minute / S.last_minute   datetime range covered
%   S.data           table, one row per (minute x quality class), with a
%                    match_key column and column names matching novana-bpm
%   S.minutes        raw per-minute struct from the reader (train detail kept)
%   S.trains         raw per-train struct from the reader
%
% MATCHING BACK TO NOVANA-BPM
%   These files carry no id_pk, so rows are identified by the triple
%   (filename, datetime, quality), pre-joined for you in S.data.match_key:
%
%       "<filename>|<yyyy-MM-dd HH:mm:ss>|<quality>"
%
%   The equivalent key on the novana-bpm side is
%       detections_file_train_duration_filename | datetime | quality
%   The quality labels ('Hi','Mod','Lo') already match between the two.
%
% MIN_ICI UNITS AND MISSING VALUES
%   min_ici is the smallest inter-click interval, in MICROSECONDS, across all
%   NBHF trains of that quality class in that minute.
%   CP3read_2_etn leaves MIN_ICI at 0 for minutes with no qualifying train.
%   Because a genuine ICI of 0 is impossible, S.data.min_ici reports those as
%   NaN so they are not written to the database as real measurements. The
%   untouched value from CP3read_2_etn is kept in S.data.min_ici_raw.
%
% EXAMPLE
%   S = minICI_workflow('D:\POD\8013 2019 01 25 POD1776.CP3');
%   head(S.data)
%   S = minICI_workflow(f, 'OutputCsv', 'minici_8013.csv');
%
% Requires CP3read_DTO.m, FP3read_DTO.m, CP3read_2_etn.m and makeGtoAngle.m
% to be on the path (all live alongside this file).

arguments
    filePath          (1,:) char
    opts.PairPath     (1,:) char    = ''
    opts.MatchName    (1,:) char    = ''
    opts.OutputCsv    (1,:) char    = ''
    opts.Verbose      (1,1) logical = true
end

%% Make sure the reader functions are reachable
thisDir = fileparts(mfilename('fullpath'));
if ~isempty(thisDir) && ~ismember(thisDir, strsplit(path, pathsep))
    addpath(thisDir);
end

%% Resolve the input file and decide which reader to use
if exist(filePath, 'file') ~= 2
    error('minICI_workflow:fileNotFound', 'File not found: %s', filePath);
end

[folder, baseName, ext] = fileparts(filePath);
if isempty(folder)
    folder = pwd;
end

switch upper(ext)
    case '.CP3'
        podType = 'CPOD';
        pairExt = '.CP1';
        reader  = @CP3read_DTO;
    case '.FP3'
        podType = 'FPOD';
        pairExt = '.FP1';
        reader  = @FP3read_DTO;
    case {'.CP1', '.FP1'}
        error('minICI_workflow:wrongMember', ...
            ['"%s" is the noise half of the pair. Point the workflow at the ' ...
             '.CP3/.FP3 file instead; the .CP1/.FP1 is found automatically.'], ...
            [baseName ext]);
    otherwise
        error('minICI_workflow:unsupportedExtension', ...
            'Unsupported extension "%s". Expected .CP3 or .FP3.', ext);
end

%% Locate the paired CP1/FP1 file (needed for nall / number_clicks_total)
pairPath = opts.PairPath;
if isempty(pairPath)
    pairPath = fullfile(folder, [baseName pairExt]);
    if exist(pairPath, 'file') ~= 2
        % Fall back to a case-insensitive scan of the folder
        d   = dir(fullfile(folder, [baseName '.*']));
        hit = find(strcmpi({d.name}, [baseName pairExt]), 1);
        if isempty(hit)
            error('minICI_workflow:pairNotFound', ...
                ['No %s file found next to %s.\nCP3read_2_etn needs the nall ' ...
                 'column from the pair file, so processing cannot continue. ' ...
                 'Pass one explicitly with ''PairPath''.'], pairExt, [baseName ext]);
        end
        pairPath = fullfile(folder, d(hit).name);
    end
elseif exist(pairPath, 'file') ~= 2
    error('minICI_workflow:pairNotFound', 'PairPath not found: %s', pairPath);
end

if opts.Verbose
    fprintf('minICI_workflow: %s file "%s"\n', podType, baseName);
    fprintf('  detections : %s\n', fullfile(folder, [baseName ext]));
    fprintf('  noise pair : %s\n', pairPath);
end

%% Read the raw file
% '-n' tells the reader to also open the CP1/FP1 partner and fill in nall.
[minutes, trains] = reader(folder, baseName, '-n', pairPath);

% A file in which no minute contained any train never gets a "train" field,
% and CP3read_2_etn indexes it unconditionally. Add it back as empty.
if ~isfield(minutes, 'train')
    [minutes.train] = deal([]);
end
if ~isfield(minutes, 'nall')
    error('minICI_workflow:nallMissing', ...
        ['The reader returned no nall values, so the pair file was not read ' ...
         'successfully. Check that %s is a valid %s file.'], pairPath, pairExt);
end

if opts.Verbose
    fprintf('  read %d minutes, %d trains\n', numel(minutes), numel(trains));
end

%% Convert to the ETN layout (this is where MIN_ICI is calculated)
ETN = CP3read_2_etn(minutes);

%% Build the join-ready table
dt = ETN.DETECTION_DATE_TIME;
dt.Format = 'yyyy-MM-dd HH:mm:ss';

% filename as it will be joined on. The reader always returns the file's own
% base name; MatchName overrides it when novana-bpm spells it differently.
if isempty(opts.MatchName)
    matchName = baseName;
else
    matchName = opts.MatchName;
end
fnameCol = repmat(string(matchName), height(ETN), 1);
podfileCol = string(ETN.filename);
qualCol  = string(ETN.QUALITY);

% min_ici: keep the raw value, but blank out the placeholder zeros that mean
% "no qualifying train in this minute" rather than "an ICI of zero".
minIciRaw = double(ETN.MIN_ICI);
minIci    = minIciRaw;
minIci(double(ETN.NUMBER_CLICKS_FILTERED) == 0) = NaN;

T = table;
T.match_key                  = fnameCol + "|" + string(dt) + "|" + qualCol;
T.filename                   = fnameCol;
T.pod_file                   = podfileCol;
T.datetime                   = dt;
T.quality                    = qualCol;
T.min_ici                    = minIci;
T.min_ici_raw                = minIciRaw;
T.species                    = string(ETN.SPECIES);
T.number_clicks_filtered     = double(ETN.NUMBER_CLICKS_FILTERED);
T.number_clicks_total        = double(ETN.NUMBER_CLICKS_TOTAL);
T.detection_positive_minutes = double(ETN.DPM);
T.milliseconds               = double(ETN.MILLISECONDS);
T.temperature                = double(ETN.TEMPERATURE);
T.angle                      = double(ETN.ANGLE);
T.time_lost_percentage       = double(ETN.TIME_LOST_PERCENTAGE);
T.recorded                   = double(ETN.RECORDED);

T = sortrows(T, {'datetime', 'quality'});

% The key must be unique or the join back into novana-bpm is ambiguous.
[uniqueKeys, ~, keyIdx] = unique(T.match_key);
if numel(uniqueKeys) ~= height(T)
    counts  = accumarray(keyIdx, 1);
    dupKeys = uniqueKeys(counts > 1);
    warning('minICI_workflow:duplicateKeys', ...
        ['%d of %d match_key values are not unique (e.g. "%s"). This usually ' ...
         'means the file contains repeated minute timestamps.'], ...
        height(T) - numel(uniqueKeys), height(T), dupKeys(1));
end

%% Assemble the output structure
S = struct();
S.source_file  = fullfile(folder, [baseName ext]);
S.pair_file    = pairPath;
S.pod_type     = podType;
S.filename     = matchName;
S.pod_file     = baseName;
S.n_minutes    = numel(minutes);
S.n_rows       = height(T);
S.first_minute = min(T.datetime);
S.last_minute  = max(T.datetime);
S.data         = T;
S.minutes      = minutes;
S.trains       = trains;

if opts.Verbose
    nWithIci = sum(~isnan(T.min_ici));
    fprintf('  %d rows (%s to %s), %d with a real min_ici\n', ...
        S.n_rows, string(S.first_minute), string(S.last_minute), nWithIci);
end

%% Optional CSV export
if ~isempty(opts.OutputCsv)
    writetable(T, fullfile(opts.OutputCsv, [S.filename, '_minICI.csv'])); 
    if opts.Verbose
        fprintf('  wrote %s\n', opts.OutputCsv);
    end
end

end
