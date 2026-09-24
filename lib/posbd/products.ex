defmodule Posbd.Products do
  @moduledoc """
  Products, variants, and the attribute system that backs them (see
  AGENTS.md §6 and §34). Every function takes a `%Scope{}` with a
  business already resolved and filters/writes strictly within that
  business - the single choke point for tenant isolation on the
  product catalog.
  """

  import Ecto.Query, warn: false

  alias Posbd.AuditLogs
  alias Posbd.Repo
  alias Posbd.Accounts.Scope
  alias Posbd.Products.{Attribute, AttributeValue, Product, ProductVariant, VariantAttributeValue}

  @default_page_size 25

  ## Products

  @doc """
  Lists products for the scope's business with optional `search` (matches
  name/sku/barcode), `category_id`, and `page`/`page_size` params, so the
  frontend never has to load the full catalog at once (see AGENTS.md §29).
  """
  def list_products(%Scope{business: business}, params \\ %{}) do
    page = max(to_integer(params[:page] || params["page"], 1), 1)

    page_size =
      min(to_integer(params[:page_size] || params["page_size"], @default_page_size), 100)

    base_query =
      from(p in Product, where: p.business_id == ^business.id)
      |> maybe_filter_search(params[:search] || params["search"])
      |> maybe_filter_category(params[:category_id] || params["category_id"])

    total_count = base_query |> select(count()) |> Repo.one()

    products =
      base_query
      |> order_by([p], asc: p.name)
      |> limit(^page_size)
      |> offset(^((page - 1) * page_size))
      |> preload(
        variants:
          ^from(v in ProductVariant,
            order_by: v.position,
            preload: [attribute_values: :attribute]
          )
      )
      |> Repo.all()

    %{data: products, page: page, page_size: page_size, total_count: total_count}
  end

  defp maybe_filter_search(query, nil), do: query
  defp maybe_filter_search(query, ""), do: query

  defp maybe_filter_search(query, term) do
    pattern = "%#{term}%"

    from p in query,
      where: ilike(p.name, ^pattern) or ilike(p.sku, ^pattern) or ilike(p.barcode, ^pattern)
  end

  defp maybe_filter_category(query, nil), do: query
  defp maybe_filter_category(query, ""), do: query

  defp maybe_filter_category(query, category_id),
    do: from(p in query, where: p.category_id == ^category_id)

  defp to_integer(nil, default), do: default

  defp to_integer(value, default) when is_binary(value) do
    case Integer.parse(value) do
      {int, _} -> int
      :error -> default
    end
  end

  defp to_integer(value, _default) when is_integer(value), do: value

  def get_product(%Scope{business: business}, id) do
    Product
    |> Repo.get_by(id: id, business_id: business.id)
    |> case do
      nil ->
        nil

      product ->
        Repo.preload(product,
          variants:
            {from(v in ProductVariant, order_by: v.position), [attribute_values: :attribute]}
        )
    end
  end

  def create_product(%Scope{business: business} = scope, attrs) do
    %Product{business_id: business.id}
    |> Product.changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, product} = ok ->
        AuditLogs.record(scope, "product.created", "Product", product.id, %{
          name: product.name,
          sku: product.sku
        })

        ok

      error ->
        error
    end
  end

  @price_fields [:purchase_price, :selling_price, :mrp]

  def update_product(%Scope{} = scope, %Product{} = product, attrs) do
    changeset = Product.changeset(product, attrs)

    case Repo.update(changeset) do
      {:ok, updated} = ok ->
        log_product_update(scope, product, updated, changeset)
        ok

      error ->
        error
    end
  end

  defp log_product_update(scope, before, updated, changeset) do
    changed_price_fields = Enum.filter(@price_fields, &Map.has_key?(changeset.changes, &1))

    if changed_price_fields == [] do
      AuditLogs.record(scope, "product.updated", "Product", updated.id, %{})
    else
      changes =
        Map.new(changed_price_fields, fn field ->
          {field, %{from: money(Map.get(before, field)), to: money(Map.get(updated, field))}}
        end)

      AuditLogs.record(scope, "product.price_changed", "Product", updated.id, changes)
    end
  end

  defp money(nil), do: nil
  defp money(%Decimal{} = decimal), do: Decimal.to_string(decimal)

  def delete_product(%Scope{} = scope, %Product{} = product) do
    case Repo.delete(product) do
      {:ok, deleted} = ok ->
        AuditLogs.record(scope, "product.deleted", "Product", deleted.id, %{
          name: deleted.name,
          sku: deleted.sku
        })

        ok

      error ->
        error
    end
  end

  ## Variants

  @doc """
  Creates a variant under `product`. `attrs["attributes"]` (or
  `attrs[:attributes]`) is an optional `%{"Size" => "M", "Color" => "Red"}`
  map; attributes/values are found-or-created per business so the catalog
  builds its own vocabulary as products are added, matching AGENTS.md §34
  (no industry-specific hardcoding).
  """
  def create_variant(%Scope{business: business}, %Product{} = product, attrs) do
    attribute_map = Map.get(attrs, "attributes") || Map.get(attrs, :attributes) || %{}

    Repo.transact(fn ->
      with {:ok, variant} <-
             %ProductVariant{product_id: product.id, business_id: business.id}
             |> ProductVariant.changeset(attrs)
             |> Repo.insert(),
           {:ok, _} <- put_variant_attributes(business, variant, attribute_map) do
        {:ok, Repo.preload(variant, attribute_values: :attribute)}
      end
    end)
  end

  def update_variant(%Scope{business: business}, %ProductVariant{} = variant, attrs) do
    attribute_map = Map.get(attrs, "attributes") || Map.get(attrs, :attributes)

    Repo.transact(fn ->
      with {:ok, variant} <- variant |> ProductVariant.changeset(attrs) |> Repo.update(),
           {:ok, _} <- maybe_put_variant_attributes(business, variant, attribute_map) do
        {:ok, Repo.preload(variant, [attribute_values: :attribute], force: true)}
      end
    end)
  end

  def delete_variant(%ProductVariant{} = variant) do
    Repo.delete(variant)
  end

  def get_variant(%Scope{business: business}, id) do
    Repo.get_by(ProductVariant, id: id, business_id: business.id)
  end

  defp maybe_put_variant_attributes(_business, _variant, nil), do: {:ok, :unchanged}

  defp maybe_put_variant_attributes(business, variant, map),
    do: put_variant_attributes(business, variant, map)

  defp put_variant_attributes(_business, _variant, map) when map_size(map) == 0,
    do: {:ok, :unchanged}

  defp put_variant_attributes(business, variant, attribute_map) do
    Repo.delete_all(from vav in VariantAttributeValue, where: vav.variant_id == ^variant.id)

    Enum.reduce_while(attribute_map, {:ok, :done}, fn {name, value}, _acc ->
      with {:ok, attribute} <- find_or_create_attribute(business, name),
           {:ok, attribute_value} <- find_or_create_attribute_value(attribute, value),
           {:ok, _} <-
             %VariantAttributeValue{}
             |> VariantAttributeValue.changeset(%{
               variant_id: variant.id,
               attribute_id: attribute.id,
               attribute_value_id: attribute_value.id
             })
             |> Repo.insert() do
        {:cont, {:ok, :done}}
      else
        error -> {:halt, error}
      end
    end)
  end

  defp find_or_create_attribute(business, name) do
    name = String.trim(to_string(name))

    case Repo.get_by(Attribute, business_id: business.id, name: name) do
      nil ->
        %Attribute{business_id: business.id}
        |> Attribute.changeset(%{name: name})
        |> Repo.insert()

      attribute ->
        {:ok, attribute}
    end
  end

  defp find_or_create_attribute_value(attribute, value) do
    value = String.trim(to_string(value))

    case Repo.get_by(AttributeValue, attribute_id: attribute.id, value: value) do
      nil ->
        %AttributeValue{attribute_id: attribute.id}
        |> AttributeValue.changeset(%{value: value})
        |> Repo.insert()

      attribute_value ->
        {:ok, attribute_value}
    end
  end

  ## Attributes (for the frontend's variant builder to suggest existing values)

  def list_attributes(%Scope{business: business}) do
    Attribute
    |> where([a], a.business_id == ^business.id)
    |> order_by([a], asc: a.name)
    |> preload(:attribute_values)
    |> Repo.all()
  end
end
