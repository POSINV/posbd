defmodule Posbd.Accounts.Scope do
  @moduledoc """
  Carries the authenticated user and, once selected, the current tenant
  (business) + membership for the request. Every context function that
  touches tenant-scoped data should accept a `%Scope{}` and filter by
  `scope.business.id` rather than trusting a bare id from the client —
  this is the single choke point for tenant isolation.
  """

  alias Posbd.Accounts.User
  alias Posbd.Businesses.{Business, Membership}

  defstruct user: nil, business: nil, membership: nil

  def for_user(%User{} = user), do: %__MODULE__{user: user}
  def for_user(nil), do: nil

  def put_business(%__MODULE__{} = scope, %Business{} = business, %Membership{} = membership) do
    %{scope | business: business, membership: membership}
  end

  def role(%__MODULE__{membership: %Membership{role: role}}), do: role
  def role(%__MODULE__{membership: nil}), do: nil
end
