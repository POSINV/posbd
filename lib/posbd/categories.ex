defmodule Posbd.Categories do
  @moduledoc """
  Product categories for a business, including parent/child nesting
  (see AGENTS.md §7). Every function takes a `%Scope{}` with a business
  already resolved and filters by `scope.business.id`.
  """

  import Ecto.Query, warn: false

  alias Posbd.Repo
  alias Posbd.Accounts.Scope
  alias Posbd.Categories.Category

  def list_categories(%Scope{business: business}) do
    from(c in Category,
      where: c.business_id == ^business.id,
      order_by: [asc: c.position, asc: c.name]
    )
    |> Repo.all()
  end

  def get_category(%Scope{business: business}, id) do
    Repo.get_by(Category, id: id, business_id: business.id)
  end

  def create_category(%Scope{business: business}, attrs) do
    %Category{business_id: business.id}
    |> Category.changeset(attrs)
    |> Repo.insert()
  end

  def update_category(%Category{} = category, attrs) do
    category
    |> Category.changeset(attrs)
    |> Repo.update()
  end

  def delete_category(%Category{} = category) do
    Repo.delete(category)
  end
end
