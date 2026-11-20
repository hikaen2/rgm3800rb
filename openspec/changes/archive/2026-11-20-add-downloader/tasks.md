# Tasks

## 1. Record conversion (no hardware)

- [x] 1.1 Create `test/fixtures/france/`: copy the 9 official files from `~/src/gps-logs/2026-09-19-france/` and store the raw records of tracks 0-8 (start date, format, record bytes) as `raw.json` (hex-encoded records). Source: the exploration capture at `/tmp/claude-1000/-home-taro-src-rgm-3800/722d7e38-170f-453f-b819-a598684f273d/scratchpad/raw.pkl` if it still exists, otherwise capture after task 2.4 (the tracks are still on the logger; do not erase it). Verify 2187 records and 9 official files are present.
- [x] 1.2 Create `rgm3800.rb` skeleton with `if __FILE__ == $0` guard and a minitest runner (`ruby -Itest test/test_*.rb`); verify an empty test run passes.
- [x] 1.3 Implement record decoding for formats 0-2 (valid flag, time, lat/lon radians, altitude, speed; skip records whose valid byte is not 1; reject other formats); verify with unit tests on the sample record `01 07 12 24 f6 6d 5a 3f ...` from design.md.
- [x] 1.4 Implement NMEA line building (GGA + RMC, checksum, CRLF, official field layout, single-precision degree conversion, date advance rule); verify the spec scenario "Format 2 waypoint" produces the exact two lines.
- [x] 1.5 Add the reference test: convert `raw.json` and verify files 00000-00003 and 00005-00008 are byte-identical to the official files and 00004 differs only in the RMC date of the 87 waypoints after 00:00:22.
- [x] 1.6 Write the "Record format" and "NMEA conversion" sections of `docs/protocol.md` (English), marking each fact as verified on hardware, verified against official output, or from other sources (rgm3800py, OSM wiki); verify every byte offset and format string in the doc matches the code.

## 2. Serial protocol (canned streams, then hardware)

- [x] 2.1 Implement command sending (`$PROYnnn...*HH\r\n`) and response framing by checksum (binary payload may contain `*` and CRLF); verify with unit tests using canned byte streams, including a payload containing `*41\r\n` and a corrupted line that must be discarded.
- [x] 2.2 Implement serial device opening with `stty -F <dev> 115200 raw -echo` and a read timeout; verify a clear error and non-zero exit for a missing device and for a device without permission.
- [x] 2.3 Implement `PROY108`, `PROY100` and `PROY101` queries with parsing; verify with canned replies in unit tests, then on hardware that track count and track info match the values in design.md.
- [x] 2.4 Implement chunked `PROY102` reads (≤ 4800 bytes per request, up to 5 retries per chunk); verify on hardware that all 2189 waypoints of tracks 0-9 are received.
- [x] 2.5 Write the "Physical layer", "Line format" and "Commands" sections of `docs/protocol.md`, including the unknown `PROY108` fields and the `PROY003`/`PROY005`/`PROY006`/`PROY109` commands seen in rgm3800py marked as unverified; verify each verified command is exercised by a test or hardware check.

## 3. Track listing and download

- [x] 3.1 Implement the CLI skeleton (`OptionParser`, `-d DEV` defaulting to `/dev/ttyUSB0`, usage on unknown command, progress to stderr); verify `ruby rgm3800.rb --help` prints the four commands.
- [x] 3.2 Implement `list`; verify on hardware that it prints 10 lines matching the track numbers, dates, counts and formats from exploration, and that an empty track list prints nothing with status 0 (unit test with canned replies).
- [x] 3.3 Implement track selection parsing (`N`, `N-`, `N-M`, `-K`, errors for malformed or out-of-range); verify with unit tests for each form.
- [x] 3.4 Implement `download [-o DIR] [RANGE]` writing `NNNNN_YYYYMMDD.nmea` via temporary file and rename, overwriting existing files, rejecting unsupported formats with an error; verify on hardware that `cmp` against `~/src/gps-logs/2026-09-19-france/` gives 8 identical files and only the known difference in 00004.
- [x] 3.5 Write `README.md` (install, `dialout` permission, `list`/`download` usage, known GPS week-rollover date error, credits to rgm3800py and the OSM wiki); verify the documented commands run as written.

## 4. Logger configuration

- [x] 4.1 Implement `info` (format, interval, memory-full, track count, memory usage from `PROY100` and track sizes); verify on hardware that it shows format 2, 60 s, stop.
- [x] 4.2 Implement `config` option validation (type 0-2, interval 5-60, memory-full overwrite|stop, no options = usage) before any device access; verify with unit tests for each rejected value.
- [x] 4.3 Implement `config` writing with `PROY104`, keeping unspecified values, and read-back confirmation via `PROY108`; verify on hardware by setting interval 15 s, checking `info`, then restoring format 2, 60 s, stop.
- [x] 4.4 Add the `PROY104` result to `docs/protocol.md` (now verified) and `info`/`config` usage to `README.md`; verify the documented commands run as written.

## 5. Integration check

- [x] 5.1 On hardware, run `list`, `download -o <tmpdir>`, `info` and `config` end to end and verify exit codes, stderr/stdout separation, and that no partial file remains after interrupting a download (Ctrl-C).
