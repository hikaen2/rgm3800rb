# RGM-3800 protocol

What `rgm3800.rb` knows about the RoyalTek RGM-3800 logger. Every fact is marked:

- **[HW]** verified on hardware (firmware `RoyalTek Ver 1.5.0.245 GSW3LP`, 8192 KB)
- **[OFF]** verified against the official RoyalTek downloader's output (a private fixture of 9 tracks, 2187 waypoints, not in the repository)
- **[EXT]** from other sources only: [rgm3800py](https://github.com/codl/rgm3800py) and the OpenStreetMap wiki

## Physical layer

- PL2303 USB serial adapter, USB ID `067b:2303`, appears as `/dev/ttyUSB0`, group `dialout`. [HW]
- 115200 baud, 8N1, raw mode (`stty -F <dev> 115200 cs8 -parenb -cstopb raw -echo`). [HW]

## Line format

- Every line is `$<body>*<HH>\r\n`; `HH` is the XOR of all body bytes, two uppercase hex digits. [HW]
- Commands are `PROYnnn[,args]`, replies `LOGnnn[,fields]`. Fields are decimal ASCII. [HW]
- `LOG102` lines carry binary payload, so `*`, `\r\n` and `$` can occur inside a line. Lines are
  therefore framed by checksum: a line ends at the first `*HH\r\n` whose `HH` matches the XOR of
  the bytes so far. A candidate that never validates is dropped when `\r\n$` followed by three
  uppercase letters starts a new line. [HW] (framing approach tested with canned streams)
- Other lines (e.g. GPS sentences) may appear and are ignored. [EXT]

## Commands

| Command | Reply | Status |
|---|---|---|
| `PROY108` | `LOG108,<format>,?,?,<memfull>,?,<interval>,?,<tracks>,<wps in last track>` | [HW] |
| `PROY100` | `LOG100,<total bytes>,<sector size>,<sectors>,?` | [HW] |
| `PROY101,<n>` | `LOG101,<yyyymmdd>,<format>,<waypoints>,<address>` | [HW] |
| `PROY102,<address>,<format>,<count>` | `LOG102,...` data lines, see below | [HW] |
| `PROY104,0,<interval>,<format>,<memfull>` | `LOG104,1` on success, `LOG104,0` on failure | [HW] |
| `PROY109,-1` | `LOG109,1`, then progress lines until the memory is erased | [HW] |

- `PROY108` example: `LOG108,2,-1,-1,1,0,60,192,10,37`. `memfull` 0 = overwrite oldest sector,
  1 = stop logging [HW for 1, EXT for 0]. Fields 1, 2, 4 and 6 are unknown; field 6 was seen as 0
  and 192. [HW]
- `PROY100` example: `LOG100,8388608,65536,128,0`. The last field is unknown. [HW]
- `PROY101` dates suffer from the GPS week-number rollover: a track recorded on 2026-09-19 is
  reported as 2007-02-03 (1024 weeks early). `download` keeps these dates unless `--fix-rollover`
  is given, which adds exactly 7168 days to each track's start date. [HW]
- `PROY102` only works for addresses inside the track last selected with `PROY101`; otherwise the
  reply is `LOG102,0`. So `PROY101,<n>` must be sent before reading track `n`. [HW]
- `PROY102` reply: one line per up to 240 payload bytes:
  `LOG102,<u16 LE line index><u8 payload length><records...>`. A request for 240 format-2 records
  (4800 bytes) returns 20 lines of 12 records. [HW] The tool requests at most 4800 bytes at once and
  retries a request up to 5 times. [EXT]
- `PROY104`: the change is acknowledged at once but `PROY108` shows the new value only after
  about one second. The tool sends `0` as the first argument as rgm3800py does; its meaning is
  unknown. Verified for changing the interval; format and memory-full use the same command. [HW]
- `PROY109,-1` erases all tracks. The logger replies `LOG109,1` at once, then sends
  `PSRFTXTSFAM Test Report: Erase now` about once per second (33-34 lines, about 33 s for the
  8192 KB memory) and then goes silent. Right afterwards `PROY108` reports 0 tracks:
  `LOG108,2,-1,-1,1,0,60,192,0,0`. The refusal reply (presumably `LOG109,0`) was not seen. [HW]
- Logging is not paused by the erase and no command to pause it is known. If the logger has a GPS
  fix it starts a new track soon after the erase (seen after 16 s and after about 3 minutes):
  track 0 at address 0, e.g. `LOG101,20070406,2,1,0`, `LOG108,2,-1,-1,1,0,60,192,1,1`. [HW]
  `rgm3800.rb erase` therefore counts the erase as done when the logger reports no tracks or
  fewer waypoints than before.

Seen in rgm3800py, not used and unverified: [EXT]

- `PROY003` → `LOG003,<yyyymmdd>,<hhmmss>` current UTC time (`LOG002` without a GPS fix).
- `PROY005` → several `PSRFTXT` lines including the firmware version.
- `PROY006` → `LOG006,...` time range of the stored waypoints.
- `PROY103,0,<0|1>` → G_Mouse mode.

## Record format

Fixed length, little-endian, no date. [HW]

| Offset | Type | Field | Formats |
|---|---|---|---|
| 0 | u8 | valid (1 = valid) | 0-2 |
| 1 | u8 | hour (UTC) | 0-2 |
| 2 | u8 | minute | 0-2 |
| 3 | u8 | second | 0-2 |
| 4 | f32 | latitude, radians | 0-2 |
| 8 | f32 | longitude, radians | 0-2 |
| 12 | f32 | altitude, metres | 1-2 |
| 16 | f32 | speed, km/h | 2 |

- Record length: format 0 = 12, 1 = 16, 2 = 20 bytes. [HW for 2, EXT for 0 and 1]
- Formats 3 (24 bytes) and 4 (60 bytes) add distance and satellite data; not supported. [EXT]
- Records whose valid byte is not 1 are skipped. [EXT] None occurred in the fixture; the official
  tool's handling is unknown.
- Sample (format 2): `01 07 12 24 f6 6d 5a 3f 69 d7 46 3d 6e 50 3d c2 2d 4f 8f 42` =
  07:18:36, 0.8532404 rad, 0.0485453 rad, -47.3285 m, 71.6546 km/h. [HW]

## NMEA conversion

Each waypoint becomes two lines, CRLF-terminated, checksum as above. [OFF]

```
$GPGGA,hhmmss.000,<lat>,<N|S>,<lon>,<E|W>,1,00,,<alt %.1f>,M,0.0,M,,0000*HH
$GPRMC,hhmmss.000,A,<lat>,<N|S>,<lon>,<E|W>,<knots %06.2f>,0.0,<ddmmyy>,,,E*HH
```

- `<lat>` is `ddmm.mmmm` (`%02d%07.4f`), `<lon>` is `dddmm.mmmm` (`%03d%07.4f`), of the absolute
  value; the sign selects `S`/`W`. [OFF]
- Degrees are computed in single precision: `deg = f32(abs(rad) * f32(180/π))`; minutes in double
  precision: `(deg - floor(deg)) * 60.0`. This matches all 2187 fixture points digit for digit;
  plain double precision differs in the last digit for about 55 % of them. [OFF]
- knots = km/h / 1.852. [OFF]
- Formats 0 and 1 write missing altitude as `0.0` and missing speed as `000.00`. [EXT; consistent
  with official format-1 logs]
- File name: `NNNNN_YYYYMMDD.nmea`, track number and the track start date from `PROY101`. [OFF]
- Dates: the track start date, advanced by one day whenever the time of day decreases. [OFF] The
  official tool did this in other logs, but in fixture track 4 it advanced for the waypoint at
  00:00:22 and then reverted to the start date for the remaining 87 waypoints. `rgm3800.rb` keeps
  the advanced date there; this is the only difference from the official output.
