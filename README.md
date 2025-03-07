# Data aggregation tool

## Project description
This project is part of the EU DTO-BioFlow (https://dto-bioflow.eu/). The focus is on aggregating passive acoustic monitoring (PAM) data and harmonising and standardising it. The tool will allow users that store CPOD or FPOD files (from here referred to as POD files) to upload them into a shared database, including relevant metadata, ensuring that porpoise detection data is harmonised across deployments and projects. 

## Features
- File selection that allows the user to select multiple files and run a batch upload
- Resolution selection: there is a built-in flexibility for the resolution of the output data. However, this feature may set to a default resolution that harmonises with existing data
- Fill in mandatory metadata: this is done for a single file at a time and the metadata is saved for each file and added to the specific file output before upload
- Validation of metadata input: the data that is supplied by the user goes through a quality check (e.g. that datetime and position data is correctly input)
- Choice of optional metadata input: not yet incorporated
- File import: the POD files are imported sequentially and the import function depends on the file type (CPOD or FPOD)
- Extracting output: the imported POD files will run through specific functions to extract and format the data for ingestion into the target database
- Formatting: the files will be formatted to match database 
- Upload: the data will upload output files to database 

## Progress
The tool is under development. 
