# VALKYRIE — Clean-machine installer testing (VMware)

Companion to `TEST_CHECKLIST.md` and `app_source/VALKYRIE_release_process.md`.

The VM Workspace is used to test how the app will work for new users, also
if they have never had MATLAB installed on ther computers. 

Through AU we have access to the VM Workspace Pro [here](https://medarbejdere.au.dk/en/administration/it/buy-it-equipment-and-software/agreements-about-software/vmware-academic-software-licensing-program)
Follow the guide on How to Access VMware. Through that you will need to register 
and download the **latest version of VM Workstation Pro**.

Through the VM Workstation Pro you can run the existing clean workspace to 
test the installation. 

The VM is already built and lives on the shared drive at:

    O:\Nat-Tech_DTO-BioFlow\VALKYRIE\Virtual Machine\Windows 11 x64.vmx


---

## Quick start — running a test

You do **not** need to install Windows or set anything up — that part is
done. This is the whole process:

1. **Install VMware Workstation Pro** via the Broadcom institutional portal.
    Just download the app — nothing else to configure.
2. **Open the existing VM**: in Workstation, **File → Open**, browse to
   `O:\Nat-Tech_DTO-BioFlow\VALKYRIE\Virtual Machine\Windows 11 x64.vmx`, 
    click **Open**.
3. **First time only**, you'll see *"Did you move or copy this virtual
   machine?"* — choose **"I copied it."**
4. **Revert to the clean snapshot**: select the VM in the Library, then
   **VM → Snapshot → Revert to Snapshot** (or **Snapshot Manager** if more
   than one snapshot exists) → `clean-no-matlab` → confirm.
5. **Power on** the VM. It logs in automatically, or with the shared
   local account/password if auto-login isn't set — same login for everyone,
   since it's baked into the VM image.
    Profile name: VALKYRIE_test
    Password:     VALKYRIE_test
6. **Copy in** the files to test: the new installer
   (`VALKYRIE_x.y.z_Setup.exe`), the `/SampleDeployments` folder or necessary 
    files to test, and the sample metadata CSV. Ordinary clipboard copy/paste 
    works (VMware Tools is already installed in the snapshot).
7. **Run the installer.** Expect a **SmartScreen** warning ("Windows
   protected your PC") — this is normal, the installer isn't code-signed.
   Click **"More info" → "Run anyway."** Note how long the install takes and
   anything unusual along the way.
8. **Launch VALKYRIE** from the shortcut it created. Check:
   - The version number is correct in the window title and the bottom-right
     label
   - `%APPDATA%\VALKYRIE\logs\` has a fresh session log, and its header shows
     the right version, `Deployed (compiled): 1`, and a sensible base path
9. **Run the smoke test**: work through `TEST_CHECKLIST.md`'s "Compiled"
   column using the sample data.
10. **Record the result** (pass/fail; keep the log file if anything failed)
    with the release notes for that version.
11. **Revert to `clean-no-matlab` again before closing** — the next person
    (or your future self) should always start from the clean baseline,
    never from a "used" state.

### Rules for sharing the VM from O:\

- **Only one person can have it powered on at a time.** VMware locks the
  running VM's files, so a second person opening it while it's live gets an
  error, not a second copy. Check with the team, or agree on a schedule.
- Running it live off the network share works but can be noticeably slower
  than local disk, especially through Windows Update or the installer's
  self-extraction step. If this becomes annoying for regular testers, copy
  the whole VM folder once to your own local disk instead (step 3's "I
  copied it" choice is exactly for this) and keep your own independent
  baseline from then on — re-copy from O:\ only if the shared baseline
  itself changes.
- Never store the VM inside a continuously-syncing cloud folder (OneDrive,
  Dropbox). A live VM disk file changes constantly while running, and a sync
  client trying to upload a file mid-write is a known corruption risk.

---

## One-time VM setup (already done — for reference / rebuilding the baseline)

1. **Install VMware Workstation Pro** (Windows) via the
   [Broadcom institutional portal](https://medarbejdere.au.dk/en/administration/it/buy-it-equipment-and-software/agreements-about-software/vmware-academic-software-licensing-program).
2. **Download a Windows 11 ISO** from microsoft.com/software-download/windows11.
   No product key needed — choose "I don't have a product key" during setup.
3. **Create the VM**: at least 60 GB disk, 8 GB RAM.
4. **Work through Windows setup (OOBE).** Current Windows 11 builds have
   removed most local-account bypasses. If forced to sign in:
   - Use a personal (non-AU) Microsoft account, never a work/AU account —
     signing in with an institutional account risks enrolling this throwaway
     VM in AU's device management.
   - Once at the desktop: **Settings → Accounts → Your info → "Sign in with
     a local account instead"** to detach it again.
5. **Install VMware Tools** (VM menu → Install VMware Tools, inside the
   guest). This enables normal clipboard/drag-and-drop between host and VM.
6. **Take a snapshot immediately**, before installing anything else:
   VM menu → Snapshot → Take Snapshot → name it `clean-no-matlab`.
   This is the reusable baseline. **Never install MATLAB, VALKYRIE, or
   anything else onto this snapshot** — always branch off it, and always
   revert back to it, never past it.
7. **Move the whole VM folder** (not individual files — `.vmx`, `.vmdk`,
   `.nvram`, snapshot files all travel together) to the shared O:\ drive if
   it isn't there already, and record the exact path at the top of this doc.

---

## Quick reference

| Step | Where |
|---|---|
| Open the VM | Workstation → File → Open → `O:\Nat-Tech_DTO-BioFlow\VALKYRIE\Virtual Machine\Windows 11 x64.vmx` |
| Revert snapshot | VM → Snapshot → Revert to Snapshot → `clean-no-matlab` |
| Copy files in | Clipboard copy/paste (needs VMware Tools) |
| Session log | `%APPDATA%\VALKYRIE\logs\` |
| Smoke test | `TEST_CHECKLIST.md`, Compiled column |
| Re-baseline | Revert to `clean-no-matlab` when done |
