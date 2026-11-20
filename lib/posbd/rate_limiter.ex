defmodule Posbd.RateLimiter do
  @moduledoc """
  Small in-memory, fixed-window rate limiter (ETS), used to slow down
  password guessing on the login endpoints.

  Counts are per node and reset on restart - enough to make online
  brute-forcing impractical for a single-instance deployment. If the app
  is ever run on several nodes, move this to a shared store.
  """

  use GenServer

  @table __MODULE__
  @cleanup_interval :timer.minutes(5)

  def start_link(_opts), do: GenServer.start_link(__MODULE__, nil, name: __MODULE__)

  @doc """
  Records one attempt for `key`. Returns `:ok` while at most `limit`
  attempts have been made in the current `window_ms` window, otherwise
  `{:error, retry_after_seconds}`.
  """
  def hit(key, limit, window_ms) do
    now = System.system_time(:millisecond)
    window_start = now - rem(now, window_ms)
    expires_at = window_start + window_ms
    entry_key = {key, window_start}

    count = :ets.update_counter(@table, entry_key, {2, 1}, {entry_key, 0, expires_at})

    if count <= limit,
      do: :ok,
      else: {:error, max(div(expires_at - now, 1000), 1)}
  end

  @doc "Forgets every recorded attempt for `key` (e.g. after a successful login)."
  def reset(key), do: :ets.match_delete(@table, {{key, :_}, :_, :_})

  @impl GenServer
  def init(nil) do
    :ets.new(@table, [:named_table, :public, :set, write_concurrency: true])
    schedule_cleanup()
    {:ok, nil}
  end

  @impl GenServer
  def handle_info(:cleanup, state) do
    now = System.system_time(:millisecond)
    :ets.select_delete(@table, [{{:_, :_, :"$1"}, [{:<, :"$1", now}], [true]}])
    schedule_cleanup()
    {:noreply, state}
  end

  defp schedule_cleanup, do: Process.send_after(self(), :cleanup, @cleanup_interval)
end
