defmodule Posbd.Repo.Migrations.AddProfileFieldsToCustomers do
  use Ecto.Migration

  def change do
    alter table(:customers) do
      add :date_of_birth, :date
      add :preferred_language, :string
      add :customer_type, :string, null: false, default: "individual"

      # Transactional and promotional communication are tracked
      # separately (Phase 2 §31) - a customer can allow their bill on
      # WhatsApp without agreeing to receive marketing.
      add :accepts_transactional_messages, :boolean, null: false, default: true
      add :accepts_promotional_messages, :boolean, null: false, default: false
    end
  end
end
