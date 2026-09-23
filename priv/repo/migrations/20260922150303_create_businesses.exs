defmodule Posbd.Repo.Migrations.CreateBusinesses do
  use Ecto.Migration

  def change do
    create table(:businesses, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :slug, :string, null: false
      add :business_type, :string, null: false
      add :country, :string
      add :currency, :string, null: false, default: "INR"
      add :timezone, :string, null: false, default: "Asia/Kolkata"
      add :language, :string, null: false, default: "en"
      add :date_format, :string, null: false, default: "%d-%m-%Y"
      add :settings, :map, null: false, default: %{}
      add :onboarding_completed_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:businesses, [:slug])
  end
end
