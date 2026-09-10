# minICI back-fill: decision log and verification history

This is the "why" document -- what we checked, what broke, and what we decided
along the way. For "how to run it," see `README_minICI.md`.

## 1. Was the minICI computation itself correct?

Before any bulk work, the very first check compared `minICI_workflow`'s output
against a detection file already sitting in the database, on the first 3 real
files. Result: **456,108 shared keys, zero mismatches across all 9 comparable
columns** (temperature, clicks, angle, DPM, milliseconds, time-lost, recorded,
species). Extra rows in the new output were entirely outside the archive's
time window -- expected, since the archive is cropped to the deployment period
and the raw reprocessing isn't.

The `min_ici` values themselves were checked against an invariant that held
throughout the whole project: **the count of `min_ici` values inside the
deployment window must exactly equal the count of click-positive rows in the
archive.** This became the single most-repeated correctness check.

## 2. Filenames could not be trusted as an identity

A single physical deployment appears under three different names depending on
where you look:
- the database's own filename (deployment date)
- the raw POD file's own name (power-on OR recovery date, inconsistent)
- the archived processed CSV's filename (deployment date again, but a
  different station-code convention in some)

Matching therefore never used filenames as an identity. It used **POD serial +
a real time window + deployment-identity grouping (full station token + date,
not just station base)**, with the filename only used for tie-breaking and
reporting.

## 3. Format assumptions that turned out wrong, and how we found out

Every one of these was caught by checking real data before trusting an
assumption, not by guessing correctly the first time:

- **The pasted `novana-bpm.csv` sample came from Excel.** Excel always
  re-exports pasted cells as tab-separated and reformats dates to the local
  display format, regardless of the source file's real delimiter or format.
  Built `inspectBigFile` to read raw bytes directly rather than trust a paste;
  the real file turned out to be comma-delimited, fully quoted, ISO datetimes
  -- unambiguous, once actually checked.
- **`minICI_workflow`'s real signature** was not `(inPath, outPath)`. It's
  `minICI_workflow(inPath, 'PairPath', p, 'OutputCsv', folder, 'MatchName', m,
  'Verbose', v)` -- one positional argument, everything else name-value,
  returns a struct not a table. Found only once real error messages exposed
  it.
- **`'OutputCsv'` is a folder, not a file path**, despite the docstring
  calling it a "CSV path." `minICI_workflow` names the file itself as
  `<MatchName>_minICI.csv` inside whatever folder you give it. Found by
  reading the exact malformed nested path in the write error.
- **A `.cp1`/`.cp3` pair shares the same base filename**, confirmed by an
  existing process rather than assumed -- but they aren't always in the same
  folder. `minICI_workflow` looks in the same folder as whatever it's given,
  and needs `'PairPath'` explicitly when the pair lives elsewhere
  (`findCompanionRawFiles` exists for exactly this).

## 4. Matching mistakes the automated matcher made, caught by verification

The "does this file's actual content match what's already in the database"
check (`verifyMinICIAgainstArchive`, eventually run over all 174 deployments
via `runVerificationBatch`) caught real automated-matching errors that would
otherwise have gone to the database silently wrong:

- **`GB4`/`GB5`/`LB3`**: two differently-named, differently-dated candidate
  deployments for the same POD, within days of each other. No way to resolve
  from filenames alone -- genuinely needed a person to pick, based on which
  raw file's actual data range covered the deployment window.
- **`KF1_2012_02_13_POD1693`**: the automated "nearest date" tie-break picked
  a *partial, mislabeled duplicate* of one part over the correctly-paired,
  complete two-part deployment sitting one day further away. A one-day
  date quirk let a partial group beat the genuinely correct one.
- **`KF4_2012_02_11_POD1691`**: the matcher picked a file from a completely
  different station family (`KALF2C`, the KF2 lineage) purely because its
  date matched exactly, over the genuinely correct `KF4`-family file that
  was 2 days off. **This is a known, unfixed limitation**: the matcher's
  `matched_nearest` path only checks competing candidates for station-family
  plausibility when there's an actual tie -- a single "winning" candidate
  with an exact date match is never cross-checked against station identity.
  It was caught here because verification is comprehensive, not because the
  matcher itself would flag it next time.

**Takeaway kept for the record**: the two-layer design (an imperfect
automated matcher, backstopped by verifying every single output against real
database content) is what actually caught these -- not matcher perfection.

## 5. Coverage: making sure nothing was silently missing

Two directions were checked, not just one:
- **Every deployment in the database has a corresponding processed CSV** --
  confirmed (`0` missing), meaning the 176-deployment folder survey was a
  complete proxy for the database's contents.
- **Every processed deployment resolves to something** -- 174 of 176 have a
  reprocessable raw file; the other 2 (`8009_2019_02_26_POD1687`,
  `FB3_2015_04_20_POD1694`) were checked directly and confirmed **not
  currently in the database at all** -- correctly excluded, not silently
  dropped.

## 6. The final proof: matching the duplicated rows

Once the full run's 3,349,901 written rows came back **exactly** 152,884
higher than the 3,197,017 offered, that gap was checked against something
independently known rather than accepted as-is:

```
FF2_2019_09_17_POD1981:  62,006 x 2 = duplicate contribution
LB3_2019_09_17_POD1687:  62,313 x 2 = duplicate contribution
LB4_2019_09_17_POD1976:  28,565 x 2 = duplicate contribution
                                total: 152,884  <-- matched exactly
```

That exact match is what turned "written is bigger than offered, is that
okay?" into real confidence: the entire discrepancy was accounted for by the
three specific, independently-verified live-database duplications found
earlier -- nothing unexplained was hiding in the difference. Combined with
`checkMismatch: 0` (even the duplicated rows passed the independent
`number_clicks_filtered`/`milliseconds` cross-check) and the click-positive
row-count invariant holding exactly at full scale, this was the strongest
validation point in the whole project.

## 7. The two archive/database duplication findings

- **`FF2_2019_09_17_POD1981`'s old local archive CSV** was found to have
  every single row duplicated exactly twice (795,261 unique rows, 1,590,522
  total). Confirmed as a pure artifact (byte-identical duplicate rows, exact
  2.0x ratio) and fixed at the source with `dedupeArchiveFileInPlace`
  (backed up first, dry-run supported).
- **The live database (`novana-bpm`) itself has the same duplication
  pattern** for 3 deployments (`FF2_2019_09_17_POD1981`,
  `LB3_2019_09_17_POD1687`, `LB4_2019_09_17_POD1976`, all dated
  `2019-09-17`) -- confirmed by pulling the actual rows and comparing them
  side by side. This is flagged to the database team as its own issue, not
  fixed by this project: both duplicate rows correctly receive the same
  `min_ici` value, and the dedup decision is left to whoever owns the
  database schema.
- Both findings prompted the yearly DOI dataset generator to deduplicate
  generally (any full-row duplicate, not just these 3 by name), since that
  generator's scope is every deployment in the database, not just the 174
  this project touched.

## 8. Deliverables and why each exists

| Deliverable | For | Built from |
|---|---|---|
| `novana_min_ici_updates.csv` | Database team, targeted `UPDATE` by `id_pk` | `extractMinICIUpdates`, keyed to the actual unique row identifier |
| Yearly DOI datasets with `MIN_ICI` | The person generating DOIs, a different denormalised schema entirely | `addMinICIToYearlyFolder`, using a confirmed fixed quality-code mapping (3=Hi, 2=Mod, 1=Lo) |

The novana_min_ici_udpates.csv is considerablt smaller than the input novana-bpm.csv.
The main reason is that it only has rows that had clicks and therefore the min_ici specified,
and only  8 columns are included (compared to the 29 coulmns in the original).