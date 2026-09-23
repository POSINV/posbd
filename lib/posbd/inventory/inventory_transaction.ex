defmodule Posbd.Inventory.InventoryTransaction do
  @moduledoc """
  One row per stock movement (see AGENTS.md §9) - opening stock, purchase,
  sale, return, or adjustment. Rows are append-only: nothing here is ever
  updated or deleted after insert, since it's the audit trail behind the
  cached `stock_quantity` on Product/ProductVariant.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @movement_types ~w(opening_stock purchase sale return adjustment)
  @directions ~w(in out)

  schema "inventory_transactions" do
    field :movement_type, :string
    field :direction, :string
    field :quantity, :integer
    field :reference, :string
    field :notes, :string
    field :occurred_at, :utc_datetime_usec

    belongs_to :business, Posbd.Businesses.Business
    belongs_to :product, Posbd.Products.Product
    belongs_to :variant, Posbd.Products.ProductVariant
    belongs_to :performed_by, Posbd.Accounts.User

    timestamps(type: :utc_datetime, updated_at: false)
  end

  def movement_types, do: @movement_types
  def directions, do: @directions

  @fields ~w(movement_type direction quantity reference notes occurred_at
             product_id variant_id business_id performed_by_id)a
  @required ~w(movement_type direction quantity business_id)a

  @doc """
  `business_id`, `product_id`/`variant_id`, and `performed_by_id` are set
  explicitly by the context, never cast from client params.
  """
  def changeset(transaction, attrs) do
    transaction
    |> cast(attrs, @fields)
    |> validate_required(@required)
    |> validate_inclusion(:movement_type, @movement_types)
    |> validate_inclusion(:direction, @directions)
    |> validate_number(:quantity, greater_than: 0)
    |> put_default_occurred_at()
    |> validate_exactly_one_target()
    |> foreign_key_constraint(:product_id)
    |> foreign_key_constraint(:variant_id)
    |> check_constraint(:base, name: :exactly_one_of_product_or_variant)
    |> check_constraint(:quantity, name: :quantity_must_be_positive)
  end

  defp put_default_occurred_at(changeset) do
    if get_field(changeset, :occurred_at) do
      changeset
    else
      put_change(changeset, :occurred_at, DateTime.utc_now())
    end
  end

  defp validate_exactly_one_target(changeset) do
    product_id = get_field(changeset, :product_id)
    variant_id = get_field(changeset, :variant_id)

    case {product_id, variant_id} do
      {nil, nil} ->
        add_error(changeset, :product_id, "must set either product_id or variant_id")

      {p, v} when not is_nil(p) and not is_nil(v) ->
        add_error(changeset, :variant_id, "cannot set both product_id and variant_id")

      _ ->
        changeset
    end
  end
end
