defmodule PosbdWeb.Plugs.CacheRawBody do
  @moduledoc """
  A `Plug.Parsers` `:body_reader` that stashes the raw request body into
  `conn.assigns.raw_body` before it's consumed by JSON parsing. Needed
  because a webhook signature (Phase 2 §11) is computed over the exact
  raw bytes the provider sent - re-serializing the parsed params would
  not reliably reproduce the same bytes.
  """

  def read_body(conn, opts) do
    case Plug.Conn.read_body(conn, opts) do
      {:ok, body, conn} -> {:ok, body, maybe_cache(conn, body)}
      other -> other
    end
  end

  # Only webhook routes need the raw bytes. Keeping every request's raw
  # body (e.g. login passwords) around in assigns would just widen what
  # can end up in crash reports or debug output.
  defp maybe_cache(%Plug.Conn{path_info: ["api", "v1", "webhooks" | _]} = conn, body),
    do: Plug.Conn.assign(conn, :raw_body, body)

  defp maybe_cache(conn, _body), do: conn
end
