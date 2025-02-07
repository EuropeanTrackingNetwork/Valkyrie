function [fpodat] = importpoddata(podfile, varargin)
%IMPORTFPODDATA Imports FPOD or CPOD files
%   [FPOD] = IMPORTFPODDATA(FILEPATH) immports CPOD or FPOD data. FILEPATH
%   is the path to a CP1/FP1 or CP3/FP3 file. The output data is a table.
%
%   [FPOD] = IMPORTFPODDATA(FILEPATH, 'detstart', N) imports only data from
%   the Nth detection on the file. 'maxdat' N sets the maximum number of
%   detections to import
%
%   The output is a structure array containing CPOD/FPOD data. The
%   following fields;
%   ampdB (double array): Amplitude of the click in dB. 
%   date : Date of the click detection in MATLAB datetime
%   freqlims (double array, 1x2): Lower and upper frequency limits of the click band (Hz)
%   freqcenter (double): Center frequency of the click band (kHz, converted to Hz)
%   freqend (double): End frequency of the click band (kHz, converted to Hz)
%   slope (double): Slope of the click spectrum (dB/kHz)
%   duration (double): Duration of the click (seconds)
%   nCyc (double): Number of cycles in the click
%   clicktrain (struct, optional): Click train classification information
%       species (string): Detected species of the click producer (empty if not classified)
%       isecho (logical): Indicates whether the click is an echo (true) or not (false)
%       quality (double): Quality level of the classification
%       clicktrainid (string): Unique identifier for the click train - use
%       this to group clicks from the same train. 
%   wav (double array, optional): Raw waveform data of the click (empty if not available and only from FPODs)

% podfile = "/Users/jdjm/Library/CloudStorage/Dropbox/PAMGuard_dev/CPOD/FPOD_NunBank/0866 NunBankB 2023 06 27 FPOD_6480 file0.FP3";

detstart = 0; %the detection to start loading within the the file.
maxdet = intmax; %the maximum number of data units that can be loaded.


iArg = 0;
while iArg < numel(varargin)
    iArg = iArg + 1;
    switch(varargin{iArg})
        case 'detstart'
            iArg = iArg + 1;
            detstart = varargin{iArg};
        case 'maxdet'
            iArg = iArg + 1;
            maxdet = varargin{iArg};
    end
end


% need to add the jar to the java path
p = mfilename('fullpath');
[filepath,~,~] = fileparts(p);

javajarpath=[filepath '/cpodutils-0.0.1-SNAPSHOT.jar'];

disp(javajarpath);

javaaddpath(javajarpath);

fpodMat = org.pamguard.cpodutils.FPODmat;


cpodDatas = fpodMat.importPODFile(podfile, detstart, maxdet);

% Convert the Java ArrayList to a MATLAB cell array

%pre allocate structure
disp('Converting to MATLAB struct')
num = cpodDatas.size();
fpodat(num) = pod2strcut(cpodDatas.get(num-1)); % pre allocate the structure.

for i = 1:cpodDatas.size()
    podData = cpodDatas.get(i-1); % Java indexing starts from 0

    if (mod(i, 5000)==0)
        disp(['Converting to MATLAB struct ' num2str(100*i/cpodDatas.size()) '% - imported ' num2str(i) ' clicks'])
    end

    fpodat(i)= pod2strcut(podData);
end

javarmpath(javajarpath)

    function fpodstruct  = pod2strcut(cpodData)

        fpodstruct.ampdB = cpodData.getAmplitudeDB();
        fpodstruct.date = millis2datenum(cpodData.getTimeMilliseconds()); 

        freq = cpodData.getFrequency();
        fpodstruct.freqlims = freq;
        fpodstruct.freqcenter = cpodData.getkHz*1000.;
        fpodstruct.freqend = cpodData.getEndF*1000.;
        fpodstruct.slope = cpodData.getSlope;

        fpodstruct.duration = cpodData.getDuration;
        fpodstruct.nCyc = cpodData.getnCyc;

        if (isempty(cpodData.getClassification))
            fpodstruct.clicktrain = [];
        else
            fpodstruct.clicktrain.species = char(cpodData.getClassification.species.toString);
            fpodstruct.clicktrain.isecho = cpodData.getClassification.isEcho;
            fpodstruct.clicktrain.quality = cpodData.getClassification.qualitylevel;
            fpodstruct.clicktrain.clicktrainid = cpodData.getClassification.clicktrainID;
        end

        if (isempty(cpodData.getWaveData))
            fpodstruct.wav=[];
        else
            fpodstruct.wav = cpodData.getWaveData;
        end

    end

    function matlab_datenum = millis2datenum(java_millis)
    % Convert Java milliseconds (since the Unix epoch) to MATLAB datenum.
    %
    % Args:
    %   java_millis: Java milliseconds timestamp.
    %
    % Returns:
    %   matlab_datenum: Equivalent MATLAB datenum.

    % Directly convert Java milliseconds to a datetime object
    matlab_datenum = datetime(java_millis/1000, 'ConvertFrom', 'posixtime');

    % % Convert the datetime object to a MATLAB datenum
    % matlab_datenum = datenum(datetime_obj);
end


end

