defmodule Posbd.Businesses.BusinessTypes do
  @moduledoc """
  Predefined business templates offered during onboarding (see AGENTS.md
  §44 Business Templates). Each template only supplies *defaults* -
  categories, feature flags, suggested units - the business can change
  everything afterwards. Adding a new industry means adding an entry
  here, not a new schema or a new code path.
  """

  @templates %{
    "clothing" => %{
      label: "Clothing / Dress Shop",
      default_categories: ["Men's", "Women's", "Kids'", "Accessories"],
      features: ["variants", "barcode"],
      variant_attributes: ["size", "color", "fabric", "gender"]
    },
    "restaurant" => %{
      label: "Restaurant / Food Business",
      default_categories: ["Starters", "Main Course", "Beverages", "Desserts"],
      features: ["variants", "tables", "kitchen"],
      variant_attributes: ["portion_size", "spice_level", "type"]
    },
    "medical" => %{
      label: "Medical / Pharmacy Store",
      default_categories: ["Tablets", "Syrups", "Injections", "Medical Equipment"],
      features: ["batch_tracking", "expiry_tracking", "barcode"],
      variant_attributes: ["batch", "expiry", "manufacturer", "strength"]
    },
    "grocery" => %{
      label: "Grocery Store",
      default_categories: ["Fruits & Vegetables", "Staples", "Dairy", "Beverages", "Household"],
      features: ["barcode", "wholesale_pricing"],
      variant_attributes: ["weight", "pack_size"]
    },
    "electronics" => %{
      label: "Electronics Store",
      default_categories: ["Mobiles", "Accessories", "Appliances", "Computers"],
      features: ["barcode", "serial_tracking", "warranty"],
      variant_attributes: ["model", "color", "storage"]
    },
    "footwear" => %{
      label: "Footwear Store",
      default_categories: ["Men's", "Women's", "Kids'", "Sports"],
      features: ["variants", "barcode"],
      variant_attributes: ["size", "color", "brand"]
    },
    "cosmetics" => %{
      label: "Cosmetics Store",
      default_categories: ["Skincare", "Makeup", "Haircare", "Fragrance"],
      features: ["barcode", "expiry_tracking"],
      variant_attributes: ["shade", "volume"]
    },
    "stationery" => %{
      label: "Stationery Store",
      default_categories: ["Writing", "Office Supplies", "Art Supplies", "Books"],
      features: ["barcode"],
      variant_attributes: ["size", "color"]
    },
    "hardware" => %{
      label: "Hardware Store",
      default_categories: ["Tools", "Electrical", "Plumbing", "Paints"],
      features: ["barcode", "wholesale_pricing"],
      variant_attributes: ["size", "material"]
    },
    "general" => %{
      label: "General Retail Store",
      default_categories: ["General"],
      features: ["barcode"],
      variant_attributes: []
    }
  }

  def templates, do: @templates

  def list do
    Enum.map(@templates, fn {key, template} -> Map.put(template, :key, key) end)
  end

  def get(key), do: Map.get(@templates, key)

  def valid_type?(key), do: Map.has_key?(@templates, key)
end
