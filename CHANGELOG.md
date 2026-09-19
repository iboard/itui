# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Initial project scaffolding: mix project, ATUI dependency, ExDoc setup and
  GPL-3.0 licensing.
- The menu MVP: a structured menu read from `data/menus/main.json`, with
  submenus, per-entry keys and a `quit` action.
- `ITui.Command` runs a menu entry's program off the UI's process and captures
  its output, standard error included.
- `ITui.Views.MainMenu` and `ITui.Views.Output` — the menu itself and the
  scrollable popup that shows what a command printed.
- `bin/itui`, which starts the UI with the `+Bc` flag a TUI needs.
