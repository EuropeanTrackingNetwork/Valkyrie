
% Test the import function of C-/F-POD files

% Import function is developed by J. MacAulay
% Link to functions: https://github.com/macster110/fpodmat/tree/main

%%  Call in functions
addpath(genpath('C:\Users\au335296\OneDrive - Aarhus universitet\Documents\MATLAB\DTO_BioFlow\POD_Upload\cpodutils'));

%% Get file paths of multiple files
[files, path] = uigetfile('*.*', 'MultiSelect','on') ;
SelectedFilePath = fullfile(path, files);

%% Or use these to test
%CFPOD .CP1 file
CP1podfile = 'O:\Tech_Novana-Marsvin\CPODS\DATA\__DataCleanedForHELCOM\TextFileProcessed\LB__LittleBelt_Processed\LB1\LB1E 2013 02 06 POD1988 file01 PART 54d 1m.CP1';

%CPOD .CP3 file
CP3podfile = 'O:\Tech_Novana-Marsvin\CPODS\DATA\__DataCleanedForHELCOM\TextFileProcessed\LB__LittleBelt_Processed\LB1\LB1E 2013 02 06 POD1988 file01 PART 54d 1m.CP3';

%FPOD FP1 file
FP1podfile = 'O:\Tech_Novana-Marsvin\FPOD\DATA\CPODvFPOD\processed_FPOD\MDF1A 2020 10 27 FPOD_6311 series1 file0.FP1';

%FPOD FP3 file 
FP3podfile = 'O:\Tech_Novana-Marsvin\FPOD\DATA\CPODvFPOD\processed_FPOD\MDF1A 2020 10 27 FPOD_6311 series2 file0.FP3';

podfilepath = {CP1podfile, CP3podfile, FP1podfile, FP3podfile};

%% Load pod data

i=1;
%import the data
[podData] = importpoddata(podfilepath{i}, 'detstart', 0, 'maxdet', 10000); % specifying to import the first N clicks
disp(['Imported ' num2str(length(podData)) ' clicks']);

%% Example plot of the amplitude of recorded clicks

ampdB = [podData.ampdB];
frequency = [podData.freqcenter];
date = [podData.date]; 

c = frequency/1000; 

scatter(date, ampdB, 10, frequency, 'filled'); 
ylabel('Amplitude (dB)'); 
set(gca, 'FontSize', 14)


