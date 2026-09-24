defmodule Posbd.Billing.Invoice do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @statuses ~w(completed cancelled)
  @payment_statuses ~w(unpaid partial paid)
  @sources ~w(pos migrated)

  schema "invoices" do
    field :invoice_number, :string
    field :status, :string, default: "completed"
    field :payment_status, :string, default: "unpaid"
    # "migrated" marks a historical invoice brought in via bulk import
    # (AGENTS.md §14/§27) - it was never charged against live inventory,
    # so cancelling one must never restore stock (see Billing.cancel_invoice).
    field :source, :string, default: "pos"
    field :currency, :string

    field :subtotal, :decimal
    field :discount_amount, :decimal, default: Decimal.new(0)
    field :tax_amount, :decimal
    field :total_amount, :decimal
    field :amount_paid, :decimal, default: Decimal.new(0)

    field :idempotency_key, :string
    field :notes, :string
    field :issued_at, :utc_datetime_usec

    belongs_to :business, Posbd.Businesses.Business
    belongs_to :customer, Posbd.Customers.Customer
    belongs_to :created_by, Posbd.Accounts.User

    has_many :items, Posbd.Billing.InvoiceItem
    has_many :payments, Posbd.Billing.Payment

    timestamps(type: :utc_datetime)
  end

  def statuses, do: @statuses
  def payment_statuses, do: @payment_statuses
  def sources, do: @sources

  @doc """
  Builds the changeset for a fully-computed invoice. Every field here is
  set by `Posbd.Billing` from server-side calculations (§53) - nothing
  is cast from raw client params, because client-submitted totals must
  never be trusted.
  """
  def build_changeset(invoice, fields) do
    invoice
    |> change(fields)
    |> validate_required([
      :business_id,
      :invoice_number,
      :currency,
      :subtotal,
      :tax_amount,
      :total_amount,
      :issued_at
    ])
    |> validate_inclusion(:status, @statuses)
    |> validate_inclusion(:payment_status, @payment_statuses)
    |> validate_inclusion(:source, @sources)
    |> unique_constraint([:business_id, :invoice_number], error_key: :invoice_number)
    |> unique_constraint([:business_id, :idempotency_key], error_key: :idempotency_key)
  end

  def status_changeset(invoice, status) do
    invoice
    |> change(status: status)
    |> validate_inclusion(:status, @statuses)
  end

  def payment_recorded_changeset(invoice, amount_paid, payment_status) do
    invoice
    |> change(amount_paid: amount_paid, payment_status: payment_status)
    |> validate_inclusion(:payment_status, @payment_statuses)
  end
end
