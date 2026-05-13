

# VALKYRIE
Valkyrie is a tool developed within the DTO BioFlow project (https://dto-bioflow.eu/) to harmonize metadata and porpoise detection data from C‑PODs and F‑PODs. It takes raw detection files (CP1/CP3 or FP1/FP3 pairs) together with standardized deployment metadata and produces ETN‑ready output files that can be uploaded directly to the ETN Underwater Acoustics database.
Valkyrie validates metadata, matches POD detection files to deployments, extracts detections from raw files, and formats all outputs according to ETN requirements.

## Installation
VALKYRIE can be installed on windows platforms. 
Installation and use of VALKYRIE does not require MATLAB license.

1. Download the installer here [link to installer once we release].
2. Run the installer by double-clicking. It can take a moment to open the installer, as it will automatically install MATLAB Runtime on the first download. When the installation window appears, follow the prompts.

## Usage
After installation, VALKYRIE is ready to use. However, to be able to upload output files into the ETN database, you need to first register on the ETN database website [insert link].

The steps for using VALKYRIE are:
1. Register as a user on ETN.
2. Prepare input files (metadata and raw C-POD or F-POD files).
3. Upload raw POD files.
4. Upload metadata file.
5. Evaluate files matched between both POD files and metadata
6. Process matched files.
7. Evaluate output files.
8. Upload output files to ETN.

Note that only files for a single ETN project can be processed in VALKYRIE at a time. 
Each step is explained in detail below.

### 1. Register as a user and create a project on ETN
This step is not required to run VALKYRIE. However, to upload files into the ETN database, a user must first register in the ETN system.
To do that, visit https://www.lifewatch.be/etn/login. Once registered you will need to create a project using this template: https://www.lifewatch.be/etn/assets/docs/ETN-project-template.xlsx.
A guide to registration and creating a project can be found here: https://www.lifewatch.be/etn/assets/docs/ETN-QuickGuide.pdf.

### 2. Prepare input files
Input files for VALKYRIE include CP1 and CP3 files, FP1 and FP3 files, and corresponding metadata for each deployment where data is uploaded.

#### POD files:
Accepted formats: 
- .CP1 and .CP3
- .FP1 and .FP3

VALKYRIE accepts the files generated when data is offloaded from either C-PODs or F-PODs using either CPOD.exe or FPOD.exe.
To correctly extract the data, files must be provided in pairs, meaning that for C-POD data it is CP1 and CP3 and for F-POD data it is FP1 and FP3. 

#### Metadata file
Accepted format:
- .CSV

Metadata includes information on the deployments. Download a template for metadata here https://github.com/EuropeanTrackingNetwork/Valkyrie/blob/main/app_source/SampleDeployments/VALKYRIE%20Sample%20Metadata%20-%20Blank.xlsm.
The template has built in macros, allowing the user to fill in the date and time for a deployment, which will then automatically be filled in for the Year, Month, Date, Time columns. Be sure to check that the datetime columns have the correct date shown in the format DD/MM/YYYY HH:mm:ss.
OBS: once the metadata has been filled out make sure to save the metadata as a copy in the csv format. The macros will only work for future deployments if the original file is saved as an .xlsm file.

### 3. Upload raw POD files
Once you have located the POD files you want to extract, click the upload button. It is possible to select either single files (OBS: make sure to select file pairs, CP1/CP3 or FP1/FP3) or a folder. If a folder is selected all files of the correct format in the folder and its subfolders are selected.

At this step VALKYRIE checks that files appear in pairs and that there are no duplicate files.

The selected files will be displayed in the window pane for viewing.

### 4. Upload metadata files
Once POD files are uploaded and validated, you can upload the metadata file. Valkyrie will validate all fields and report any issues.

VALKYRIE can only process files for a single ETN project at a time. If more than one project appears in the metadata, the user will be prompted to select which one they want to process. 

### 5. Evaluate file match
When metadata has been validated, the user can click Confirm to inspect the matches between metadata deployments and POD files. 

In this window, it will appear green if a deployment has a corresponding file, or in red if not. 

The user can choose to go back to reupload or continue with the files that did match.

### 6. Process matched files
Once the user has clicked Process files, VALKYRIE will extract porpoise detections from each POD file pair and format them to match the ETN database.
This step can take a long time depending on the size and number of files.

### 7. Evaluate output files
Once the processing is done, VALKYRIE will present an overview table of the files that were processed and those that failed with a reason indicated. 
The user can now download the output files for all the POD files that were successfully extracted. 

After processing is complete, Valkyrie produces three output files:

1. A deployment metadata file containing harmonized information for the processed deployments
2. A receiver metadata file with information about the POD units used
3. A combined detections file containing all extracted detections from all uploaded deployments

### 8. Upload output files to ETN
All output files are ready for direct ingestion into the ETN Underwater Acoustics database with no further formatting required.

## Troubleshooting
When uploading data to ETN, ETN will run some checks to ensure the quality of the data that is uploaded. One check is that the metadata has not already been uploaded. This error can occur if you upload a metadata sheet with several deployments and then upload a folder containing a lot of deployments. VALKYRIE will match all metadata and detection files that have been uploaded, and will not take into account that some could have been processed before. If this error occurs at ETN, either remove the deployments manually or rerun files in VALKYRIE, only including the detection files you want to process instead of folders with subfolders.

## Meta
- License: MIT
- Please note that by using VALKYRIE and registering for ETN, you agree to the following Data Policy https://www.lifewatch.be/etn/assets/docs/ETN-DataPolicy.pdf.
