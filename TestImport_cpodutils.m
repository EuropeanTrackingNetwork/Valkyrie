
% Test the import function of C-/F-POD files

% Import function is developed by J. MacAulay
% Link to functions: https://github.com/macster110/fpodmat/tree/main
%% Get file paths of multiple files
[files, path] = uigetfile('*.*', 'MultiSelect','on') ;
SelectedFilePath = fullfile(path, files);

%% Or use these to test
%CFPOD .CP1 file
CP1podfile = 'O:\Tech_Novana-Marsvin\CPODS\DATA\__DataCleanedForHELCOM\TextFileProcessed\FB__FermernBelt_Processed\FB1\FB1J 2015 04 16 POD1981 file01 PART 62d 1m.CP1';

%CPOD .CP3 file
CP3podfile = 'O:\Tech_Novana-Marsvin\CPODS\DATA\__DataCleanedForHELCOM\TextFileProcessed\FB__FermernBelt_Processed\FB1\FB1K 2015 09 30 POD1776 file01 PART 41d 52m.CP3';

%FPOD FP1 file
FP1podfile = 'O:\Tech_Novana-Marsvin\FPOD\DATA\CPODvFPOD\processed_FPOD\MDF1A 2020 10 27 FPOD_6311 series1 file0.FP1';

%FPOD FP3 file 
FP3podfile = 'O:\Tech_Novana-Marsvin\FPOD\DATA\CPODvFPOD\processed_FPOD\MDF1A 2020 10 27 FPOD_6311 series2 file0.FP3';

podfilepath = {CP1podfile, CP3podfile, FP1podfile, FP3podfile};

%% Load pod data

i=2;
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

