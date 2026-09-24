defmodule Posbd.Repo.Migrations.CreateImportLogs do
  use Ecto.Migration

  def change do
    create table(:import_logs, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :business_id, references(:businesses, type: :binary_id, on_delete: :delete_all),
        null: false

      add :performed_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)

      add :import_type, :string, null: false
      add :total_rows, :integer, null: false
      add :success_count, :integer, null: false
      add :error_count, :integer, null: false

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:import_logs, [:business_id, :inserted_at])
  end
end
