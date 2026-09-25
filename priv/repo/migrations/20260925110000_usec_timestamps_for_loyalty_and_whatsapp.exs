defmodule Posbd.Repo.Migrations.UsecTimestampsForLoyaltyAndWhatsapp do
  @moduledoc """
  `list_ledger/3` and `list_messages/2` order by `inserted_at desc` to
  show the newest activity first, but two rows created within the same
  second are indistinguishable (and so unpredictably ordered) at
  second-level precision - exactly the problem `Posbd.AuditLogs.AuditLog`
  already solved by using `:utc_datetime_usec`. Applying the same fix
  here for the same reason.
  """
  use Ecto.Migration

  def change do
    alter table(:loyalty_ledger_entries) do
      modify :inserted_at, :utc_datetime_usec, from: :utc_datetime
    end

    alter table(:whatsapp_templates) do
      modify :inserted_at, :utc_datetime_usec, from: :utc_datetime
      modify :updated_at, :utc_datetime_usec, from: :utc_datetime
    end

    alter table(:whatsapp_campaigns) do
      modify :inserted_at, :utc_datetime_usec, from: :utc_datetime
      modify :updated_at, :utc_datetime_usec, from: :utc_datetime
    end

    alter table(:whatsapp_messages) do
      modify :inserted_at, :utc_datetime_usec, from: :utc_datetime
      modify :updated_at, :utc_datetime_usec, from: :utc_datetime
    end
  end
end
