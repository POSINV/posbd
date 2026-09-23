defmodule Posbd.Categories.Category do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "categories" do
    field :name, :string
    field :slug, :string
    field :position, :integer, default: 0
    field :active, :boolean, default: true

    belongs_to :business, Posbd.Businesses.Business
    belongs_to :parent, __MODULE__
    has_many :children, __MODULE__, foreign_key: :parent_id

    timestamps(type: :utc_datetime)
  end

  @doc """
  `business_id` is set explicitly by the context (never cast from client
  params); `parent_id` is cast but validated against the same business.
  """
  def changeset(category, attrs) do
    category
    |> cast(attrs, [:name, :parent_id, :position, :active])
    |> validate_required([:name])
    |> validate_length(:name, min: 1, max: 160)
    |> put_slug()
    |> unique_constraint([:business_id, :slug], error_key: :name)
  end

  defp put_slug(changeset) do
    case get_change(changeset, :name) do
      nil ->
        changeset

      name ->
        slug =
          name
          |> String.downcase()
          |> String.replace(~r/[^a-z0-9]+/, "-")
          |> String.trim("-")

        put_change(changeset, :slug, slug)
    end
  end
end
