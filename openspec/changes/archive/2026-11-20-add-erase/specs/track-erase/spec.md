# Spec Delta

## Purpose

Lets the user delete all tracks stored on the RGM-3800 logger from Linux, so the memory can be reused, without erasing by accident.

## ADDED Requirements

### Requirement: Erase all tracks
The `erase` command SHALL delete all tracks stored on the logger.

#### Scenario: Logger with tracks
- **WHEN** the logger holds 10 tracks and the user runs `erase --yes`
- **THEN** the logger holds no tracks afterwards and the tool exits with status 0

#### Scenario: Unexpected arguments
- **WHEN** the user runs `erase` with an argument other than `--yes`
- **THEN** the tool prints an error, sends nothing to the logger and exits with a non-zero status

### Requirement: Confirm before erasing
Unless `--yes` is given, the tool SHALL show the number of tracks and waypoints that will be deleted and ask for confirmation on the terminal before erasing. Only an answer of `y` or `yes` (any case) SHALL start the erase.

#### Scenario: User confirms
- **WHEN** the user runs `erase` and answers `y`
- **THEN** the tool erases all tracks

#### Scenario: User declines
- **WHEN** the user runs `erase` and answers anything other than `y` or `yes`, or presses Enter, or ends input
- **THEN** the tool prints that nothing was erased, does not erase, and exits with a non-zero status

#### Scenario: No terminal
- **WHEN** the user runs `erase` without `--yes` and no terminal is available to ask
- **THEN** the tool prints an error saying to use `--yes`, does not erase, and exits with a non-zero status

#### Scenario: Prompt does not mix with output
- **WHEN** the tool asks for confirmation
- **THEN** the question is written to stderr, not stdout

### Requirement: Confirm erase completion
After starting the erase, the tool SHALL wait until the logger has finished, show progress on stderr while waiting, and report success only if the logger then reports no tracks or fewer waypoints in total than before the erase. The logger keeps logging, so it can start a new track right after erasing.

#### Scenario: Erase completes
- **WHEN** the logger accepts the erase and afterwards reports 0 tracks
- **THEN** the tool prints that the logger is empty and exits with status 0

#### Scenario: New track started after erase
- **WHEN** the logger held 2234 waypoints before the erase and afterwards reports 1 track with 1 waypoint
- **THEN** the tool prints that the logger was erased and has started a new track with 1 waypoint, and exits with status 0

#### Scenario: Erase refused
- **WHEN** the logger does not accept the erase request
- **THEN** the tool prints an error and exits with a non-zero status

#### Scenario: Tracks remain
- **WHEN** after the erase has finished the logger reports at least as many waypoints in total as before the erase
- **THEN** the tool prints an error showing the waypoint counts before and after and exits with a non-zero status
