# Valkyrie — Build Environment

This file records the exact toolchain used to produce official releases. Update it
**whenever any value below changes**, and mention the change in that release's
`CHANGELOG.md` entry — a MATLAB release change usually means users need a new
MATLAB Runtime.

| Item | Value | Notes |
|---|---|---|
| MATLAB release | R2025b | Determines the required MATLAB Runtime version for end users |
| MATLAB Compiler | installed | Required for `compiler.build.standaloneWindowsApplication` |
| MATLAB Compiler SDK | installed | Required for `compiler.package.installer` |
| Required toolboxes | No recquired toolboxes | Must be licensed on the build machine; cross-check against `requiredFilesAndProducts` output each release (Step 3) |
| Build machine | Mia L. K. Nielsen/D54296 | Designated machine, or a documented VM image/snapshot |
| Build machine OS | Windows 11 (64-bit) | |
| Test machine | _name/ID, e.g._ clean Win11 on Viretual Machinge, snapshot called "pre-install"_ | No MATLAB installed. Revert to snapshot before each Step 5 test |
| `RuntimeDelivery` mode | `installer` | `installer` = MATLAB Runtime bundled (offline-capable, large). `web` = runtime downloaded during setup (small, needs internet). Keep consistent across releases unless deliberately changed and documented here |
| MATLAB Runtime version shipped | R2025b | Must match what installer users will receive |

## Change log for this file

| Date | Changed by | What changed | Why |
|---|---|---|---|
| _YYYY-MM-DD_ | _name_ | _e.g. MATLAB release bumped R2024a → R2024b_ | _reason_ |

## Notes

- If the MATLAB release used to build changes, every user installing the new version
  will need the matching MATLAB Runtime — call this out explicitly in that release's
  GitHub release notes, not just here.
- If a new toolbox becomes a dependency, add it to this table **and** verify it's
  actually licensed on the build machine before attempting Step 4 (Compile).