defmodule ITui.MixProject do
  use Mix.Project

  @version "0.1.1"
  @source_url "https://github.com/iboard/itui"

  def project do
    [
      app: :i_tui,
      version: @version,
      elixir: "~> 1.19",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      # Hex
      description: description(),
      package: package(),
      # Docs
      name: "iTUI",
      escript: escript(),
      source_url: @source_url,
      homepage_url: @source_url,
      docs: docs()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {ITui.Application, []}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_env), do: ["lib"]

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:atui, "~> 0.4"},
      {:ecto, "~> 3.13"},
      {:jason, "~> 1.4"},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false}
    ]
  end

  # `app: nil` so that the application is not started before main/1 — asking
  # for the version should not open a terminal UI — `+Bc` so that Ctrl-C
  # reaches the application rather than the BEAM's BREAK menu, and `+fnu` so
  # that a machine with no UTF-8 locale, which is most servers over ssh, still
  # reads and writes filenames as UTF-8.
  defp escript do
    [main_module: ITui.CLI, name: "itui", app: nil, emu_args: "+Bc +fnu"]
  end

  defp description do
    "A configurable terminal UI for Linux: structured menus that run system " <>
      "commands, and JSON-defined forms and data schemas."
  end

  defp package do
    [
      name: "i_tui",
      licenses: ["GPL-3.0-or-later"],
      links: %{"GitHub" => @source_url},
      # data/records is whoever is running iTUI, not the package.
      files: ~w(lib data/menus data/schemas mix.exs README.md LICENSE CHANGELOG.md .formatter.exs)
    ]
  end

  defp docs do
    [
      main: "readme",
      source_ref: "v#{@version}",
      extras: ["README.md", "CHANGELOG.md", "LICENSE"]
    ]
  end
end
