defmodule PosbdWeb.Api.CategoryJSON do
  alias Posbd.Categories.Category

  def index(%{categories: categories}), do: %{data: Enum.map(categories, &category_json/1)}
  def show(%{category: category}), do: %{data: category_json(category)}

  defp category_json(%Category{} = category) do
    %{
      id: category.id,
      name: category.name,
      slug: category.slug,
      parent_id: category.parent_id,
      position: category.position,
      active: category.active
    }
  end
end
