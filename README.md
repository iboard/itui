# iTUI

[![Hex.pm](https://img.shields.io/hexpm/v/i_tui.svg)](https://hex.pm/packages/i_tui)
[![Docs](https://img.shields.io/badge/hex-docs-blue.svg)](https://hexdocs.pm/i_tui)
[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](LICENSE)

A configurable terminal UI for Linux, built with [ATUI](https://hex.pm/packages/atui).

iTUI turns plain text files into a working terminal application: a structured
menu that runs system commands and applications, and simple forms that collect
the parameters those commands need.

## Features

- **Structured menus** — nested entries that call system commands and applications.
- **Simple forms** — collect parameters before a command runs.
- **Declarative schemas** — forms and data structures are defined in
  `data/schemas/*.json`, not in code.
- **Data layer** — a repository abstraction over the JSON-backed schemas,
  moving towards Ecto.

## Status

Early development.

- **Menu MVP** — done: `df`, `uptime` and `free` run from the menu.
- **Forms & data MVP** — next: a small todo application driven by JSON schemas.

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

## Layout

```
data/menus/main.json     the menu, as data
data/schemas/            form and data-structure schemas (next milestone)
lib/i_tui/menu.ex        the menu file, parsed
lib/i_tui/command.ex     a system command, and the running of it
lib/i_tui/views/         the ATUI views: the menu, and the output popup
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
