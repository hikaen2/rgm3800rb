# Proposal

## Why

The logger's clock passed its GPS week-rollover limit in 2026 (between 2026-01 and 2026-09), so every track it records now carries dates 1024 weeks (7168 days) early, e.g. 2007-02-03 for 2026-09-19. Every future download needs correcting, and the one archive already affected (`~/src/gps-logs/2026-09-19-france/`) can no longer be re-downloaded because the logger has since been erased.

## What Changes

- Add `download --fix-rollover`, which adds exactly 1024 weeks to each track's start date before naming the file and dating its waypoints. Without the option, output stays identical to the official tool.
- The correction is always the user's explicit choice; the tool does not try to detect whether dates are wrong.
- Regenerate the 9 files in `~/src/gps-logs/2026-09-19-france/` from the private raw fixture (`test/fixtures/france/raw.json`) with corrected dates, and replace the wrongly dated originals after verification. This also fixes the official tool's date-revert defect in track 4.
- Update README.md ("Known issue: wrong dates") and docs/protocol.md to describe the option.

Out of scope: automatic rollover detection, a general command for rewriting dates in existing NMEA files, and correcting other archives.

## Capabilities

### New Capabilities
- None.

### Modified Capabilities
- `track-download`: the requirement "Dates are not corrected" changes so that dates are corrected by 1024 weeks when `--fix-rollover` is given.

## Impact

- `rgm3800.rb`: `download` option parsing and the start date used for file names and waypoint dates.
- `test/test_rgm3800.rb`: tests for the option.
- `README.md`, `docs/protocol.md`.
- `~/src/gps-logs/2026-09-19-france/` (separate git repository): 9 files renamed and rewritten; the originals remain in its git history and in the private fixture.
