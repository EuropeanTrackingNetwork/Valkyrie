% This script is developed to create HDF5 files of the monitoring data to 
% upload to the joint JOMOPANS server created by BSH. 
%
% This version is set up to work with the allnoise mat file produced in
% Step 2.
%
% Current Version by Emily T. Griffiths, 2020.
%
% Originally Developed by Jakob Tougaard and Pernille Meyer Sørensen, 2018. 
% Modified and improved by Line Hermannsen and Mia L. K. Nielsen, 2018-2020.


clear all
close all


%%  Call in functions
addpath(genpath('O:\Tech_MSFD-deskriptor11-Danmark\Monitering\Analysis\scripts'));

% Call in metadata for the deployment you would like to process
run('O:\Tech_MSFD-deskriptor11-Danmark\Monitering\Data\__Metadata\_metadataInput\Station 104 Anholt\DKMst104_20201008_Metadata.m');

% Call in Allnoise data from Step 2.
cd(outputLocation)



mfiles=dir(strcat('TOLdB_Allnoise_*.mat')); %find matfiles created from 'data_logarithmic_units_2019_LH.m' - where deployment and retrieval day are excluded (minday and maxday variables)

load(mfiles.name);

%load('TOLdB_Allnoise_CL209_DKMst104_20200529_to_20200712_SE-SM2M002.mat');
%filesdata=dir(strcat('O:\Tech_MSFD-deskriptor11-Danmark\Monitering\Data\Station 104 Anholt\DKMst104_20210601 Recordings\5379'));
% Extract the seconds per sample information for this deployment.  This
% will be a consistent number based on the sample rate
% This was added to the data file save in Step 1 on 3/9/2020. Check to make
% sure this step is necessary.
dur=cell(size(filesdata));
for f = 1:length(filesdata)
    wav=audioinfo([filesdata(f).folder '\' filesdata(f).name]);
    inSec=extractBefore(char(seconds(wav.Duration)),' ');
    [dur{f}]=inSec;
end

duration=str2double(dur);

% Select the folder to save the file
cd('O:\Tech_MSFD-deskriptor11-Danmark\JOMOPANS\Data\Datasharing_BSH\Data_for_BSH_server\2020 Anholt');

%% What Months/Years are you interested in?
iyy='2020'; %year of interest
imo=[month(DTstart):1:month(DTslut)];%sets months of interest, or manually set e.g. [2:1:9] = feb to sep
imo=[10:1:12];
disp(['Months of interest: ' num2str(imo) ' (total: ' num2str(length(imo)) ')']);

%% Double check the following
duty_cycle=median(duration)/60; %recording schedule, e.g. 30 or 60 min per hour
%hydsens=-201;
hydsens='';
[nyy nmo ndd]=datevec(datestr(now)); curdate=[num2str(nyy) '-' num2str(nmo) '-' num2str(ndd)]; %get current date
datver='2'; %data version
depthmet=['Measured by ' author]; %Default, depth measured by author
sa_tool='JOMOPANS_processing_function.m, version 2.3';
ref=[250.0,134]; %Pistonphone calibration at 250 Hz, 134 dB re 1V/µPa
plotfig=0;

if strncmp(type,'SM2M',4)
    devman='WILDLIFE';
    hydman='WILDLIFE';
elseif strncmp(type,'ST500',4)
    devman='Ocean Instruments';
    hydman='Ocean Instruments';
elseif strncmp(type,'DSG-ST',4)
    devman='Loggerhead Instruments';
    hydman='Loggerhead Instruments';
end
datacomment=['Data from ' depSite ' ' iyy];

calibration = struct( ...
    'calibration_procedure', 'pistonphone', ...
    'other_calibration_method',' ', ...
    'reference_frequencies_levels',ref, ...
    'calibration_file',' ');

%% % Example of frequency index:
% frequency_index = [ ...
%     10, 12.589, 15.849, 19.953, 25.119, 31.623, 39.811, 50.119, ...
%     63.096, 79.433, 100, 125.89, 158.49, 199.53, 251.19, 316.23, ...
%     398.11, 501.19, 630.96, 794.33, 1000, 1258.9, 1584.9, 1995.3, ...
%     2511.9, 3162.3, 3981.1, 5011.9, 6309.6, 7943.3, 10000, 12589, 15849, ...
%     19953];

% There has to be the 34 TOL bands shown above - either add or remove to
% fit
frequency_index = allnoise.fm(11:end) ;
frequency_count = length(frequency_index);

disp(['TOLs are estimated in ' num2str(length(frequency_index)) ' third-octave bands from '...
    num2str(frequency_index(1)) ' Hz to ' num2str(max(frequency_index)) ' Hz'])
%% Automatically runs the following for each month defined in variable 'imo'
% and saves an HDF5 file with data for each month



for j = 1:length(imo)
    
    spectro_temporal_values=[];
    temporal_values= [];
    datetime_index= [];
    for x = 1:length(allnoise.bb) %for each month
        %% To convert from datenum to time used by Jomopans:
        datetime_con = allnoise.timestamps{1,x};
        if isnat(datetime_con)
            continue
        end
        %t = datetime(datetime_con,'Format','yyyyMMddhhmmss');
        if isdatetime(datetime_con)
            t=datetime_con;
        else
            t = datetime(datetime_con,'ConvertFrom','datenum');
        end
        
        if length(t) > length(allnoise.TOLdB{1,x})
            t=t(1:end-1);
        end

    %% Convert datetime
        [yy mo dd hh mm ss]=datevec(datestr(t));

        S=(mo==imo(j));  
        if sum(S) == 0
            continue
        end
        st = min(find(mo==imo(j))); %find first occurence of month of interest (imo)
        sl = max(find(mo==imo(j))); %find last occurence of month of interest
        spectral_val=allnoise.TOLdB{1,x}(st:sl,:);
        spectro_temporal_values=vertcat(spectro_temporal_values,spectral_val);
        
        temporal_values=vertcat(temporal_values, allnoise.bb{1,x}(st:sl,:));
        datetime_index=vertcat(datetime_index, t(st:sl));
    end
    value_count = length(datetime_index); %count
    spectro_temporal_values = [spectro_temporal_values NaN(length(spectro_temporal_values),2)];
    
    smo=datetime(datetime_index(1),'Format','yyyyMMdd');%find first day in month        
    maxmo=datetime(datetime_index(end),'Format','yyyyMMdd'); %find last day in month
    
    datetime_index=cellstr(datestr(datetime_index,'yyyymmddHHMMSS'));

    clear temporal_stats spectral_stats dset

    temporal_stats = struct( ...
        'LMin', min(temporal_values), ...
        'L01', quantile(temporal_values, 0.99), ...
        'L05', quantile(temporal_values, 0.95), ...
        'L10', quantile(temporal_values, 0.90), ...
        'L25', quantile(temporal_values, 0.75), ...
        'L50', quantile(temporal_values, 0.50), ...
        'L75', quantile(temporal_values, 0.25), ...
        'L90', quantile(temporal_values, 0.10), ...
        'L95', quantile(temporal_values, 0.05), ...
        'L99', quantile(temporal_values, 0.01), ...
        'LMax', max(temporal_values));

    spectral_stats = struct( ...
        'LMin', min(spectro_temporal_values), ...
        'L01', prctile(spectro_temporal_values, 0.99), ...%changed from quantile to prctile after mail from Fritjof Basan 29th nov 2019
        'L05', prctile(spectro_temporal_values, 0.95), ...
        'L10', prctile(spectro_temporal_values, 0.90), ...
        'L25', prctile(spectro_temporal_values, 0.75), ...
        'L50', prctile(spectro_temporal_values, 0.50), ...
        'L75', prctile(spectro_temporal_values, 0.25), ...
        'L90', prctile(spectro_temporal_values, 0.10), ...
        'L95', prctile(spectro_temporal_values, 0.05), ...
        'L99', prctile(spectro_temporal_values, 0.01), ...
        'LMax', max(spectro_temporal_values));

    %% Plot the values
    if plotfig==1
        figure(j)
        title(['Spectral stats for month ' num2str(imo(j))])
        semilogx(frequency_index,spectral_stats.L10)
        semilogx(frequency_index,spectral_stats.L25)
        semilogx(frequency_index,spectral_stats.L50)
        semilogx(frequency_index,spectral_stats.L75)
        subplot(1,2,1)
        semilogx(frequency_index,spectral_stats.LMax)
        hold on
        semilogx(frequency_index,spectral_stats.L01)
        semilogx(frequency_index,spectral_stats.L05)
        semilogx(frequency_index,spectral_stats.L90)
        semilogx(frequency_index,spectral_stats.L95)
        semilogx(frequency_index,spectral_stats.L99)
        semilogx(frequency_index,spectral_stats.LMin)
        legend('LMax','L01','L05','L10','L25','L50','L75','L90','L95','L99','LMin')

        subplot(1,2,2)
        plot(datetime(datetime_ind,'ConvertFrom','yyyyMMddhhmmss'),spectro_temporal_values)
    end
    %%k

    dset = struct('author',author, ...
        'date_of_creation',curdate, ...
        'measuring_institution','AU', ...
        'point_of_contact','AU, Section for Marine Mammal Research', ...
        'dataset_ambient_noise', struct( ...
        'averaging_time', round(1), ...
        'calibration', calibration, ...
        'comments', datacomment, ...
        'construction_design','bottom frame', ...
        'cordinates_measurement_position', [depDecimalLat, depDecimalLon], ...
        'count', uint64(value_count), ...
        'dataset_type', 'ambient noise', ...
        'dataset_version', datver, ...
        'datetime_index', {datetime_index}, ...
        'device_manufacturer', devman, ...
        'device_serial_number', logger, ...
        'device_type', type, ...
        'duty_cycle', uint8(duty_cycle), ...
        'frequency_count', uint8(34), ...
        'frequency_index', frequency_index, ...
        'hydrophone_decoupling','yes', ...
        'hydrophone_manufacturer', hydman, ...
        'hydrophone_sensitivity',hydsens, ...
        'hydrophone_serial_number', hydrophoneID, ...
        'hydrophone_type', 'Standard', ...
        'measurement_height', 3.0, ...
        'measurement_purpose', 'Research and Development', ...
        'measurement_setup', 'autonomous', ...
        'name_measurement_position', depSite, ...
        'name_noise_measurement_project', 'JOMOPANS', ...
        'rawdata_timestamp',' ', ...
        'rawdata_uuid', char(java.util.UUID.randomUUID), ...
        'spectral_analysis_tool', sa_tool, ...
        'spectral_temporal_stats', spectral_stats, ...
        'spectral_temporal_values', spectro_temporal_values, ...
        'water_depth', Depth_m, ...
        'water_depth_method', depthmet)); % Anholt 12m, Horns Reef
    %% creates and writes data to hdf5 file (file must not exits at time of function call)
    ofilename=['01_' depID '_clip' num2str(round(ClipLevel)) '_' datestr(smo,'yyyymmdd') '_' datestr(maxmo,'yyyymmdd') '.h5'];
    matlab_write_recursive_hdf5(ofilename, '', dset);
end

