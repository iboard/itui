# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.2] - 2026-09-20

### Fixed

- Standard output is set to Unicode before anything is printed, so a machine
  with no UTF-8 locale — most servers over ssh, and every one of them under
  cron — draws the table rules and the box around the menu rather than
  `\x{2500}`. The escript carries `+fnu` beside `+Bc` for the same reason,
  and the VM stops warning that it expected a UTF-8 locale.

### Changed

- iTUI asks for Elixir ~> 1.18 rather than ~> 1.19, and for Atui ~> 0.4.1,
  which does the same. An escript carries the Elixir it was built with, so
  the Elixir that builds it decides which Erlang/OTP the result will load on:
  built with 1.18 it runs on OTP 25 and upwards, which is a production
  machine nobody has upgraded lately. Nothing here needed the newer Elixir.
  Tested on 1.18.5/OTP 25 as well as on 1.19.5/OTP 28.

## [0.1.1] - 2026-09-20

### Added

- Arguments for `itui`, so that it can be asked for one thing rather than
  opened: `itui menu system/uptime` goes straight to a menu entry and does
  what enter would do there, `itui todo` opens the todo list, and `itui todo
  add`, `itui todo done` and `itui todo list` do their work without a screen
  at all. `itui --help` says the whole of it, with the options `todo add`
  takes read from the todo schema itself.
- `ITui.Menu.resolve/2` — a path of names walked into the menu, matched
  against an entry's key, its label, or as much of one as says which it is.
- `ITui.Views.MainMenu` can be mounted at a menu entry (`:open`) or over an
  application (`:open_view`), which is how the command line says where to go.
- `ITui.Band` — what kind of todo a todo is, now that the list, the filter and
  the command line all reckon by it.

## [0.1.0] - 2026-09-19

### Added

- `itui` as an escript: `mix escript.install hex i_tui`, with `--where`,
  `--version` and `--help`, and the `+Bc` flag a TUI needs baked in.
- `ITui.Data` — the menus and schemas iTUI ships with are read into the code at
  compile time and written into `$ITUI_DATA`, `~/.itui` or `~/.config/itui` on
  first run, and never over a file that is already there. A schema's `source`
  is a path inside that directory.

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
- `ITui.Views.About` — `?` on the menu says what iTUI is and what it is built
  on, reading the version and the description from the application spec.

- A `datetime` field type (`ITui.Schema.Timestamp`), stored as ISO 8601 in UTC
  and shown in local time.
- A schema says which of its fields are columns and in what order
  (`"columns"`), and which column its list starts sorted by (`"sort"`); a field
  left out of the columns is shown beside the list, and `"form": false` on a
  field means it is never asked for.
- `ITui.TextArea` — a field of several lines in the shape of `Atui.TextInput`,
  which a schema asks for with `"lines"`. Inside one, `enter` starts a new line
  and `ctrl-d` saves the form; what it holds is shown in one line wherever
  there is only one.
- A field can carry a `"short"` label for a column too narrow for its own.
- A schema names the column that takes the width the others leave over
  (`"stretch"`), and the todo list gives it to `description`.
- A schema says which fields are shown beside the list (`"detail"`), column or
  not, each on a row of its own.
- A date in a column is the day it fell on, without the time.
- A `date` field type (`ITui.Schema.Date`) — a day in a calendar rather than a
  moment in time — and a `due` field on a todo, asked for in the form and
  given a column between Created and Checked.
- A date field takes a day said as how far off it is — `in 3 days`, `3d`,
  `3weeks`, `1 month`, `tomorrow` — and stores the day it comes to.
- `t` switches the todo list between dates as they are written and as they
  stand from today (`+3 days`, `-2 weeks`), and `f` opens `ITui.Views.Filter`,
  which hides and shows the colour bands and says how many there are of each.
  The list is filtered as the boxes are ticked, not when the popup closes.
- Today's date heads the todo list, and is the day its colours are reckoned
  from.
- Rows are coloured by how near their due date is: green once done, red past
  it, yellow within two days, orange within the rest of the calendar week,
  white for the rest of the month, light blue beyond it.
- The todo list is a sortable, ruled table — `←`/`→` move the sort from column
  to column, `r` turns it the other way up, `R` re-reads the file — with a
  serial number, `description` and `url` fields, a `Created` column and a
  `Checked off` column that is written when a todo is ticked and cleared when
  it is unticked.

### Changed

- Casting and validation are `Ecto.Changeset`s built from the schema files —
  `ITui.Schema.changeset/4`, `cast/3`, `change/4` and `errors/2` — with
  `ITui.Schema.Boolean` as a custom `Ecto.Type` for a yes/no field. There is no
  database and no `ecto_sql`: the changesets end in
  `Ecto.Changeset.apply_action/2` and the JSON file is the store.
- Records are keyed by the field names as atoms, the way a changeset applies
  them; the JSON on disk is unchanged, and a key nobody declared survives being
  read and written back.
