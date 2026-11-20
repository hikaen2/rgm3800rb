# Proposal

## Why

The logger's memory can only be cleared with the official Windows tool. Without an erase, the 8 MB fills up and the logger stops recording (memory-full is set to "stop"). The rgm3800py erase looks broken under Python 3: it compares a bytes reply with a str, so it reports failure without waiting for the erase to finish.

## What Changes

- Add an `erase` command to `rgm3800.rb` that deletes all tracks on the logger.
- Ask for confirmation on the terminal before erasing; `--yes` skips the question.
- Wait for the erase to finish and report success only when the logger reports 0 tracks.
- Record the hardware-verified erase behaviour (`PROY109`) in `docs/protocol.md`, and document `erase` in `README.md`.

Out of scope: erasing single tracks, and any backup or download step inside `erase` (the user downloads first).

## Capabilities

### New Capabilities
- `track-erase`: deleting all tracks stored on the logger safely, with confirmation and completion check.

### Modified Capabilities
- None.

## Impact

- `rgm3800.rb`: new `erase` command and usage text; tests in `test/test_rgm3800.rb`.
- `docs/protocol.md`, `README.md`.
- Destructive on hardware: verification erases the logger, so all tracks must be downloaded and checked first.
