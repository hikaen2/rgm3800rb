# logger-config Specification

## Purpose

Lets the user read the RGM-3800 logger's status and change its logging configuration from Linux, covering the settings offered by the official RoyalTek downloader.

## Requirements

### Requirement: Show logger status
The `info` command SHALL print the logger's current data type (record format), logging interval in seconds, memory-full behaviour, number of tracks and memory usage.

#### Scenario: Show configuration
- **WHEN** the logger is set to format 2, 60 seconds, stop when full, and the user runs `info`
- **THEN** the output shows data type 2 (time, lat, lon, alt, vel), interval 60 s, memory full "stop", and the track count

### Requirement: Change logging configuration
The `config` command SHALL change any combination of data type (`--type 0|1|2`), interval (`--interval 5..60`) and memory-full behaviour (`--memory-full overwrite|stop`). Settings not given SHALL keep their current values on the logger.

#### Scenario: Change interval only
- **WHEN** the logger is set to format 2, 60 s, stop, and the user runs `config --interval 15`
- **THEN** the logger is set to format 2, 15 s, stop

#### Scenario: Change several settings
- **WHEN** the user runs `config --type 1 --memory-full overwrite`
- **THEN** the logger's data type becomes 1 and memory-full becomes overwrite, and the interval is unchanged

#### Scenario: No settings given
- **WHEN** the user runs `config` without options
- **THEN** the tool prints usage, sends nothing to the logger and exits with a non-zero status

### Requirement: Validate configuration values
The tool SHALL reject a data type other than 0, 1 or 2, an interval outside 5 to 60 seconds, and a memory-full value other than `overwrite` or `stop`, before sending anything to the logger.

#### Scenario: Interval out of range
- **WHEN** the user runs `config --interval 1`
- **THEN** the tool prints an error stating the allowed range 5-60, sends nothing and exits with a non-zero status

#### Scenario: Unsupported data type
- **WHEN** the user runs `config --type 4`
- **THEN** the tool prints an error stating that only types 0-2 are supported, sends nothing and exits with a non-zero status

### Requirement: Confirm configuration change
After writing the configuration, the tool SHALL read the configuration back from the logger and report success only if it matches the requested values.

#### Scenario: Change accepted
- **WHEN** the logger acknowledges the change and the read-back values match
- **THEN** the tool prints the new configuration and exits with status 0

#### Scenario: Change rejected
- **WHEN** the logger reports failure or the read-back values differ
- **THEN** the tool prints an error showing the requested and actual values and exits with a non-zero status
