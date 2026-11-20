# Design

## Context

See proposal.md for motivation. The facts below were established during exploration against a real logger (firmware `RoyalTek Ver 1.5.0.245 GSW3LP`, 8192 KB, format 2) and against the official downloader's output in `~/src/gps-logs/2026-09-19-france/` (9 tracks, 2187 waypoints).

- The logger is a PL2303 USB serial device (`067b:2303`, `/dev/ttyUSB0`, group `dialout`).
- The protocol is NMEA-style: `$<body>*<HH>\r\n`, where HH is the XOR of the body bytes. Commands are `PROYnnn`, replies `LOGnnn`. Data replies (`LOG102`) carry binary payload, so a raw `\r\n` or `*` can occur inside a line.
- Commands used (verified on hardware unless noted):
  - `PROY108` → `LOG108,<format>,?,?,<memfull>,?,<interval>,?,<tracks>,<wps in last track>`
  - `PROY100` → `LOG100,<total memory>,<sector size>,<sectors>`
  - `PROY101,<n>` → `LOG101,<yyyymmdd>,<format>,<waypoints>,<address>`
  - `PROY102,<address>,<format>,<count>` → one or more `LOG102,<u16 part><u8 len><records...>` lines
  - `PROY104,0,<interval>,<format>,<memfull>` → `LOG104,<1|0>` (not yet verified on hardware)
- Records are fixed-length little-endian: `u8 valid, u8 h, u8 m, u8 s, f32 lat_rad, f32 lon_rad[, f32 alt_m[, f32 vel_kmh]]`; format 0/1/2 = 12/16/20 bytes. Records have no date; the track start date comes from `PROY101`.
- The logger's clock has passed its GPS week-rollover limit (between 2026-01 and 2026-09) and now reports dates 1024 weeks early.
- rgm3800py (GPLv3, `codl/rgm3800py` branch `py3k`) is used as a protocol reference only.

## Goals / Non-Goals

**Goals:**
- One readable Ruby file of roughly 200 lines, standard library only.
- Conversion logic testable without hardware, against a captured fixture.
- `docs/protocol.md` that records what is known, with its confidence level.

**Non-Goals:**
- Reproducing the official tool's date-revert defect (see Decisions).
- Formats 3/4, erase, G_Mouse, GPX, rollover correction, Windows/macOS support.

## Decisions

### Single file `rgm3800.rb`, usable as library and command
A file guard (`if __FILE__ == $0`) lets tests `require_relative` the file and call the conversion functions directly. Alternative: `bin/` + `lib/` gem layout — rejected as unnecessary for ~200 lines.

### Serial setup via `stty`
Configure the port with `stty -F <dev> 115200 raw -echo` and use `File.open(dev, 'r+b')`. Alternatives: the `serialport`/`uart` gems (adds a dependency) or `Fiddle` termios calls (more code). `stty` is always present on Linux.

### Line framing by checksum, not by newline
Read byte by byte; a line starts at `$` and ends at the first `*HH\r\n` whose HH matches the XOR checksum of the bytes so far. If HH does not match, keep reading (the `*` was payload). Lines that never validate are discarded when the next `$` + 3 uppercase letters sequence starts a new candidate after a CRLF. Alternative: splitting on `\r\n` — breaks on binary payload.

### Chunked reads with retries
Request at most 4800 bytes (`4800 / record_len` records) per `PROY102`, as rgm3800py does. If a chunk does not deliver the expected number of records within the read timeout, re-request that chunk, up to 5 times. Files are written to a temporary name and renamed only after the whole track is received, so a failed track leaves no partial file.

### Coordinates: single-precision degrees, double-precision minutes
Official compatibility requires `deg = f32(f32(rad) * f32(180/π))`, then `min = (deg - floor(deg)) * 60.0` in double, printed `%07.4f`. In Ruby, single precision is emulated with `[x].pack('e').unpack1('e')`; the product of two single-precision values is exact in double, so rounding that product once to single gives the IEEE single-precision result. This is very likely an artifact of the official tool being written in C with `float` variables and a `double` literal `60.0`. Of the candidates tried, it was the only one matching all 2187 reference points; full double precision differs in the last digit for about 55 % of points (≤ 0.2 m, below GPS accuracy). Compatibility is chosen because it allows byte comparison and keeps the archive consistent.

### NMEA field layout for formats 0-2
```
$GPGGA,hhmmss.000,<lat>,<N|S>,<lon>,<E|W>,1,00,,<alt %.1f>,M,0.0,M,,0000*HH
$GPRMC,hhmmss.000,A,<lat>,<N|S>,<lon>,<E|W>,<knots %06.2f>,0.0,<ddmmyy>,,,E*HH
```
knots = km/h / 1.852. Fields absent from the record format (altitude in format 0, speed in formats 0-1) are written as 0 (`0.0`, `000.00`), consistent with the official format-1 logs since 2020 showing `000.00`.

### Date advance rule
Advance the date when the time of day decreases. The official tool advanced the date at UTC midnight in the 2025-12 Ōsumi logs, but in the 2026-09 France track 4 it advanced for one waypoint and then reverted to the start date. The cause could not be determined from the available data. The natural rule is chosen; the France track 4 difference is accepted as an official-tool defect.

### Invalid records
Records whose `valid` byte is not 1 are skipped (rgm3800py does this; none occurred in the fixture). The official tool's handling is unknown.

### Test fixture
Store the raw records captured from the logger for tracks 0-8 together with their start dates as a small binary or JSON file under `test/fixtures/`, plus the 9 official NMEA files. Tests use Ruby's bundled `minitest`. The serial protocol framing is tested with canned byte streams; the full device path is tested manually on hardware.

### CLI
```
rgm3800.rb [-d DEV] info
rgm3800.rb [-d DEV] list
rgm3800.rb [-d DEV] download [-o DIR] [RANGE]
rgm3800.rb [-d DEV] config [--type 0|1|2] [--interval 5..60] [--memory-full overwrite|stop]
```
Parsed with `OptionParser`. Progress goes to stderr; data files only to disk.

## Risks / Trade-offs

- [Formats 0 and 1 not verified byte-for-byte] → Layout inferred from format-2 output and 2020+ official logs; verify by recording a short track in each format and comparing field structure.
- [`PROY104` never tested on hardware; rgm3800py's Python 3 result check is broken] → Read back with `PROY108` after writing; test once manually, restore the original config (format 2, 60 s, stop) afterwards.
- [Interval 1-4 s may work with updated firmware] → Restricted to 5-60 to match the official tool; can be relaxed later.
- [Unknown `PROY108` fields] → Only the documented positions are used; unknown ones are ignored.
- [Unknown root cause of official date revert] → Documented as a known difference; the fixture test encodes it explicitly.
- [Clean-room concern with GPLv3 reference] → Implement from docs/protocol.md and this design, not by translating rgm3800py's code structure.

## Open Questions

- What the `PROY108` fields at positions 1, 2, 4 and 6 mean.
- Whether the official tool writes anything for invalid (`valid != 1`) records.
