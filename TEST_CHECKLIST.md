
## Appendix A — Smoke test checklist (template)

Run through it the same way on the App Designer (Step 3) and on the compiled app (Step 5).

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
