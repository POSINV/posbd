defmodule PosbdWeb.Api.AttributeJSON do
  alias Posbd.Products.Attribute

  def index(%{attributes: attributes}), do: %{data: Enum.map(attributes, &attribute_json/1)}

  defp attribute_json(%Attribute{} = attribute) do
    %{
      id: attribute.id,
      name: attribute.name,
      values: Enum.map(attribute.attribute_values, & &1.value)
    }
  end
end
