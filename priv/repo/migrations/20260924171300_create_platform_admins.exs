defmodule Posbd.Repo.Migrations.CreatePlatformAdmins do
  use Ecto.Migration

  def change do
    create table(:platform_admins, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :email, :string, null: false
      add :hashed_password, :string, null: false
      add :full_name, :string, null: false
      # "admin" (full access) or "support" (read-only per AGENTS.md Phase 2
      # §45 - avoid giving support staff unrestricted access).
      add :role, :string, null: false, default: "support"

      timestamps(type: :utc_datetime)
    end

    create unique_index(:platform_admins, [:email])

    create table(:platform_admin_tokens, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :token, :binary, null: false
      add :context, :string, null: false

      add :platform_admin_id,
          references(:platform_admins, type: :binary_id, on_delete: :delete_all),
          null: false

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create unique_index(:platform_admin_tokens, [:context, :token])
  end
end
