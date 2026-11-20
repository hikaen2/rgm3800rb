# rgm3800rb

Linux downloader for the RoyalTek RGM-3800 GPS logger. It writes the same NMEA files as the
official (Windows-only) RoyalTek downloader.

## Install

Needs Ruby 3.4 and `stty`; no gems. Copy `rgm3800.rb` anywhere.

The logger appears as `/dev/ttyUSB0`. To access it, your user must be in the `dialout` group:

```
sudo usermod -aG dialout $USER   # then log out and in again
```

## Usage

```
ruby rgm3800.rb [-d DEV] info
ruby rgm3800.rb [-d DEV] list
ruby rgm3800.rb [-d DEV] download [-o DIR] [--fix-rollover] [RANGE]
ruby rgm3800.rb [-d DEV] config [--type 0|1|2] [--interval 5..60] [--memory-full overwrite|stop]
ruby rgm3800.rb [-d DEV] erase [--yes]
```

`-d` selects the serial device (default `/dev/ttyUSB0`). Progress and errors go to stderr.

List the tracks (number, start date, waypoints, record format):

```
$ ruby rgm3800.rb list
    0  2007-02-03     480 waypoints  format 2
    1  2007-02-05      67 waypoints  format 2
```

Download tracks to `NNNNN_YYYYMMDD.nmea` files, overwriting existing ones:

```
ruby rgm3800.rb download -o ~/gps-logs/new     # all tracks
ruby rgm3800.rb download 7-9                    # tracks 7 to 9 into the current directory
```

`RANGE` is `N` (one track), `N-` (N to the last), `N-M`, or `-K` (the last K tracks).

Show the configuration and memory usage:

```
$ ruby rgm3800.rb info
data type    : 2 (time, lat, lon, alt, vel)
interval     : 60 s
memory full  : stop
tracks       : 10
memory used  : 43 of 8192 KB (0.5%)
```

Change the configuration; settings not given stay as they are, and the result is read back:

```
ruby rgm3800.rb config --interval 15
ruby rgm3800.rb config --type 2 --interval 60 --memory-full stop
```

Data types: 0 = time, lat, lon; 1 = + altitude; 2 = + speed. Types 3 and 4 are not supported.

Erase all tracks. This cannot be undone, so download and check the tracks first. The tool asks on
the terminal before erasing; `--yes` skips the question. Erasing takes about 30 seconds:

```
$ ruby rgm3800.rb download -o ~/gps-logs/new
$ ruby rgm3800.rb erase
Erase all 10 tracks (2234 waypoints)? [y/N] y
PSRFTXTSFAM Test Report: Erase now
logger is empty
```

The logger keeps logging while connected. If it has a GPS fix, it may start a new track right after
the erase; `erase` then reports `logger erased; it has started a new track (N waypoints)`.

## Known issue: wrong dates

The logger's GPS week number has rolled over, so it reports dates 1024 weeks (about 19.6 years)
early, e.g. 2007-02-03 for 2026-09-19. By default the files contain the dates as the logger
reports them, like the official tool. For this logger, download with `--fix-rollover` to add the
1024 weeks back:

```
ruby rgm3800.rb download -o ~/gps-logs/new --fix-rollover    # 00000_20260919.nmea, not 00000_20070203.nmea
```

The tool does not detect the rollover itself. Do not use the option for a logger whose dates are
already correct: its dates would jump 19.6 years into the future.

## Development

```
ruby -Itest test/test_rgm3800.rb
```

The reference test compares the conversion of raw records captured from a logger with the official
downloader's files in `test/fixtures/france/`. That fixture holds private GPS tracks and is not in
the repository; the test is skipped without it. See `docs/protocol.md` for the protocol.

## Credits

Protocol knowledge from [rgm3800py](https://github.com/codl/rgm3800py) by Karsten Petersen and
contributors, and the OpenStreetMap wiki page on the RGM-3800. No code was copied.

## License

MIT
