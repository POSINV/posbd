defmodule Posbd.Repo.Migrations.CreateWhatsapp do
  use Ecto.Migration

  def change do
    create table(:whatsapp_templates, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :business_id, references(:businesses, type: :binary_id, on_delete: :delete_all),
        null: false

      add :name, :string, null: false
      add :purpose, :string, null: false, default: "custom"
      add :category, :string, null: false, default: "utility"
      add :language, :string, null: false, default: "en"
      add :body, :text, null: false
      add :variable_count, :integer, null: false, default: 0
      add :status, :string, null: false, default: "pending_approval"
      add :provider_template_name, :string
      add :rejected_reason, :string
      add :reviewed_by_id, references(:platform_admins, type: :binary_id, on_delete: :nilify_all)
      add :reviewed_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index(:whatsapp_templates, [:business_id])
    create index(:whatsapp_templates, [:status])

    create table(:whatsapp_campaigns, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :business_id, references(:businesses, type: :binary_id, on_delete: :delete_all),
        null: false

      add :template_id, references(:whatsapp_templates, type: :binary_id, on_delete: :nilify_all)
      add :name, :string, null: false
      add :audience_segment, :string, null: false, default: "all"
      add :status, :string, null: false, default: "draft"
      add :scheduled_at, :utc_datetime
      add :created_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create index(:whatsapp_campaigns, [:business_id, :inserted_at])

    create table(:whatsapp_messages, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :business_id, references(:businesses, type: :binary_id, on_delete: :delete_all),
        null: false

      add :customer_id, references(:customers, type: :binary_id, on_delete: :delete_all),
        null: false

      add :template_id, references(:whatsapp_templates, type: :binary_id, on_delete: :nilify_all)
      add :campaign_id, references(:whatsapp_campaigns, type: :binary_id, on_delete: :nilify_all)
      add :kind, :string, null: false
      add :phone, :string, null: false
      add :body, :text, null: false
      add :status, :string, null: false, default: "queued"
      add :provider_message_id, :string
      add :error_message, :string
      add :sent_at, :utc_datetime
      add :delivered_at, :utc_datetime
      add :read_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index(:whatsapp_messages, [:business_id, :inserted_at])
    create index(:whatsapp_messages, [:customer_id])
    create index(:whatsapp_messages, [:campaign_id])
    create unique_index(:whatsapp_messages, [:provider_message_id])
  end
end
