# Proposal

## Why

The RoyalTek RGM-3800 GPS logger can only be downloaded with RoyalTek's Windows-only tool, and the existing Linux tool (rgm3800py) is an unfinished Python 3 port whose track download crashes. A small, self-contained Linux downloader is needed that produces the same NMEA files as the official tool, so new logs stay consistent with the existing archive of logs downloaded since 2008.

## What Changes

- Add `rgm3800.rb`, a single-file Ruby command-line tool (standard library only, no gems) that talks to the logger over its PL2303 USB serial port.
- List the tracks stored on the logger.
- Download tracks into per-track NMEA files that are byte-identical to the official RoyalTek downloader output (`NNNNN_YYYYMMDD.nmea`, `$GPGGA` + `$GPRMC`, CRLF).
- Show and set the logging configuration offered by the official tool: data type (formats 0-2), logging interval (5-60 s), and memory-full behaviour (overwrite/stop).
- Support only record formats 0-2; formats 3 and 4 are rejected with a clear error.
- Add `docs/protocol.md`, an English description of the serial protocol, record layout, and NMEA conversion rules, marking each fact as verified on hardware or taken from other sources.
- Add test fixtures (raw records captured from the logger and the matching official NMEA output) so the conversion can be tested without hardware.

Out of scope: erasing memory, G_Mouse mode, formats 3 and 4, GPX output, and correcting the GPS week-rollover date error (done as a separate post-processing step).

## Capabilities

### New Capabilities
- `track-download`: listing tracks on the logger and downloading them as NMEA files compatible with the official RoyalTek downloader.
- `logger-config`: reading and changing the logger's logging configuration (data type, interval, memory-full behaviour).

### Modified Capabilities
- None.

## Impact

- New files: `rgm3800.rb`, `docs/protocol.md`, tests and fixtures under `test/`.
- Runtime dependencies: Ruby (3.4 available) and `stty`; no gems.
- Requires read/write access to the serial device (e.g. `/dev/ttyUSB0`, group `dialout`).
- Licensed MIT. rgm3800py (GPLv3) and the OpenStreetMap wiki are used as protocol references only; no code is copied.
