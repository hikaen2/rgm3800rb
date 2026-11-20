# Tasks

## 1. Rollover option

- [x] 1.1 Add a `ROLLOVER = 7168` (days, 1024 weeks) shift to `cmd_download`, controlled by a `--fix-rollover` option on `download`, applied to the start date before the file name and `nmea` call; verify with a unit test that a track dated 2007-02-03 yields file name `..._20260919.nmea` and first RMC date `190926`.
- [x] 1.2 Add a unit test for the midnight scenario on the fixture's track 4 with the shift: waypoints before midnight are dated `230926`, waypoints from 00:00:22 on `240926`, and the file name is `00004_20260923.nmea` (skipped when the private fixture is absent, like the existing reference test).
- [x] 1.3 Add a unit test that, for every fixture track, output with and without the shift differs only in RMC date and checksum fields (all `$GPGGA` lines identical); verify `ruby -Itest test/test_rgm3800.rb` passes.
- [x] 1.4 Update `USAGE`, README.md ("Known issue: wrong dates": use `download --fix-rollover` for this logger; do not use it for an unaffected logger) and docs/protocol.md (the `PROY101` rollover note); verify `ruby rgm3800.rb --help` shows the option and the README commands run as written.

## 2. Regenerate the France archive

- [x] 2.1 Regenerate the 9 files from `test/fixtures/france/raw.json` with `RGM3800.decode` and `RGM3800.nmea` using start date + 7168 days, writing to a temporary directory; verify 9 files named `00000_20260919.nmea` ... `00008_20260927.nmea`.
- [x] 2.2 Compare with `~/src/gps-logs/2026-09-19-france/`; verify the same line count per file (4374 in total), identical `$GPGGA` lines, `$GPRMC` lines differing only in date and checksum, every RMC date equal to the official date + 7168 days except the 87 track-4 waypoints after 00:00:22, which are one day later, and the date range 2026-09-19 to 2026-09-27.
- [x] 2.3 After the user approves the comparison, replace the files in `~/src/gps-logs/2026-09-19-france/` (`git rm` the 2007-named files, add the new ones) without committing; verify `git -C ~/src/gps-logs status` shows 9 renames/modifications and nothing else. The user decides whether to commit.
