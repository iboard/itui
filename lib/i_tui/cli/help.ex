defmodule ITui.CLI.Help do
  @moduledoc """
  What `itui --help` says.

  Most of it is written here, because what iTUI takes on the command line is
  the same however it is configured. The fields of `itui todo add` are not:
  they are the fields of your todo schema, read from the file and listed as
  the options they have become, so a field you add to it is a line here.
  """

  alias ITui.{Band, Data, Schema}
  alias ITui.Schema.{Boolean, Field}

  @doc """
  The whole of it, with the fields of `schema` as the options `todo add` takes.

  `nil` — a schema that could not be read — leaves that section out rather
  than guessing at what is in a file it has not seen.
  """
  @spec text(Schema.t() | nil) :: String.t()
  def text(schema \\ nil) do
    """
    iTUI #{ITui.version()} — a configurable terminal UI for Linux.

      itui [command] [options]

    On the screen

      itui                    open the menu
      itui menu PATH          open the menu at PATH, and do what enter does
      itui todo               open the todo list

    PATH says its way down the menu, as "system/uptime" or as the keys the
    entries carry, "s/u". A space may be written as a dash, and as much of an
    entry's name as says which one it is will do: "menu system/disk". What
    happens at the end of the path is what pressing enter there would do — a
    submenu opens, a command runs, an application starts.

    Without a screen

      itui todo list          print the todos and stop
      itui todo add WORDS     add a todo, the words being what it is called
      itui todo done NUMBER   check todos off by the number in the # column

    itui todo list takes --only and --hide, which name the kinds of todo to
    show and to leave out — as a list separated by commas, or the option
    again:

      #{Enum.join(Band.names(), " · ")}

      itui todo list --hide done
      itui todo list --only overdue,soon
    #{fields(schema)}
    About iTUI itself

      itui --where            say which data directory it is using
      itui --version          say which version this is
      itui --help             this

    #{where()}
    """
  end

  defp fields(nil), do: ""

  defp fields(%Schema{} = schema) do
    case Schema.form_fields(schema) do
      [] ->
        ""

      fields ->
        width = fields |> Enum.map(&String.length(option(&1))) |> Enum.max()

        """

        What a #{String.downcase(schema.label)} is made of, as itui todo add takes it:

        #{Enum.map_join(fields, "\n", &"  #{String.pad_trailing(option(&1), width)}  #{about(&1)}")}
        """
    end
  end

  # A yes/no field is the option on its own; everything else takes a value,
  # and says what kind of one it is.
  defp option(%Field{type: Boolean} = field), do: "--#{name(field)}"
  defp option(%Field{type: :integer} = field), do: "--#{name(field)} NUMBER"
  defp option(%Field{type: ITui.Schema.Date} = field), do: "--#{name(field)} DAY"
  defp option(%Field{type: ITui.Schema.Timestamp} = field), do: "--#{name(field)} WHEN"
  defp option(%Field{} = field), do: "--#{name(field)} TEXT"

  defp name(%Field{name: name}), do: String.replace(name, "_", "-")

  defp about(%Field{} = field) do
    [field.label, said(field.placeholder), required(field)]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" ")
  end

  # What the field says for itself in the form, where it is the grey writing
  # in an empty box: "1 is highest", "2026-12-24, or in 3 days".
  defp said(text) when is_binary(text), do: "— #{text}"
  defp said(_none), do: nil

  defp required(%Field{required: true}), do: "(required)"
  defp required(%Field{}), do: nil

  defp where do
    """
    The menus, the schemas and the records are JSON files in #{Data.dir()},
    written there on first run and yours to edit after that. $ITUI_DATA says
    where they should be instead.\
    """
  end
end
