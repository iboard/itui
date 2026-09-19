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
- Schemas: `ITui.Schema` and `ITui.Schema.Field` read `data/schemas/*.json` and
  cast values into the types they declare.
- A data layer: `ITui.Repo` is one interface with an adapter behind it, and
  `ITui.Repo.Json` keeps each schema's records in the JSON file it names.
- `ITui.Views.Form` — a form over a schema, with per-field validation.
- `ITui.Views.Todo` — the todo list, built out of `data/schemas/todo.json` and
  nothing else.
- Menu entries can open an application (`"view"`) and can ask for a command's
  arguments first (`"form"`), filling the `{{placeholders}}` in its arguments.

### Changed

- Casting and validation are `Ecto.Changeset`s built from the schema files —
  `ITui.Schema.changeset/4`, `cast/3`, `change/4` and `errors/2` — with
  `ITui.Schema.Boolean` as a custom `Ecto.Type` for a yes/no field. There is no
  database and no `ecto_sql`: the changesets end in
  `Ecto.Changeset.apply_action/2` and the JSON file is the store.
- Records are keyed by the field names as atoms, the way a changeset applies
  them; the JSON on disk is unchanged, and a key nobody declared survives being
  read and written back.
