# Design

## Context

See proposal.md for motivation. `cmd_download` names each file from `t[:date]` (the `PROY101` start date) and passes the same date to `nmea(waypoints, start_date)`, which advances the date whenever the time of day decreases. Records carry no date of their own. The private fixture `test/fixtures/france/raw.json` (git-ignored) holds the raw records and start dates of the 9 France tracks; the logger's copy was erased.

## Goals / Non-Goals

**Goals:**
- Correct dates at download time with a single explicit option.
- Regenerate the France archive using exactly the same conversion code.

**Non-Goals:**
- Detecting rollover automatically.
- Rewriting existing NMEA files in general.

## Decisions

### Shift the track start date only
Add 1024 weeks to `t[:date]` once, before it is used for the file name and for `nmea`. The waypoint date-advance rule then works unchanged from the corrected date. Alternative: shift each RMC date after formatting — more code and duplicates date handling.

### Explicit option, no automatic detection
A rule such as "shift dates earlier than X" is ambiguous. Shifted dates of logs recorded from about 2027 onward fall into 2008 and later, the same range as the correctly dated archive (2008-2025). The user knows which logger state applies, so the option is explicit. Shifting by exactly 1024 weeks is always correct for this logger after its rollover. A second rollover would only happen about 19.6 years later.

### Regenerate France from the fixture, not by editing files
Run the library's `decode` and `nmea` on `raw.json` with corrected start dates (a one-off `ruby -r ./rgm3800 -e ...` command recorded in tasks.md, not a new CLI command). This uses the same code path as `--fix-rollover`, fixes the track 4 date revert in the official files, and needs no NMEA parser. Alternative: a `fix-dates FILE...` command that rewrites existing files — 30-40 more lines and a risk of double correction, for a single affected archive.

### Verification before replacing the archive
Compare the regenerated files with the official ones. The expectation is: same number of files and lines, identical `$GPGGA` lines, and `$GPRMC` lines that differ only in the date and checksum. Every RMC date should equal the official date + 7168 days, except the 87 track-4 waypoints after 00:00:22, which should be one day later than that. The originals stay in the gps-logs git history (commit `0d906c1`) and in the private fixture.

## Risks / Trade-offs

- [User forgets the option and downloads with wrong dates] → The README states that `--fix-rollover` is needed for this logger. The files can be re-downloaded until the logger is erased.
- [User applies the option to an unaffected logger] → Documented as explicit behaviour; dates jump about 19.6 years into the future, which is obvious.
- [Fixture is only stored locally] → It is intentionally private. Keep a backup outside the repository if it is still needed after the France archive is regenerated.
