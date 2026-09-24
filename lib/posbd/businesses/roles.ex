defmodule Posbd.Businesses.Roles do
  @moduledoc """
  Central registry of roles and the granular permissions they grant by
  default. Kept as plain data (not scattered across controllers/pages) so
  authorization stays enforceable from the backend regardless of which
  client is asking, per the platform's permission model.
  """

  @roles ~w(owner admin manager cashier inventory_staff accountant)

  @all_permissions ~w(
    products.view products.create products.update products.delete
    inventory.view inventory.adjust
    billing.create billing.cancel billing.discount
    customers.view customers.manage
    reports.view reports.export
    users.manage settings.manage audit.view
  )

  @default_permissions %{
    "owner" => @all_permissions,
    "admin" => @all_permissions,
    "manager" =>
      ~w(products.view products.create products.update inventory.view inventory.adjust
         billing.create billing.discount customers.view customers.manage reports.view reports.export),
    "cashier" => ~w(products.view billing.create customers.view),
    "inventory_staff" => ~w(products.view products.update inventory.view inventory.adjust),
    "accountant" => ~w(reports.view reports.export billing.view customers.view)
  }

  def roles, do: @roles

  def all_permissions, do: @all_permissions

  def default_permissions_for("owner"), do: @default_permissions["owner"]
  def default_permissions_for(role), do: Map.get(@default_permissions, role, [])

  def valid_role?(role), do: role in @roles

  @doc "True if the membership's role/permissions grant the given permission."
  def can?(%Posbd.Businesses.Membership{role: "owner"}, _permission), do: true

  def can?(%Posbd.Businesses.Membership{permissions: permissions}, permission),
    do: permission in permissions

  def can?(nil, _permission), do: false
end
