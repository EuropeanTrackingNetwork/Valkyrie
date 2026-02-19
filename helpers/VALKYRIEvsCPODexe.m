
% Script to validate the output from CP3read_DTO.m against CPOD.exe output.

% WHen extracting pod data in CPOD.exe and FPOD.exe the default setting is
% to only include Hi and Med quality clicks. However, in ETN (and in
% Valkyrie) detections are extracted for all three qualities. Therefore,
% valkyrie outout will only match with POD.exe output if the Lo quality is
% also inlcuded. 

% Load the output from CPOD.exe
[file, path] = uigetfile('*.*', 'MultiSelect','on') ;
fname = fullfile(path,file);
CPOD_output = readtable(fname);

% Load the output from the CP3read_DTO.m - a full detection file from
% Valkyrie or just from the script
[file, path] = uigetfile('*.*', 'MultiSelect','on') ;
fname = fullfile(path,file);
valkyrie_output = readtable(fname);

% Does numbers of rows match?
% OBS: only work for comparing valkyrie output for single detection file
n_val = height(valkyrie_output)/3; % divide by three because Valkyrie output is split in to Lo, Med and Hi qualities

disp('The difference between the CPOD.exe output and Valkyrie output is:');
disp(height(CPOD_output)-n_val);

% Match the timestamps to check if all minutes have data
% CPOD data has to combine the date and time columns:
dtStr = string(CPOD_output{:,2});     % returns cell array of char
DT = datetime(dtStr, 'InputFormat', 'dd/MM/yyyy HH:mm');
DT.Format = 'yyyy-MM-dd HH:mm:ss';  
CPOD_output.DT = DT;

% Then we can check the two datetime columns against each other - finding
% where datetimes are missing:
T = outerjoin(CPOD_output, valkyrie_output, 'LeftKeys', 'DT', 'RightKeys', 'DETECTION_DATE_TIME');

% How many rows are missing for the datetime (since NaT will display if
% only datetime in one of the tables)
missing_cpod = sum(ismissing(T.DETECTION_DATE_TIME));
missing_valk = sum(ismissing(T.DT));

% What timestamps are missing and from where?
if missing_cpod>0 
    disp(['Missing CPOD timestamps: ', num2str(missing_cpod)]);
    % the position of the timestamps in the dataset
    missing_positions = find(ismissing(T.DETECTION_DATE_TIME));
    disp('Positions of missing CPOD timestamps:');
    length(missing_positions);
end
if missing_valk > 0
    disp(['Missing Valkyrie timestamps: ', num2str(missing_valk)]);
    missing_positions = find(ismissing(T.DT));
    disp('Positions of missing CPOD timestamps:');
    length(missing_positions);
end


% Check the number of Nall clicks in a minute

cpod_Nall = CPOD_output.Nall_m;
CPOD_output.cpod_Nall = cpod_Nall;
% Replace empty -> zero (no detections)
CPOD_output.cpod_Nall = fillmissing(CPOD_output.cpod_Nall, 'constant', 0);

valk_Nall = groupsummary(valkyrie_output, 'DETECTION_DATE_TIME', 'sum', 'NUMBER_CLICKS_TOTAL');
valk_Nall.sum_NUMBER_CLICKS_TOTAL = valk_Nall.sum_NUMBER_CLICKS_TOTAL/3;
valk_Nall.Properties.VariableNames{'sum_NUMBER_CLICKS_TOTAL'} = 'Valkyrie_Nall';

C = outerjoin(CPOD_output, valk_Nall, ...
    'LeftKeys','DT', 'RightKeys','DETECTION_DATE_TIME', ...
    'MergeKeys', true);


C.Nall_diff = C.cpod_Nall - C.Valkyrie_Nall;

n_mismatch = sum(C.Nall_diff ~= 0 & ~isnan(C.Nall_diff));

if n_mismatch == 0
    disp('[PASS] Nall values match for all minutes');
else
    fprintf('[FAIL] %d minute(s) have mismatched Nall values\n', n_mismatch);
end


disp('First 10 mismatches (if any):');

mismatches = C(C.Nall_diff ~= 0, ...
    {'DT_DETECTION_DATE_TIME','cpod_Nall','Valkyrie_Nall','Nall_diff'});
disp(mismatches(1:min(10, height(mismatches)), :));


% Check that there are the same number of NBHF clicks

% In the Valkyrie detections: check that number of train clicks sum to the
% number of clicks in Lo, Med, Hi


