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
- **Data layer** — one repository interface, with records kept in readable JSON
  files, on its way to Ecto.
- **A todo list** — the forms and the data layer with a screen in front of them.

## Status

Early development.

- **Menu MVP** — done: `df`, `uptime` and `free` run from the menu.
- **Forms & data MVP** — done: schemas in `data/schemas/`, a JSON-backed
  repository, forms over both, and a todo list built out of them.
- **Ecto** — next: the repository rewritten as an Ecto adapter over the same
  schemas and files.

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
  "fields": [
    { "name": "title", "label": "Title", "type": "string", "required": true },
    { "name": "priority", "label": "Priority", "type": "integer", "default": 2 },
    { "name": "done", "label": "Done", "type": "boolean", "default": false }
  ]
}
```

Fields are `string`, `integer` or `boolean`; a boolean is a toggle in the form
rather than a text field. `source` is where `ITui.Repo` keeps the records —
a plain JSON array anyone can open in an editor. A schema with no `source` is
a form and nothing more, which is what a command's arguments need.

Records go through one interface, `ITui.Repo`, with the adapter behind it named
in the configuration:

```elixir
config :i_tui, repo: ITui.Repo.Json
```

### The todo list

`data/schemas/todo.json` and the `Todos` menu entry are the whole application:
`a` adds, `enter` edits, `space` marks one done, `d` then `y` deletes, `r`
re-reads the file. Nothing in `ITui.Views.Todo` mentions a title or a priority.

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
lib/i_tui/schema.ex      a schema file, parsed, and the casting of values
lib/i_tui/repo.ex        where records live, behind one interface
lib/i_tui/views/         the ATUI views: menu, output, form, todo list
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
