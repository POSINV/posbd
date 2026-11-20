defmodule Posbd.TenantValidation do
  @moduledoc """
  Changeset helper that keeps foreign keys inside the tenant. Database
  foreign keys only check that the referenced row *exists*, not that it
  belongs to the same business - so without this a client could point a
  product at another business's category just by sending its id.
  """

  import Ecto.Changeset
  import Ecto.Query, only: [from: 2]

  alias Posbd.Repo

  @doc """
  Adds an error on `field` unless its (changed) value is the id of a
  `schema` row with the same `business_id` as the record being changed.
  """
  def validate_same_business(%Ecto.Changeset{} = changeset, field, schema) do
    validate_change(changeset, field, fn ^field, id ->
      business_id = get_field(changeset, :business_id)

      with false <- is_nil(business_id),
           {:ok, uuid} <- Ecto.UUID.cast(id),
           true <-
             Repo.exists?(
               from r in schema, where: r.id == ^uuid and r.business_id == ^business_id
             ) do
        []
      else
        _ -> [{field, "does not exist"}]
      end
    end)
  end
end
