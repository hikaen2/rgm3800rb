# Spec Delta

## MODIFIED Requirements

### Requirement: Dates are not corrected
The tool SHALL output the dates as reported by the logger, without correcting the GPS week-number rollover, unless the user runs `download --fix-rollover`. With that option, the tool SHALL add exactly 1024 weeks (7168 days) to each track's start date before naming the file and dating its waypoints. The tool SHALL NOT decide automatically whether a correction is needed.

#### Scenario: Logger after rollover
- **WHEN** the logger reports a track start date of 2007-02-03 for a track recorded on 2026-09-19
- **THEN** the file is named `..._20070203.nmea` and its RMC dates are in 2007

#### Scenario: Corrected file name and dates
- **WHEN** the logger reports a track start date of 2007-02-03 and the user runs `download --fix-rollover`
- **THEN** the file is named `..._20260919.nmea` and its first RMC date field is `190926`

#### Scenario: Corrected track crossing UTC midnight
- **WHEN** a track reported as starting 2007-02-07 crosses UTC midnight and is downloaded with `--fix-rollover`
- **THEN** its file is named `..._20260923.nmea`, waypoints before midnight are dated 2026-09-23, and waypoints from midnight on are dated 2026-09-24

#### Scenario: Only dates change
- **WHEN** the same tracks are downloaded with and without `--fix-rollover`
- **THEN** the outputs differ only in file names and in the RMC date and checksum fields; all `$GPGGA` lines are identical

#### Scenario: Correct dates are shifted too
- **WHEN** the user gives `--fix-rollover` for tracks whose dates are already correct
- **THEN** the dates are still shifted by 1024 weeks, because the option is an explicit user choice
