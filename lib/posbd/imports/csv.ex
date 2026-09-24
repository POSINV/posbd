NimbleCSV.define(Posbd.Imports.CSVParser, separator: ",", escape: "\"")

defmodule Posbd.Imports.CSV do
  @moduledoc "Parses an uploaded CSV into row maps keyed by normalized header name."

  alias Posbd.Imports.CSVParser

  @doc """
  Returns `{:ok, [%{row_number: n, fields: %{"name" => ..., ...}}]}` -
  `row_number` is 1-based over the data rows (excluding the header), so
  it matches what a user sees when they count rows in a spreadsheet.
  """
  def parse(binary) do
    case CSVParser.parse_string(binary, skip_headers: false) do
      [] ->
        {:error, %{message: "The file is empty"}}

      [header | data_rows] ->
        keys = Enum.map(header, &normalize_header/1)

        rows =
          data_rows
          |> Enum.with_index(1)
          |> Enum.map(fn {row, row_number} ->
            fields = keys |> Enum.zip(pad(row, length(keys))) |> Map.new()
            %{row_number: row_number, fields: fields}
          end)

        {:ok, rows}
    end
  rescue
    _ in NimbleCSV.ParseError -> {:error, %{message: "Could not parse this file as CSV"}}
  end

  defp normalize_header(h) do
    h |> String.trim() |> String.downcase() |> String.replace(~r/[\s-]+/, "_")
  end

  # A short trailing row (missing trailing commas) shouldn't crash the zip.
  defp pad(row, len) when length(row) >= len, do: row
  defp pad(row, len), do: row ++ List.duplicate("", len - length(row))

  @doc "Builds a downloadable CSV string from a list of rows (first row is the header)."
  def to_csv(rows) do
    rows |> CSVParser.dump_to_iodata() |> IO.iodata_to_binary()
  end
end
