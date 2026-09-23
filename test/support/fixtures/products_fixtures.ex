defmodule Posbd.ProductsFixtures do
  alias Posbd.Accounts.Scope
  alias Posbd.Categories
  alias Posbd.Products

  def valid_category_attrs(attrs \\ %{}) do
    Enum.into(attrs, %{name: "Category #{System.unique_integer()}"})
  end

  def category_fixture(%Scope{} = scope, attrs \\ %{}) do
    {:ok, category} = Categories.create_category(scope, valid_category_attrs(attrs))
    category
  end

  def valid_product_attrs(attrs \\ %{}) do
    Enum.into(attrs, %{
      name: "Product #{System.unique_integer()}",
      unit: "pcs",
      selling_price: "199.00",
      purchase_price: "120.00"
    })
  end

  def product_fixture(%Scope{} = scope, attrs \\ %{}) do
    {:ok, product} = Products.create_product(scope, valid_product_attrs(attrs))
    product
  end

  def valid_variant_attrs(attrs \\ %{}) do
    Enum.into(attrs, %{selling_price: "199.00", purchase_price: "120.00"})
  end

  def variant_fixture(%Scope{} = scope, product, attrs \\ %{}) do
    {:ok, variant} = Products.create_variant(scope, product, valid_variant_attrs(attrs))
    variant
  end
end
