# Design

## Context

`rgm3800.rb` already has the serial layer (`Device#send_command`, `#read_line`, `#query`, `#info`) and a CLI that parses each command's options before opening the device. What is known about erasing comes only from rgm3800py (unverified):

- `PROY109,-1` → `LOG109,1` starts erasing all memory.
- While erasing, the logger sends about one line per second starting with `PSRFTXTSFAM Test Report:`; rgm3800py treats 2 s without such a line as "done".

Unknown until tested on hardware: the exact progress lines, the duration for this logger's memory, the reply when the logger refuses, and the track numbering, addresses and `PROY108` fields after erasing.

The logger currently holds the 10 tracks used as the private reference fixture (`test/fixtures/france/`, not in git), and the fixture's raw records were captured from them. They must be downloaded and checked before any hardware erase.

## Goals / Non-Goals

**Goals:**
- A small `erase` command (about 30 lines) reusing the existing `Device` methods.
- Unit tests for confirmation and the erase sequence with the existing `FakeIO`.

**Non-Goals:**
- A built-in download-before-erase step or backup check.
- Partial erase; the `-1` argument is the only form used.

## Decisions

### Command sequence
1. `info` and `tracks` to get the track and waypoint counts for the prompt.
2. Ask for confirmation (unless `--yes`).
3. `query('PROY109,-1', 'LOG109')`; anything other than `[1]` is "refused".
4. Read lines until none arrives for an idle timeout; print progress lines to stderr.
5. Read the tracks again; success if there are none, or if their total waypoint count is lower than before the erase.

Alternative: poll `PROY108` during the erase instead of waiting for silence — rejected until hardware shows the logger answers queries while erasing.

### Waiting for completion
Read with `read_line` and count time since the last progress line; stop after 5 s without one, with an overall limit of 10 minutes so a misbehaving logger cannot hang the tool. 5 s instead of rgm3800py's 2 s gives margin over the existing 1 s read timeout. Both values are adjusted after the hardware test if needed. Progress lines are matched by the `PSRFTXT` prefix rather than the full text, until the exact text is seen.

### Success check
Verified on hardware: the logger keeps logging after the erase and started a new track (number 0, address 0, 1 waypoint) about 16 s after it went silent, so "0 tracks" alone would report a working erase as failed. There is no known command to pause logging. The logger only ever adds waypoints and the erase is all-or-nothing, so a lower total than before proves the erase happened. The read-back is retried a few times, as with `PROY104`. Limitation: if the logger was empty and starts a track during the erase, the check reports failure; this is harmless and not handled.

### Confirmation
Read the answer from `/dev/tty`, not stdin, so `erase` cannot be confirmed by accident through piped input; if `/dev/tty` cannot be opened, fail and suggest `--yes`. The prompt goes to stderr, e.g. `Erase all 10 tracks (2222 waypoints) on /dev/ttyUSB0? [y/N] `. Alternative: `$stdin` — simpler, but a stray pipe could confirm the erase. For tests, the prompt reads from an IO argument so a `StringIO` can stand in for the terminal.

### Option parsing
`--yes` (and `-y`) parsed with `OptionParser` before the device is opened, like `config`; extra arguments are rejected before any device access.

## Risks / Trade-offs

- [Irreversible data loss on hardware verification] → Task order requires downloading all 10 tracks and comparing them with the official files before the erase task; the fixture already holds the raw records of tracks 0-8.
- [Unknown progress line format or duration] → First hardware run logs every line received during the erase to a scratch file; the matching rule and timeouts are fixed from that log.
- [Logger may not answer `PROY108` immediately after erasing (as with `PROY104`)] → Retry the read-back for a few seconds before declaring failure.
- [Logger starts a new track right after erasing] → Success check compares total waypoints with the count before the erase (see Success check).
- [rgm3800py erase is broken under Python 3] → Implementation follows this design and the hardware log, not rgm3800py's code.
