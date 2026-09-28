defmodule Posbd.Marketing.RetentionWorker do
  @moduledoc """
  Runs `Posbd.Marketing.run_daily_retention/1` for every business, once a
  day (Phase 2 §31/§35) - scheduled by `Oban.Plugins.Cron`, never called
  directly from a request.
  """

  use Oban.Worker, queue: :default, max_attempts: 1

  alias Posbd.Businesses.Business
  alias Posbd.Marketing
  alias Posbd.Repo

  @impl Oban.Worker
  def perform(_job) do
    Business |> Repo.all() |> Enum.each(&Marketing.run_daily_retention/1)
    :ok
  end
end
