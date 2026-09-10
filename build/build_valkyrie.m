
function tbl = createDateTime(tbl, Config)
 % BUILD_VALKYRIE  Compile VALKYRIE.mlapp into a standalone Windows
% executable and installer. Run from anywhere; paths are resolved
% relative to this file's location, so this only works correctly
% if the file stays at <repo root>/build/build_valkyrie.m.
%
% Usage:
%   cd build
%   build_valkyrie
%
% Requires: MATLAB Compiler, MATLAB Compiler SDK (for installer packaging)
 
    root      = fileparts(fileparts(mfilename('fullpath')));  % repo root
    buildDir  = fileparts(mfilename('fullpath'));
    appSrc    = fullfile(root, 'app_source');
    appFile   = fullfile(appSrc, 'VALKYRIE.mlapp');
    configDir = fullfile(appSrc, 'config');    % nested inside app_source
    helpDir   = fullfile(appSrc, 'helpers');   % nested inside app_source
    gfxDir    = fullfile(appSrc, 'graphics');  % nested inside app_source
    verFile   = fullfile(appSrc, 'valkyrieVersion.m');  % single source of truth
    outDir    = 'O:\Nat-Tech_DTO-BioFlow\VALKYRIE';   % shared network drive — avoids OneDrive
                                       % file-locking and Windows path-length limits
                                       % during installer packaging, and keeps
                                       % build output accessible to the whole team
 
    requiredFolders = {appSrc, configDir, helpDir, gfxDir};
    for i = 1:numel(requiredFolders)
        if ~isfolder(requiredFolders{i})
            error('build_valkyrie:missingFolder', ...
                'Expected folder not found: %s', requiredFolders{i});
        end
    end
    if ~isfile(appFile)
        error('build_valkyrie:missingApp', 'App file not found: %s', appFile);
    end
 
    % The app calls valkyrieVersion() in startupFcn, so it MUST be inside
    % app_source and MUST be packaged with the exe.
    if ~isfile(verFile)
        error('build_valkyrie:missingVersionFile', ...
            ['Version file not found: %s\n' ...
             'valkyrieVersion.m must live in app_source/ (see ' ...
             'VALKYRIE_release_process.md) so it is packaged with the app.'], verFile);
    end
 
    % A leftover copy in build/ shadows app_source/ whenever the build is run
    % from this folder, which is how the two can silently drift apart.
    staleVerFile = fullfile(buildDir, 'valkyrieVersion.m');
    if isfile(staleVerFile)
        error('build_valkyrie:duplicateVersionFile', ...
            ['A second copy of valkyrieVersion.m exists at:\n%s\n' ...
             'Delete it — app_source/valkyrieVersion.m is the single source of truth.'], ...
            staleVerFile);
    end
 
    addpath(appSrc, configDir, helpDir, gfxDir);
 
    ver = readVersionFrom(verFile);
    fprintf('Building VALKYRIE v%s\n', ver);
    fprintf('  App:      %s\n', appFile);
    fprintf('  Version:  %s\n', verFile);
    fprintf('  Config:   %s\n', configDir);
    fprintf('  Helpers:  %s\n', helpDir);
    fprintf('  Graphics: %s\n', gfxDir);
 
    exeArgs = { ...
        'ExecutableName',  'VALKYRIE', ...
        'ExecutableVersion', ver, ...
        'AdditionalFiles', {configDir, helpDir, gfxDir, verFile}, ...
        'OutputDir',        fullfile(outDir, 'exe'), ...
        'Verbose',          'on'};
 
    % Optional branding assets — only added if present, so the build
    % doesn't fail before these assets exist.
    iconFile   = fullfile(gfxDir, 'icon64.png');
    splashFile = fullfile(gfxDir, 'valkyrieV1.png');
    if isfile(iconFile)
        exeArgs = [exeArgs, {'ExecutableIcon', iconFile}];
    end
    if isfile(splashFile)
        exeArgs = [exeArgs, {'ExecutableSplashScreen', splashFile}];
    end
 
    % --- compile executable ---
    res = compiler.build.standaloneWindowsApplication(appFile, exeArgs{:});
 
    % --- verify the runtime dependencies actually got packaged ---
    % Cheap insurance against the v1.0.0 failure mode, where a file the app
    % needs at startup was simply not in the bundle.
    assertPackaged(res, {'valkyrieVersion.m', 'metadata_validation.json'});
 
    % --- package installer ---
    exePath = fullfile(outDir, 'exe', 'VALKYRIE.exe');
 
    installerArgs = { ...
        'InstallerName',   "VALKYRIE_" + ver + "_Setup", ...
        'ApplicationName', 'VALKYRIE', ...
        'AuthorCompany',   'Aarhus University & VLIZ/European Tracking Network', ...
        'Version',          ver, ...
        'Summary',         'Click detection extraction and harmonization tool', ...
        'RuntimeDelivery', 'installer', ...   % switch to 'web' for a smaller, online-only installer
        'OutputDir',        fullfile(outDir, 'installer')};
 
    % InstallerIcon is what actually gets used as the icon for the
    % desktop/Start Menu shortcut (see icon_48 -> applicationIcon in
    % compiler.package.installer's source). ExecutableIcon above only
    % affects the .exe's own embedded icon, not the shortcut.
    % Shortcut must point at a file that's actually being packaged
    % (here, the compiled exe) — it is NOT an icon path itself.
    if isfile(iconFile)
        installerArgs = [installerArgs, ...
            {'InstallerIcon', iconFile, ...
             'AddRemoveProgramsIcon', iconFile, ...
             'Shortcut', exePath}];
    end
 
    compiler.package.installer(res, installerArgs{:});
 
    fprintf('Done.\n');
    fprintf('  Executable: %s\n', fullfile(outDir, 'exe'));
    fprintf('  Installer:  %s\n', fullfile(outDir, 'installer'));
end
 
 
function v = readVersionFrom(verFile)
% Call valkyrieVersion from its own folder, so the current folder cannot
% shadow it with a different copy.
    [folder, fname] = fileparts(verFile);
    oldFolder = cd(folder);
    restore   = onCleanup(@() cd(oldFolder)); %#ok<NASGU>
    v = string(feval(fname));
    if strlength(v) == 0
        error('build_valkyrie:emptyVersion', 'valkyrieVersion() returned an empty value.');
    end
end
 
 
function assertPackaged(res, mustContain)
% Confirm the compiler results list the files the app needs at runtime.
    packaged = strings(0,1);
    for f = ["Files","IncludedSupportPackages","AdditionalFiles"]
        if isprop(res, f) || isfield(res, f)
            try
                packaged = [packaged; string(res.(f))(:)]; %#ok<AGROW>
            catch
                % property present but not a string list — ignore
            end
        end
    end
 
    if isempty(packaged)
        warning('build_valkyrie:noFileList', ...
            ['Could not read the packaged file list from the build results, so ' ...
             'the dependency check was skipped. Verify manually that %s are in the bundle.'], ...
            strjoin(string(mustContain), ', '));
        return
    end
 
    for i = 1:numel(mustContain)
        needle = string(mustContain{i});
        if ~any(contains(packaged, needle, 'IgnoreCase', true))
            error('build_valkyrie:missingDependency', ...
                ['%s does not appear in the packaged files. The compiled app will ' ...
                 'fail at startup. Check AdditionalFiles and the dependency report.'], needle);
        end
    end
    fprintf('Dependency check passed: %s\n', strjoin(string(mustContain), ', '));
end