# Valkyrie - Data Harmonization Tool for C-POD and F-POD data

Valkyrie is a tool developed within the DTO BioFlow project (https://dto-bioflow.eu/) to harmonize metadata and porpoise detection data from C‑PODs and F‑PODs. It takes raw detection files (CP1/CP3 or FP1/FP3 pairs) together with standardized deployment metadata and produces ETN‑ready output files that can be uploaded directly to the ETN Underwater Acoustics database.
Valkyrie validates metadata, matches POD detection files to deployments, extracts detections from raw files, and formats all outputs according to ETN requirements.

## Overview
Valkyrie provides an automated workflow for preparing POD datasets for ingestion into ETN. After registering as an ETN user and obtaining a project number, users can upload one metadata CSV file and the raw POD detection files for their deployments. Valkyrie checks that the metadata file follows the required format, verifies that all POD detection files are complete and correctly paired, and links each file to the appropriate deployment.

Once processing begins, Valkyrie extracts detections from each CP1/CP3 or FP1/FP3 file pair and converts both the detections and the metadata into harmonized ETN‑compatible formats. The application outputs three files: deployment metadata, receiver metadata, and a combined detections dataset containing all processed deployments.

## Metadata Requirements
Before using Valkyrie, prepare a single metadata CSV file containing one row per deployment. The metadata must follow the Valkyrie metadata template, which includes separating timestamps into year, month, day, and time columns. A template is available in this repository to help you prepare the file (\SampleDeployment\VALKYRIE Sample Metadata - Blank.xlsm). Once completed, export the file to CSV format before uploading it to Valkyrie.

## Uploading files
Valkyrie accepts metadata and POD detection files for one ETN project at a time, but you may upload multiple deployments in a single session. Upload your raw POD detection files first. You can either select individual files or a folder; Valkyrie will automatically search through subfolders and detect valid file pairs.

Once POD files are uploaded and validated, you can upload the metadata file. Valkyrie will validate all fields and report any issues.

Each deployment must include both files in the pair: CP1 and CP3 for C‑PODs, or FP1 and FP3 for F‑PODs. Valkyrie will match these files to the corresponding deployment based on the metadata.

## Processing and output
When all files are uploaded, Valkyrie processes the data automatically. It extracts detections and converts everything into ETN‑standard formats.
After processing is complete, Valkyrie produces three output files:

1. A deployment metadata file containing harmonized information for the processed deployments
2. A receiver metadata file with information about the POD units used
3. A combined detections file containing all extracted detections from all uploaded deployments

All output files are ready for direct ingestion into the ETN Underwater Acoustics database with no further formatting required.

## Support
For issues, feature requests, or bug reports, please open an issue in this repository.
If you need additional help preparing metadata or understanding the ETN submission requirements, please consult the ETN documentation or contact the project maintainers.

## Progress
The tool is under development in a collaboration between Aarhus University and VLIZ. 


