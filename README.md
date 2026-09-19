# iTUI

[![Hex.pm](https://img.shields.io/hexpm/v/i_tui.svg)](https://hex.pm/packages/i_tui)
[![Docs](https://img.shields.io/badge/hex-docs-blue.svg)](https://hexdocs.pm/i_tui)
[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](LICENSE)

A configurable terminal UI for Linux, built with [ATUI](https://hex.pm/packages/atui).

iTUI turns plain text files into a working terminal application: a structured
menu that runs system commands and applications, and simple forms that collect
the parameters those commands need.

## Features

- **Structured menus** — nested entries that call system commands and
  applications, described in `data/menus/main.json`.
- **Simple forms** — a menu entry can ask for a command's arguments before it
  runs, and fill its `{{placeholders}}` with the answers.
- **Declarative schemas** — forms and data structures are defined in
  `data/schemas/*.json`, not in code.
- **Data layer** — Ecto changesets over the JSON-declared schemas, and one
  repository interface with the records kept in readable JSON files.
- **A todo list** — the forms and the data layer with a screen in front of them.

## Status

Early development.

- **Menu MVP** — done: `df`, `uptime` and `free` run from the menu.
- **Forms & data MVP** — done: schemas in `data/schemas/`, a JSON-backed
  repository, forms over both, and a todo list built out of them.
- **Ecto** — done: casting and validation are `Ecto.Changeset`s built from the
  schema files.

## Installation

Requires Elixir ~> 1.19 and OTP 28.

```console
git clone https://github.com/iboard/itui.git
cd itui
mix deps.get
```

## Running it

```console
bin/itui
```

That is `elixir --erl "+Bc" -S mix run --no-halt`: the `+Bc` flag is what makes
Ctrl-C reach the application instead of opening the BEAM's BREAK menu. Plain
`mix run --no-halt` works too, but the VM keeps Ctrl-C for itself.

### Keys

| | |
| --- | --- |
| `↑` `↓`, `k` `j` | move through the entries |
| `enter`, `→` | open a submenu, or run the command |
| an entry's own key | the same, without moving first |
| `esc`, `←`, `backspace` | back out of a submenu |
| `?` | what this is, and what it is built on |
| `q` | quit |

While a command's output is open, the arrows and `page up`/`page down` scroll
it and `esc` closes it.

## The menu file

The menu is data, not code: `data/menus/main.json` describes it, and iTUI reads
it at startup. An entry carries exactly one of `items` (a submenu), `command`
(a program and its `args`) or `action` (`"quit"` is the only one so far).

```json
{
  "title": "iTUI",
  "items": [
    {
      "key": "s",
      "label": "System",
      "items": [
        {
          "key": "d",
          "label": "Disk free",
          "description": "Free space per mounted filesystem",
          "command": "df",
          "args": ["-h"]
        }
      ]
    },
    { "key": "q", "label": "Quit", "action": "quit" }
  ]
}
```

A command is never handed to a shell: the program is resolved with
`System.find_executable/1` and its arguments are passed straight to it, so
nothing in a menu file is expanded, globbed or chained. It runs off the UI's
process, so the interface keeps drawing — and stays quittable — while it works.

A menu file that does not parse is reported on screen rather than stopping the
application: a terminal that says what is wrong with the file is more use than
one that refuses to open.

## Schemas, forms and data

A schema file says what a thing holds. The same declaration draws the form and
stores the record, so a field added to the file shows up in both:

```json
{
  "name": "todo",
  "label": "Todo",
  "title": "Todos",
  "source": "data/records/todos.json",
  "columns": ["id", "priority", "done", "inserted_at", "done_at", "title"],
  "sort": "id",
  "fields": [
    { "name": "title", "label": "Title", "type": "string", "required": true },
    { "name": "description", "label": "Description" },
    { "name": "url", "label": "URL" },
    { "name": "priority", "label": "Priority", "type": "integer", "default": 2 },
    { "name": "done", "label": "Done", "type": "boolean", "default": false },
    { "name": "id", "label": "#", "type": "integer", "form": false },
    { "name": "inserted_at", "label": "Created", "type": "datetime", "form": false },
    { "name": "done_at", "label": "Checked off", "type": "datetime", "form": false }
  ]
}
```

Fields are `string`, `integer`, `boolean` or `datetime`. A boolean is a toggle
in the form and a `[x]` in the list; a datetime is stored as ISO 8601 in UTC —
which sorts chronologically — and shown in local time.

`columns` says which fields the table draws and in what order: a table reads in
a different order from the form that fills it, and a field left out of them is
shown beside the list instead, which is where a description and a link belong.
Leave `columns` out and every field gets one, in the order they are declared.
`"form": false` on a field means it is never asked for, which is what a serial
number and a timestamp the application writes itself need. `sort` names the
column the list starts sorted by.

The serial number is the `id` the repository gives a record: it counts up, and
it is not handed out twice even when a record is deleted.

`source` is where `ITui.Repo` keeps the records — a plain JSON array anyone can
open in an editor. A schema with no `source` is a form and nothing more, which
is what a command's arguments need.

Records go through one interface, `ITui.Repo`, with the adapter behind it named
in the configuration:

```elixir
config :i_tui, repo: ITui.Repo.Json
```

### Ecto without a database

The fields are only known when the file is read, so there is no module to
`use Ecto.Schema` in — and no need for one. `Ecto.Changeset` takes a
`{data, types}` pair as readily as it takes a struct, so `ITui.Schema` builds
the types out of the fields it parsed and hands Ecto the usual job:

```elixir
{:ok, schema} = ITui.Schema.load("todo")

ITui.Schema.changeset(schema, %{}, %{"title" => "Write it", "priority" => "1"})
#=> #Ecto.Changeset<changes: %{title: "Write it", priority: 1}, valid?: true>

ITui.Schema.cast(schema, %{"priority" => "high"})
#=> {:error, #Ecto.Changeset<...>}
```

`ITui.Schema.errors/2` turns a changeset into what the form shows under the
rows. A yes/no field is a custom `Ecto.Type` (`ITui.Schema.Boolean`) so that
`yes`, `no`, `y` and `n` mean what a person typing them means.

There is no repository behind the changesets: casting ends in
`Ecto.Changeset.apply_action/2`, and the JSON file is the database. `ecto_sql`
is not a dependency, and nothing here talks to one.

### The todo list

`data/schemas/todo.json` and the `Todos` menu entry are the whole application:
`a` adds, `enter` edits, `space` marks one done, `d` then `y` deletes, `R`
re-reads the file. Nothing in `ITui.Views.Todo` mentions a title or a priority.

The list is a table of the columns the schema declares. `←`/`→` move the sort
from one column to the next and `r` turns it the other way up. A column too
wide for the terminal is dropped rather than half-drawn — never the one that
stretches — so the sort is named in the summary line as well as marked in the
header.

```
 4 todos, 2 done                                              sorted by # ▲
   # ▲ │ Priority   │ Done   │ Created          │ Checked off      │ Title
 ──────┼────────────┼────────┼──────────────────┼──────────────────┼──────────────
 ▸   2 │          1 │ [ ]    │ 2026-09-19 21:26 │                  │ scheissn geh
     3 │          5 │ [x]    │ 2026-09-19 21:28 │ 2026-09-19 22:00 │ publish iTUI
 Description: the last one before the release
```

Ticking one off writes the moment it happened into `done_at`, and unticking it
takes the date away again.

### Forms for a command

A command entry that names a `"form"` asks for its arguments first, and fills
the `{{placeholders}}` with what the form collected:

```json
{
  "key": "p",
  "label": "Ping a host",
  "command": "ping",
  "args": ["-c", "{{count}}", "{{host}}"],
  "form": "ping"
}
```

## Layout

```
data/menus/main.json     the menu, as data
data/schemas/*.json      forms and data structures, as data
data/records/*.json      the records themselves
lib/i_tui/menu.ex        the menu file, parsed
lib/i_tui/command.ex     a system command, and the running of it
lib/i_tui/schema.ex      a schema file, parsed, and its Ecto changesets
lib/i_tui/repo.ex        where records live, behind one interface
lib/i_tui/views/         the ATUI views: menu, output, form, todo list, about
```

## Documentation

Generate the docs locally with:

```console
mix docs
```

Published documentation lives at <https://hexdocs.pm/i_tui>.

## Development

```console
mix deps.get      # fetch dependencies
mix test          # run the test suite
mix format        # format the code
mix docs          # build the documentation
```

## License

Copyright (C) 2026 Andreas Altendorfer

This program is free software: you can redistribute it and/or modify it under
the terms of the GNU General Public License as published by the Free Software
Foundation, either version 3 of the License, or (at your option) any later
version. See [LICENSE](LICENSE) for the full text.
