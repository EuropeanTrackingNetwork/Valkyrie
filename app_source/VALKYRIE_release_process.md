# Valkyrie — Build & Release Process

Repeatable procedure for compiling the MATLAB App Designer app into a Windows installer and publishing it as a GitHub release.

Repository: `EuropeanTrackingNetwork/Valkyrie` — app source in `/app_source`

---

## 0. One-time setup (do once per build machine, then leave alone)

Compiled output depends on the exact toolchain, so the build machine must be pinned and documented.

| Item | Value | Notes |
|---|---|---|
| MATLAB release | e.g. R2024b | Changing this changes the required MATLAB Runtime on every user's PC |
| Toolboxes used | list them | Must be licensed on the build machine |
| MATLAB Compiler | required | `matlabruntime`/`mcc` must be available |
| Build machine | name/ID | One designated machine, or a documented VM image |
| Test machine | clean Windows VM, no MATLAB | Keep a pre-install snapshot to roll back to |

Record these in `BUILD_ENVIRONMENT.md` in the repo. Update it whenever the MATLAB release changes.

**Single source of truth for the version number:** `app_source/valkyrieVersion.m`

```matlab
function v = valkyrieVersion()
    v = "1.4.0";   % <-- the only place the version is edited
end
```

Used in the app's About/title bar and read by the build script (Step 4). This prevents the app, the installer, and the Git tag from drifting apart. This file is committed to GitHub alongside `VALKYRIE.mlapp`.

**Repo layout referenced by the build:**

```
app_source/
  VALKYRIE.mlapp
  valkyrieVersion.m
config/       ← settings/config files the app loads at runtime
helpers/      ← helper .m functions called by the app
graphics/     ← icons, images, logos used in the UI, also holds icon64.png / valkyrieV1.png used by the build
build/
  build_valkyrie.m   ← committed
  output/            ← NOT committed, in .gitignore
```

> If `config`, `helpers`, or `graphics` contain files not on the MATLAB path automatically, the Step 3 dependency check (`requiredFilesAndProducts`) is what confirms the build actually picks them all up — check its output against these three folders specifically.

---

## 1. Sync and freeze the source

In the Command Window:
```powershell
!git checkout main
!git pull
!git status            # must be clean — no uncommitted changes
!git log -1 --oneline  # record this commit SHA in the release notes
```

- [ ] On `main`, up to date with remote
- [ ] Working tree clean
- [ ] Commit SHA recorded

> Never build from a dirty working tree. If a local change is needed, commit it first — otherwise the released binary corresponds to no known source state.

---

## 2. Decide the version and update the changelog

Use semantic versioning: `MAJOR.MINOR.PATCH`

- **MAJOR** — breaking change (input file format, saved-session compatibility, workflow removed)
- **MINOR** — new feature, backwards compatible
- **PATCH** — bug fixes only

Then:

- [ ] Update `valkyrieVersion.m`
- [ ] Add a `CHANGELOG.md` entry (Added / Changed / Fixed / Known issues)
- [ ] If the MATLAB release changed since the last version, flag it — users will need a new MATLAB Runtime
- [ ] Commit: `git commit -am "Bump version to X.Y.Z"` and push

---

## 3. Run-through from source in MATLAB

Run the app from the `.mlapp` in App Designer, on the freshly pulled code.

- [ ] App opens with no warnings or errors in the Command Window
- [ ] Version shown in the app matches Step 2
- [ ] Smoke test: work through the checklist in `TEST_CHECKLIST.md` (see Appendix A)
- [ ] Every new/changed item from the changelog is exercised
- [ ] No errors printed at any point

**Dependency check** — catches files that only exist on your machine:

```matlab
[files, products] = matlab.codetools.requiredFilesAndProducts('app_source/VALKYRIE.mlapp');
files'      % all paths must be inside the repo (app_source, config, helpers, graphics)
products.Name'  % all toolboxes must be in BUILD_ENVIRONMENT.md
```

- [ ] No dependency outside the repo
- [ ] Every file returned falls inside `app_source/`, `config/`, `helpers/`, or `graphics/`
- [ ] No unexpected toolbox

> Anything listed here that lives outside the repo will be missing for users. Either add the file to the repo, or add it explicitly to the build in Step 4.

---

## 4. Compile

Use a **build script**, not the Application Compiler GUI. The GUI hides settings and drifts between releases; a script is committed, reviewed, and identical every time.

The script lives at `build/build_valkyrie.m` (full listing in Appendix D — copy it in as-is). It:

1. Adds `app_source`, `config`, `helpers`, `graphics` to the path so `VALKYRIE.mlapp` and everything it calls are found
2. Reads the version from `valkyrieVersion.m`
3. Compiles the standalone executable, explicitly bundling `config`, `helpers`, and `graphics` as additional files (so runtime-loaded assets aren't silently dropped even if the dependency scan misses them, e.g. files loaded by dynamic path rather than direct call)
4. Packages the installer, named with the version number

Run it:

```matlab
cd build % navigate to folder with the script
build_valkyrie
```

- [ ] Build completes with no errors
- [ ] `mccExcludedFiles.log` reviewed — nothing important excluded
- [ ] Installer produced with the version number in its filename
- [ ] `build/output/` is in `.gitignore` (binaries do not belong in Git — they go on the release page)

**On `RuntimeDelivery`:** `'installer'` bundles the MATLAB Runtime (~1–2 GB installer, works offline). `'web'` downloads it during install (small installer, needs internet). Pick one and keep it consistent, or publish both and label them clearly.

---

## 5. Test the installer (preferably on another PC)

Best would be to test on a new PC, one that doesn't already have MATLAB installed.
If that isn't possible, just install and test on the build-PC. 

- [ ] Installer runs from a normal (non-admin) user account, or admin requirement is documented
- [ ] MATLAB Runtime installs correctly
- [ ] Start-menu/desktop shortcut created and launches the app
- [ ] Correct version displayed in the app
- [ ] Full smoke test (Appendix A/TEST_CHECKLIST.md) passes on the compiled app
- [ ] Reading and writing files works — including in the paths a real user would use
- [ ] Nothing tries to write into `C:\Program Files\` (blocked for standard users)
- [ ] App closes cleanly, no orphaned processes
- [ ] Uninstall works and removes the shortcut
- [ ] Reinstall over an existing installation works (upgrade path)

> The compiled app is not the same as the app in MATLAB: `pwd` differs, `matlabroot` is gone, no toolbox paths, and anything relying on `which`/`exist`/`addpath` may behave differently. This step is the one that catches those.

If anything fails: fix, commit, and restart from **Step 1**. Do not patch the binary.

---

## 6. Tag and release on GitHub

Generate a checksum first. Open Powershell and make sure to change the path to the new installer file.
The checksum will generate a sort of fingerprint for the recently build installer file. If something is not working a user can check that the checksum of their downloaded copy is identical to the one in our release.

```powershell
Get-FileHash .\Valkyrie_1.0.0_Setup.exe -Algorithm SHA256
```
When this has run it will generate a very long Hash string that is used in the release.
A check here could be to download installer after release and check that the checksum matches what was uploaded.


Tag the exact source that was built. For example:

```powershell
git tag -a v1.0.0 -m "Valkyrie 1.0.0"
git push origin v1.0.0
```

Create the release (GitHub → Releases → Draft a new release, or `gh release create`):

On GitHub:
- [ ] Tag: `v1.0.0`, target = the commit from Step 1
- [ ] Title: `Valkyrie 1.0.0`
- [ ] Notes from the template in Appendix B
- [ ] Installer attached as a release asset
- [ ] SHA-256 listed in the notes
- [ ] Required MATLAB Runtime version stated
- [ ] Marked as pre-release if it is a test build
- [ ] Publish

In the powershell: 
OBS: here the .md document for the release notes have to be generated first, with the information listed above.
```powershell
gh release create v1.0.0 .\Valkyrie_1.0.0_Setup.exe --title "Valkyrie 1.0.0" --notes-file notes.md
```

---

## 7. Post-release

- [ ] Download the asset from the release page and install it once more — confirms the upload is not corrupted
- [ ] Archive the build output (installer + `mccExcludedFiles.log` + `BUILD_ENVIRONMENT.md`) somewhere outside the repo
- [ ] Announce to users; state explicitly if a new MATLAB Runtime is required
- [ ] Update any documentation referring to the version

**Rollback:** if a serious defect appears, mark the release as a pre-release or delete the asset, point users to the previous release, and ship a PATCH version. Never replace the asset of a published version — reused version numbers make support impossible.

---

## Appendix A — Smoke test checklist (template)

Keep this in the repo as `TEST_CHECKLIST.md` and run through it the same way on the App Designer (Step 3) and on the compiled app (Step 5).

| # | Action | Expected result | Source | Compiled |
|---|---|---|---|---|
| 1 | Launch app | Main window opens, correct version | ☐ | ☐ |
| 2 | Load a known-good input dataset | Loads, summary populated | ☐ | ☐ |
| 3 | Load a deliberately malformed file | Clear error message, app survives | ☐ | ☐ |
| 4 | Run the main analysis | Completes, values match reference output | ☐ | ☐ |
| 5 | Every button worked | Renders, no errors | ☐ | ☐ |
| 6 | Export results | File written, opens correctly | ☐ | ☐ |
| 7 | Close and relaunch | Clean start, settings retained if applicable | ☐ | ☐ |
| 8 | Check error log file | Follow the path at start-up and check it has written an error log | ☐ | ☐ |

Use the sample data in /SampleDeployments as well as the VALKYRIE Sample Metadata - Sample Files.csv as metadata.

## Appendix B — Release notes template

```markdown
## Valkyrie X.Y.Z

**Requires:** MATLAB Runtime R20XXx (bundled in this installer / downloaded during install)
**Built from:** commit <sha>

### Added
-

### Changed
-

### Fixed
-

### Known issues
-

### Installation
1. Download `Valkyrie_X.Y.Z_Setup.exe` below
2. Run the installer and follow the prompts
3. Launch Valkyrie from the Start menu

Existing users: install over the previous version. If the required MATLAB
Runtime version has changed, the installer will handle it.

SHA-256: `<hash>`
```

## Appendix C — Release issue checklist

Paste into a GitHub issue per release, so each step is ticked visibly by whoever performed it.

```markdown
Release: vX.Y.Z — Owner: @______

- [ ] 1. Pulled `main`, clean tree, SHA recorded: ______
- [ ] 2. Version bumped, changelog updated, pushed
- [ ] 3. Run-through from source passed + dependency check clean
- [ ] 4. Compiled via `build_valkyrie.m`, excluded-files log reviewed
- [ ] 5. Installer tested on clean PC (install, run, smoke test, uninstall)
- [ ] 6. Tagged, release published with installer + checksum
- [ ] 7. Asset re-downloaded and verified, build archived, users notified
```
## Appendix D — build_valkyrie.m

The authoritative copy lives at `build/build_valkyrie.m` in the repo — that is the file to edit, run, and review in PRs. It:

1. Resolves all paths relative to its own location (`<repo root>/build/build_valkyrie.m`), so it works regardless of who runs it or from where
2. Verifies `app_source`, `config`, `helpers`, `graphics`, and `VALKYRIE.mlapp` exist before doing anything, with a clear error if not
3. Adds those four folders to the path and reads the version from `valkyrieVersion.m`
4. Compiles the executable, bundling `config`, `helpers`, `graphics` as `AdditionalFiles`
5. Attaches `graphics/icon64.png` as the executable icon and `graphics/valkyrieV1.png` as the splash screen — only if those files exist, and only if `ExecutableIcon` accepts `.png` on your MATLAB release (see caveat below)
6. Packages the installer, named `Valkyrie_<version>_Setup`

Run it:

```matlab
cd build
build_valkyrie
```

Notes:
- **Icon format caveat:** `ExecutableIcon` traditionally expects a `.ico` file for Windows executables; some MATLAB releases accept `.png` directly, others don't. If Step 4 errors on that line, convert `icon64.png` to `.ico` and update the path in the script. `ExecutableSplashScreen` accepts `.png` normally.
- `'RuntimeDelivery', 'installer'` bundles the MATLAB Runtime (large, offline-capable). Switch to `'web'` for a smaller installer that downloads the runtime during setup — see Step 4 in the main process.
- If `config`, `helpers`, or `graphics` end up empty in a given release, `compiler.build` will error on a missing folder reference — keep at least a placeholder file in each, or guard the `AdditionalFiles` list with an `isfolder` check.