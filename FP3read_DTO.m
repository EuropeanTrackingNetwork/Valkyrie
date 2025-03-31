function [minutes, trains]=FP3read(filename, n)
% [minutes, trains]=FP3read(filename, n)
% Reads F-POD FP3-datafile
% returns structures "minutes" with data arranged per minute and
% "trains" with data arranged in individual trains
% Filename without extension or .'FP3'.
% Requires both FP1 and FP3-files to be in the current directory in order
% to compute noise level nall
% Variable n = '-n' includes Nall from FP1-file (if present)

% Info from FP3-file is stored in two structures, minutes and trains.
% Minutes-structure contains redordings minute by minute, also empty
% minutes.
% minutes.time          : beginning of minute, in Matlab format
% minutes.temperature   : in oC
% minutes.angle         : degrees from vertical (hydrophone up
% minutes.no_of_trains  : trains in minute
% minutes.no_of_clicks  : clicks in minute
% minutes.trainHi       : Trains classified as High probability
% minutes.trainMed      : Trains classified as Medium probability
% minutes.trainLow      : Trains classified as Low probability
% minutes.trainAll      : Trains classified as Doubtful
% minutes.clickHi       : clicks classified as High probability
% minutes.clickMed      : clicks classified as Medium probability
% minutes.clickLow      : clicks classified as Low probability
% minutes.clickAll      : clicks classified as Doubtful
% minutes.train.ID              : ID number of train. not unique
% minutes.train.spclass         : 0=NBHF, 1= dolphin, 2=noSp, 3=sonar
% minutes.train.species         : text
% minutes.train.qualityclass    : 0=doubt, 1=low, 2=med, 3=hi
% minutes.train.quality         : text
% minutes.train.rategood        : Boolean, use unknown
% minutes.train.speciesgood     : Boolean, use unknown
% minutes.train.no_of_clicks    : clicks in train
% minutes.train.time            : time of individual clicks, usecs after start of minute
% minutes.train.ici             : Inter-click-interval, usec
% minutes.train.cycles          : cycles in click
% minutes.train.nix             : peak amplitude, uncalibrated unit (Nix-unit)
% minutes.train.frq             : mean instantaneous frequency (kHz)
% minutes.train.BW              : measure of variation in instantaneous frequency (kHz)
% minutes.train.fend            : Instantaneous frequency at end of click

% trains-structure contains the same information about individual trains as
% the minutes-strucure, just organised by individual trains, rather than by
% minute.

% There is more information in the FP3-file, not all is extracted.

% J. Tougaard, Aarhus University, May 2017
% Modified by Mel Cosentino, Aarhus University, Nov 2023, to read FP3 files
% Modified by Mia L. K. Nielsen, Aarhus University, March 2025 based on
% input from Nick Treganza

% FP3-file structure (from Nick):
% The FP3 file structure is different than the CP3 file structure. There is
% a longer header and data is stored in 16-bit segments. The information
% that is stored in each byte of the segment will depend on the number in
% the first byte (see below). 
% But similar to the CP3 data 254 denotes minute data.

% Click data:
% 0-183: Means the following 15 bytes will have click data information
% % Byte 1: Time (MSB): time stamp: steps of 0.5 micro-s from start of current minute, big-endian,
% % Byte 2: time
% % Byte 3: Time (LSB)
% % Byte 4: Peakat #ClkIPIrange: Wavenumber of loudest cycle; range of IPIs in click
% % Byte 5: IPIpreMax: IPI  of Pk-1
% % Byte 6: IPIatMax: IPI of  Pk  this is the loudest cycle in the click
% % Byte 7: IPIplus1: IPI of  Pk+1
% % Byte 8: IPIplus2: IPI of  Pk+2
% % Byte 9: RawPkminus1: Amplitude of  P-1
% % Byte 10: MaxPkRaw: Amplitude of  Pmax,  the loudest cycle in the click
% % Byte 11: RawPkplus1: Amplitude of  P+1
% % Byte 12: IPIbefore: IPI before click start
% % Byte 13: AmpReversals #duration: N of Amplitude Reversals in click envelope; Duration of click (MSB)
% % Byte 14: duration: Duration of click (LSB)
% % Byte 15: HasWave #EndIPI: IPI of last cycle, compressed; flag if boat sonar found

% Train details
% 249: Indicates that the following 15 bytes are train information
% % Byte 1: tNinIncGaps #clusterNall
% % Byte 2: tNinIncGaps
% % Byte 3: tMedKHZ
% % Byte 4: tAvSPL
% % Byte 5: tAvPkAt #tAvPRF
% % Byte 6: tAvPRF
% % Byte 7: PrecedingGap #tAvBWx8 #tWUTSrisk
% % Byte 8: 
% % Byte 9: tRateGoodScore
% % Byte 10: tavNcyc
% % Byte 11: cFmin
% % Byte 12: cFmax
% % Byte 13: EncSpN
% % Byte 14: Qn #SpClass #Marked #IsEcho #SpGood #RateGood
% % Byte 15: #TrnIDn

% Minute data
% 254: Indicates that the following 15 bytes are minute information
% % Byte 1: VirtLastClkTimeInMin
% % Byte 2: 
% % Byte 3: AngleDeg
% % Byte 4: 
% % Byte 5: 
% % Byte 6: LandmarkSeqScore
% % Byte 7: DegC
% % Byte 8: NrawClxInMin
% % Byte 9: NrawClxInMin
% % Byte 10: PriorMinOn #FollowingMinON #BatInUse #BatInUse
% % Byte 11: battery stuff
% % Byte 12: battery stuff
% % Byte 13: battery stuff
% % Byte 14: MinuteDeadband
% % Byte 15: 

% Other values may appear and then the following bytes will hold different
% information. These are not relevant for this project, but the vlaues and
% their meaning are outlined here:
% 247: Text error code
% 248: social call parameters
% 250: wev recording info
% 252: sonar ghosts record
% 253: Duff record
% 255: end of recording 

% First 7008 bytes: Header 
% Byte 257-260: Starttime in minutes from 1899-12-30 00:00, big-endian


% % % % % % % % % % % % % % % % % % % % % % % % % % % % % % % % % % % % % %
% 
% Troubleshooting: 
% [files, path] = uigetfile('*.*', 'MultiSelect','on') ; % select files to
% load and test the script on
% filename = files{4} ; % get filename of selected file
   
if strcmp('.FP3',filename(end-3:end)) || strcmp('.fp3',filename(end-3:end))
    filename=filename(1:end-4);     %remove extension
end
file=fopen([filename,'.FP3']);
% file = fopen([path, filename, '.FP3']) ; % include path as argument 
header=fread(file,360); % Question: is this 360 because we just want to extract date?
starttime=((header(257)*256+header(258))*256+header(259))*256+header(260);
starttimeFP3=datenum([1899 12 30 0 starttime 0]); % changed from datenum
%datebase = 1899-12-30 00:00
FP3_data=fread(file,[48,inf]); % there seem to be 48 variables in FPOD data, not 40
FP3_data(:,FP3_data(48,:)==255)=[]; % delete end of file markers
fclose(file);

if nargin>1 && strcmp('-n',n)
    try     %Read FP1-file, if present
        file=fopen([filename,'.FP1']);
        % file = fopen([path, filename, '.FP1']);
        noFP1=false;
    catch
        disp('FP1-file not found!');
        noFP1=true;
    end
else
    noFP1=true;
end
if ~noFP1
    fread(file,360);    %header
    FP1_data=fread(file,[10,inf]);
    FP1_data(:,FP1_data(10,:)==255)=[]; %delete end of file markers
    fclose(file);
end

%% Find minute-recordings
if ~noFP1
    minutebreaksFP1=FP1_data(10,:)==254;    %lines with minutedata
    dummy=(1:length(FP1_data))';            %linenumber in raw data
    minuteindexFP1=dummy(minutebreaksFP1);  %index to location of minutebreaks in data
end

minutebreaks=FP3_data(41,:)==254;       % lines with minutedata (used to be 40, for CP3)
dummy=(1:length(FP3_data))';            % linenumber in raw data
minuteindex=dummy(minutebreaks);        % index to location of minutebreaks in data

%% Read clicks minute by minute
qualitylist={'Doubtful','Low','Medium','High'};
specieslist={'NBHF','Dolphin','Unclass.','Sonar','HEL1'};
minutes=struct;
trains=struct;
trainno=1;
for currentminute=1:sum(minutebreaks)-1
    minutes(currentminute).time=starttimeFP3+currentminute/1440;
    minutes(currentminute).temperature=FP3_data(4,minuteindex(currentminute))/5; % get temperature in current minute
    minutes(currentminute).angle=acosd(1-FP3_data(5,minuteindex(currentminute))/128); % get angle in current minute
    if minuteindex(currentminute+1)>minuteindex(currentminute)+1   %minute not empty
        clicksinminute=FP3_data(:,minuteindex(currentminute)+1:minuteindex(currentminute+1)-1); %all clickinfo in current minute (between the minute breaks)
        trainID=clicksinminute(40,:);
        trainIDlist=unique(trainID);
        minutes(currentminute).no_of_trains=length(trainIDlist);
        minutes(currentminute).no_of_clicks=size(clicksinminute,2);    
        for n=1:length(trainIDlist)
            minutes(currentminute).train(n).ID=trainIDlist(n);
            trains(trainno).ID=trainIDlist(n);
            dummy=clicksinminute(37,trainID==trainIDlist(n));
            % Species class
            minutes(currentminute).train(n).spclass=bitshift(bitand(dummy(1),240),-4);
            trains(trainno).spclass=bitshift(bitand(dummy(1),240),-4);
            minutes(currentminute).train(n).species=specieslist(trains(trainno).spclass+1);
            trains(trainno).species=specieslist(trains(trainno).spclass+1);

            % quality class
            minutes(currentminute).train(n).qualityclass=bitand(dummy(1),3);
            trains(trainno).qualityclass=bitand(dummy(1),3);
            minutes(currentminute).train(n).quality=qualitylist(trains(trainno).qualityclass+1);
            trains(trainno).quality=qualitylist(trains(trainno).qualityclass+1);
            % Rate good? (boolean)
            minutes(currentminute).train(n).rategood=bitshift(bitand(dummy(1),4),-2);
            trains(trainno).rategood=bitshift(bitand(dummy(1),4),-2);
            % species good (boolean)
            minutes(currentminute).train(n).speciesgood=bitshift(bitand(dummy(1),8),-3);
            trains(trainno).speciesgood=bitshift(bitand(dummy(1),8),-8);
            % Number of clicks in train
            minutes(currentminute).train(n).no_of_clicks=sum(trainID==trainIDlist(n));
            trains(trainno).no_of_clicks=sum(trainID==trainIDlist(n));
            % Date and time of current minute
            trains(trainno).minute=starttimeFP3+currentminute/1440;
            % time
            minutes(currentminute).train(n).time=5*((clicksinminute(1,trainID==trainIDlist(n))*256 ...
                +clicksinminute(2,trainID==trainIDlist(n)))*256)+clicksinminute(3,trainID==trainIDlist(n));
            trains(trainno).time=5*((clicksinminute(1,trainID==trainIDlist(n))*256 ...
                +clicksinminute(2,trainID==trainIDlist(n)))*256)+clicksinminute(3,trainID==trainIDlist(n));
            minutes(currentminute).train(n).ici=diff([minutes(currentminute).train(n).time]);
            trains(trainno).ici=diff([minutes(currentminute).train(n).time]);
            % cycles
            minutes(currentminute).train(n).cycles=clicksinminute(4,trainID==trainIDlist(n));
            trains(trainno).cycles=clicksinminute(4,trainID==trainIDlist(n));
            % amplitude (nix)
            minutes(currentminute).train(n).nix=clicksinminute(8,trainID==trainIDlist(n));
            trains(trainno).nix=clicksinminute(8,trainID==trainIDlist(n));
            % frequency
            minutes(currentminute).train(n).frq=clicksinminute(6,trainID==trainIDlist(n));
            trains(trainno).frq=clicksinminute(6,trainID==trainIDlist(n));
            % bandwidth
            minutes(currentminute).train(n).BW=clicksinminute(5,trainID==trainIDlist(n));
            trains(trainno).BW=clicksinminute(5,trainID==trainIDlist(n));
            %f-end
            minutes(currentminute).train(n).fend=clicksinminute(7,trainID==trainIDlist(n));
            trains(trainno).fend=clicksinminute(7,trainID==trainIDlist(n));
            trainno=trainno+1;
        end
        
        minutes(currentminute).trainHi=sum([minutes(currentminute).train.spclass]==0'&...
            [minutes(currentminute).train.qualityclass]==3);
        minutes(currentminute).trainMed=sum([minutes(currentminute).train.spclass]==0'&...
            [minutes(currentminute).train.qualityclass]==2);
        minutes(currentminute).trainLow=sum([minutes(currentminute).train.spclass]==0'&...
            [minutes(currentminute).train.qualityclass]==1);
        minutes(currentminute).trainAll=sum([minutes(currentminute).train.spclass]==0'&...
            [minutes(currentminute).train.qualityclass]==0);
        
        minutes(currentminute).clickHi=sum([minutes(currentminute).train(...
            [minutes(currentminute).train.spclass]'==0&...
            [minutes(currentminute).train.qualityclass]'==3).no_of_clicks]);
        minutes(currentminute).clickMed=sum([minutes(currentminute).train(...
            [minutes(currentminute).train.spclass]'==0&...
            [minutes(currentminute).train.qualityclass]'==2).no_of_clicks]);
        minutes(currentminute).clickLow=sum([minutes(currentminute).train(...
            [minutes(currentminute).train.spclass]'==0&...
            [minutes(currentminute).train.qualityclass]'==1).no_of_clicks]);
        minutes(currentminute).clickAll=sum([minutes(currentminute).train(...
            [minutes(currentminute).train.spclass]'==0&...
            [minutes(currentminute).train.qualityclass]'==0).no_of_clicks]);
    else    % No clicks in minute, set all variables to zero
        minutes(currentminute).no_of_trains=0;
        minutes(currentminute).no_of_clicks=0;
        minutes(currentminute).trainHi=0;
        minutes(currentminute).trainMed=0;
        minutes(currentminute).trainLow=0;
        minutes(currentminute).trainAll=0;
        minutes(currentminute).clickHi=0;
        minutes(currentminute).clickMed=0;
        minutes(currentminute).clickLow=0;
        minutes(currentminute).clickAll=0;
    end
    if ~noFP1   %Get nall from FP1-file, if present
        if minuteindexFP1(currentminute+1)>minuteindexFP1(currentminute)+1   %FP1 minute not empty
            clicksinminute=FP1_data(:,minuteindexFP1(currentminute)+1:minuteindexFP1(currentminute+1)-1); %all clickinfo in current minute
            minutes(currentminute).nall=size(clicksinminute,2);
        else
            minutes(currentminute).nall=0;
        end
    end
end

