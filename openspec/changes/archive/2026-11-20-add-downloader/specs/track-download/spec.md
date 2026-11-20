# Spec Delta

## Purpose

Lets the user list the tracks stored on an RGM-3800 logger and download them from Linux as NMEA files identical to those produced by the official RoyalTek downloader.

## ADDED Requirements

### Requirement: Serial device selection
The tool SHALL communicate with the logger over a serial device given by `-d <device>`, defaulting to `/dev/ttyUSB0`, at 115200 baud, 8N1, raw mode.

#### Scenario: Default device
- **WHEN** the user runs a command without `-d`
- **THEN** the tool opens `/dev/ttyUSB0`

#### Scenario: Device not accessible
- **WHEN** the device does not exist or the user lacks read/write permission
- **THEN** the tool prints an error naming the device and exits with a non-zero status

### Requirement: List tracks
The `list` command SHALL print one line per track stored on the logger, showing the track number, start date, number of waypoints, and record format.

#### Scenario: Logger with tracks
- **WHEN** the logger holds 10 tracks and the user runs `list`
- **THEN** the tool prints 10 lines, numbered 0 to 9, each with the track's start date, waypoint count and format

#### Scenario: Empty logger
- **WHEN** the logger holds no tracks
- **THEN** the tool prints nothing and exits with status 0

### Requirement: Download tracks to files
The `download` command SHALL write each selected track to its own file named `NNNNN_YYYYMMDD.nmea` (5-digit zero-padded track number, track start date) in the output directory given by `-o <dir>`, defaulting to the current directory. Existing files with the same name SHALL be overwritten.

#### Scenario: Download all tracks
- **WHEN** the user runs `download` without a track selection
- **THEN** the tool writes one file per track, e.g. track 0 started 2007-02-03 is written as `00000_20070203.nmea`

#### Scenario: Download selected tracks
- **WHEN** the user runs `download 7-9`
- **THEN** only tracks 7, 8 and 9 are written

#### Scenario: Track selection syntax
- **WHEN** the user gives a selection `N`, `N-`, `N-M` or `-K`
- **THEN** the tool selects track N only, N to the last track, N to M, or the last K tracks respectively

#### Scenario: Invalid selection
- **WHEN** the selection is malformed or out of range
- **THEN** the tool prints an error, writes no files and exits with a non-zero status

### Requirement: Official NMEA output format
Each waypoint SHALL be written as one `$GPGGA` line followed by one `$GPRMC` line, with CRLF line endings and a correct XOR checksum, using exactly the field layout of the official RoyalTek downloader for record formats 0-2 (see docs/protocol.md).

#### Scenario: Format 2 waypoint
- **WHEN** a format-2 waypoint at 07:18:36 UTC, latitude 0.8532404 rad, longitude 0.0485453 rad, altitude -47.3285 m, speed 71.6546 km/h on 2007-02-03 is written
- **THEN** the output is `$GPGGA,071836.000,4853.2244,N,00246.8864,E,1,00,,-47.3,M,0.0,M,,0000*5C` and `$GPRMC,071836.000,A,4853.2244,N,00246.8864,E,038.69,0.0,030207,,,E*5B`, each followed by CRLF

#### Scenario: Southern and western hemispheres
- **WHEN** a waypoint has negative latitude or longitude
- **THEN** the hemisphere fields are `S` or `W` and the coordinate value is the absolute value

### Requirement: Coordinate conversion compatible with the official tool
Latitude and longitude SHALL be converted so that the printed `ddmm.mmmm` / `dddmm.mmmm` values match the official downloader digit for digit: degrees are computed in single precision from the stored single-precision radians, and minutes are computed from those degrees in double precision and rounded to 4 decimals.

#### Scenario: Last-digit compatibility
- **WHEN** the 2187 waypoints of the reference fixture are converted
- **THEN** every latitude and longitude string equals the one in the official output

### Requirement: Waypoint dates
Waypoint records carry only a UTC time of day. The date of each waypoint SHALL start at the track's start date and advance by one day each time the time of day decreases compared to the previous waypoint of the same track.

#### Scenario: Track crossing UTC midnight
- **WHEN** a track started on 2007-02-07 has a waypoint at 23:59:22 followed by one at 00:00:22
- **THEN** the second waypoint and all following waypoints in that track are dated 2007-02-08 until the next decrease

### Requirement: Dates are not corrected
The tool SHALL output the dates as reported by the logger, without correcting the GPS week-number rollover.

#### Scenario: Logger after rollover
- **WHEN** the logger reports a track start date of 2007-02-03 for a track recorded on 2026-09-19
- **THEN** the file is named `..._20070203.nmea` and its RMC dates are in 2007

### Requirement: Byte-identical reference output
For the reference fixture (tracks recorded with format 2 and downloaded with the official tool), the tool's output SHALL be byte-identical to the official files, except for the known official-tool defect in track 4 where the official output reverts the date after UTC midnight.

#### Scenario: Reference comparison
- **WHEN** the fixture's raw records are converted
- **THEN** files 00000, 00001, 00002, 00003, 00005, 00006, 00007 and 00008 are byte-identical to the official files
- **AND** file 00004 differs only in the RMC date field of the 87 waypoints after 00:00:22

### Requirement: Unsupported record formats
The tool SHALL support record formats 0, 1 and 2 only. A track in any other format SHALL be reported as unsupported instead of being downloaded.

#### Scenario: Format 4 track
- **WHEN** a selected track uses format 4
- **THEN** the tool prints an error naming the track and its format, writes no file for it, and exits with a non-zero status

### Requirement: Reliable transfer
The tool SHALL verify the checksum of every response line and retry a data request when its response is incomplete or corrupted, failing with an error after a bounded number of retries.

#### Scenario: Corrupted response
- **WHEN** a data response line fails its checksum
- **THEN** the tool discards it and requests the same data again

#### Scenario: Logger stops responding
- **WHEN** retries are exhausted
- **THEN** the tool prints an error, does not leave a partial file for the failed track, and exits with a non-zero status
