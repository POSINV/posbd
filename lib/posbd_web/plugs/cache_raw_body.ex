defmodule PosbdWeb.Plugs.CacheRawBody do
  @moduledoc """
  A `Plug.Parsers` `:body_reader` that stashes the raw request body into
  `conn.assigns.raw_body` before it's consumed by JSON parsing. Needed
  because a webhook signature (Phase 2 §11) is computed over the exact
  raw bytes the provider sent - re-serializing the parsed params would
  not reliably reproduce the same bytes.
  """

  def read_body(conn, opts) do
    {:ok, body, conn} = Plug.Conn.read_body(conn, opts)
    {:ok, body, Plug.Conn.assign(conn, :raw_body, body)}
  end
end
