defmodule Posbd.Pricing.PriceTier do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "price_tiers" do
    field :label, :string, default: "Custom"
    field :min_quantity, :integer, default: 1
    field :price, :decimal
    field :effective_from, :date
    field :effective_to, :date

    belongs_to :business, Posbd.Businesses.Business
    belongs_to :product, Posbd.Products.Product
    belongs_to :variant, Posbd.Products.ProductVariant

    timestamps(type: :utc_datetime)
  end

  @fields ~w(label min_quantity price effective_from effective_to product_id variant_id)a

  @doc """
  `business_id` is set explicitly by the context, never cast from client
  params. Exactly one of `product_id`/`variant_id` must be set - a tier
  prices either a simple product or one specific variant, never both.
  """
  def changeset(price_tier, attrs) do
    price_tier
    |> cast(attrs, @fields)
    |> validate_required([:label, :min_quantity, :price])
    |> validate_number(:min_quantity, greater_than_or_equal_to: 1)
    |> validate_number(:price, greater_than_or_equal_to: 0)
    |> validate_date_range()
    |> validate_exactly_one_target()
    |> foreign_key_constraint(:product_id)
    |> foreign_key_constraint(:variant_id)
    |> check_constraint(:base, name: :exactly_one_of_product_or_variant)
  end

  defp validate_date_range(changeset) do
    from = get_field(changeset, :effective_from)
    to = get_field(changeset, :effective_to)

    if from && to && Date.compare(from, to) == :gt do
      add_error(changeset, :effective_to, "must be on or after the start date")
    else
      changeset
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
