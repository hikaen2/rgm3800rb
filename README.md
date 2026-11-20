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
ruby rgm3800.rb [-d DEV] download [-o DIR] [RANGE]
ruby rgm3800.rb [-d DEV] config [--type 0|1|2] [--interval 5..60] [--memory-full overwrite|stop]
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

## Known issue: wrong dates

The logger's GPS week number has rolled over, so it reports dates 1024 weeks (about 19.6 years)
early, e.g. 2007-02-03 for 2026-09-19. The files contain the dates as the logger reports them,
like the official tool. Correct them in a separate step.

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
