defmodule Posbd.Businesses.Membership do
  use Ecto.Schema
  import Ecto.Changeset

  alias Posbd.Businesses.Roles

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "business_memberships" do
    field :role, :string, default: "owner"
    field :permissions, {:array, :string}, default: []

    belongs_to :business, Posbd.Businesses.Business
    belongs_to :user, Posbd.Accounts.User

    timestamps(type: :utc_datetime)
  end

  @doc """
  Builds the owner membership created alongside a new business.
  `business_id`/`user_id` are set explicitly by the context, never cast
  from client params.
  """
  def owner_changeset(membership, business_id, user_id) do
    change(membership,
      business_id: business_id,
      user_id: user_id,
      role: "owner",
      permissions: Roles.default_permissions_for("owner")
    )
  end

  def role_changeset(membership, attrs) do
    membership
    |> cast(attrs, [:role])
    |> validate_required([:role])
    |> validate_inclusion(:role, Roles.roles())
    |> put_default_permissions()
  end

  defp put_default_permissions(changeset) do
    case get_change(changeset, :role) do
      nil -> changeset
      role -> put_change(changeset, :permissions, Roles.default_permissions_for(role))
    end
  end
end
