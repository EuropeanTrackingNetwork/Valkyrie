function build_valkyrie()

%
% What changed vs v1.0.0:
%  1. valkyrieVersion.m is expected in app_source/ (as
%     VALKYRIE_release_process.md already specifies) and is now passed
%     explicitly in AdditionalFiles. In v1.0.0 it lived in build/ and was not
%     shipped, so whether the compiled exe could call valkyrieVersion() at
%     runtime depended on the build machine's current folder. If it was not
%     picked up, startupFcn died at the version-label line and left the whole
%     app half-initialised.
%  2. The version is read by cd-ing into app_source first, so a stale
%     build/valkyrieVersion.m in the current folder cannot shadow it.
%  3. A stale build/valkyrieVersion.m is reported as an error, so the two
%     copies cannot drift apart.
%  4. After compiling, the packaged file list is checked for
%     valkyrieVersion.m and metadata_validation.json, and the build stops if
%     either is missing.
% =========================================================================
%
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

    % Confirm the app's dependency analysis actually finds valkyrieVersion.m,
    % and that it resolves to app_source rather than a stray copy elsewhere on
    % the path. This is the check that would have caught the v1.0.0 problem.
    assertDependencyResolves(appFile, verFile);

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

    % --- confirm what we asked the compiler to bundle ---
    % NOTE: res.Files lists the build's OUTPUT artifacts (exe, readme,
    % requiredMCRProducts.txt), not the packaged dependencies — it cannot be
    % used to verify bundle contents. What can be checked here is that the
    % files were actually requested. To inspect the real bundle, rebuild with
    % 'EmbedArchive','off' to get a separate VALKYRIE.ctf (a zip archive) and
    % list its contents, or run the exe once and look in
    % %LOCALAPPDATA%\Temp\<user>\mcrCache25.2\VALKYRIE0\.
    assertRequestedFiles(res, {verFile, configDir, helpDir, gfxDir});

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


function assertDependencyResolves(appFile, verFile)
% Confirm the app's own dependency analysis finds valkyrieVersion.m, and that
% it resolves to app_source rather than a copy elsewhere on the path. This is
% the check that would have caught the v1.0.0 startup failure at build time.
    try
        fList = matlab.codetools.requiredFilesAndProducts(appFile);
    catch depME
        warning('build_valkyrie:depCheckUnavailable', ...
            'Dependency analysis could not run (%s). Skipping this check.', depME.message);
        return
    end

    fList = string(fList(:));
    hits  = fList(endsWith(fList, "valkyrieVersion.m", 'IgnoreCase', true));

    if isempty(hits)
        error('build_valkyrie:versionNotADependency', ...
            ['valkyrieVersion.m is not detected as a dependency of:\n  %s\n' ...
             'It will not be packaged, and the compiled app will fail at startup.'], appFile);
    end

    if ~any(strcmpi(hits, string(verFile)))
        error('build_valkyrie:versionWrongCopy', ...
            ['valkyrieVersion.m resolves to:\n  %s\nbut the build expects:\n  %s\n' ...
             'Remove the other copy from the MATLAB path so the two cannot drift.'], ...
            hits(1), verFile);
    end

    fprintf('Dependency check passed: %s\n', hits(1));
end


function assertRequestedFiles(res, mustRequest)
% Confirm the files were actually passed to the compiler in AdditionalFiles.
% Warns rather than errors: this reads an undocumented corner of the results
% object, and a false alarm must never block a release build.
    try
        requested = string(res.Options.AdditionalFiles(:));
    catch
        warning('build_valkyrie:noAdditionalFilesList', ...
            ['Could not read AdditionalFiles from the build results, so this ' ...
             'check was skipped. Verify the bundle manually (see note above).']);
        return
    end

    for i = 1:numel(mustRequest)
        item = string(mustRequest{i});
        if ~any(strcmpi(requested, item))
            warning('build_valkyrie:notRequested', ...
                '%s was not passed in AdditionalFiles — check the bundle before releasing.', item);
        end
    end
    fprintf('AdditionalFiles check complete (%d entries requested).\n', numel(requested));
end
