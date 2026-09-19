import Config

config :i_tui,
  # Where the menu and schema files live, relative to the working directory.
  data_dir: "data",
  start_ui: true

if config_env() == :test do
  # Tests drive views headlessly; starting the real UI would take the terminal.
  config :i_tui, start_ui: false
end
