defmodule Posbd.Repo.Migrations.UseMicrosecondPrecisionForOrderingTimestamps do
  use Ecto.Migration

  @moduledoc """
  Second-precision timestamps tie when several movements/invoices/payments
  are created within the same second - plausible in a fast-billing POS -
  making "newest first" ordering ambiguous. Microsecond precision fixes
  that without needing a synthetic sequence column.
  """

  def change do
    alter table(:inventory_transactions) do
      modify :occurred_at, :utc_datetime_usec, from: :utc_datetime
    end

    alter table(:invoices) do
      modify :issued_at, :utc_datetime_usec, from: :utc_datetime
    end

    alter table(:payments) do
      modify :received_at, :utc_datetime_usec, from: :utc_datetime
    end
  end
end
