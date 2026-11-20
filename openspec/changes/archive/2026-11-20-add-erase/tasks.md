# Tasks

## 1. Erase command (no hardware)

- [x] 1.1 Add `erase [--yes]` to the CLI and usage text, parsing options before device access; verify with unit tests that an unexpected argument fails without opening the device and that `ruby rgm3800.rb --help` lists `erase`.
- [x] 1.2 Implement the confirmation prompt (stderr, answer from `/dev/tty` or an injected IO, `y`/`yes` any case, decline on anything else or EOF, error suggesting `--yes` when no terminal); verify with unit tests for accept, decline, empty answer, EOF and missing terminal, and that nothing is sent to the logger on decline.
- [x] 1.3 Implement the erase sequence (`PROY109,-1` → `LOG109,1`, wait until progress lines stop with idle and overall timeouts, progress to stderr, read-back with retries, success if no tracks or fewer waypoints than before); verify with `FakeIO` tests for success, new track started after erase, refused (`LOG109,0` and no reply) and tracks remaining.

## 2. Hardware verification

- [x] 2.1 Before erasing, run `download -o <tmpdir>` and verify with `cmp` that 00000-00003 and 00005-00008 match `~/src/gps-logs/2026-09-19-france/` and 00004 shows only the known 87-line difference; keep the downloaded files, including track 9, in `~/src/gps-logs/` and confirm with the user before continuing.
- [x] 2.2 On hardware, send `PROY109,-1` once while logging every received line with timestamps to a scratch file; verify the logger reports 0 tracks afterwards and record the reply, progress lines and duration.
- [x] 2.3 Adjust the progress matching and timeouts to the log from 2.2 if needed, then record a short new track and run `erase` (prompt, then `y`) end to end; verify exit status 0, progress on stderr, and `list` printing nothing or only a newly started track.
- [x] 2.4 After the erase, let the logger record a new track and run `list`, `info` and `download`; verify the new track is numbered 0, record its address and the `PROY108` fields in `docs/protocol.md`.

## 3. Documentation

- [x] 3.1 Move `PROY109` from the unverified list to the commands table in `docs/protocol.md` with the hardware findings (reply, progress lines, duration, state after erase); verify each statement is backed by the 2.2-2.4 logs.
- [x] 3.2 Add `erase` to `README.md` (download first, confirmation, `--yes`); verify the documented commands run as written.
