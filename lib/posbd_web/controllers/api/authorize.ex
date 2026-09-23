defmodule PosbdWeb.Api.Authorize do
  @moduledoc "Small helper so tenant-scoped controllers check permissions consistently."

  alias Posbd.Accounts.Scope
  alias Posbd.Businesses.Roles

  @doc "Returns `:ok` or `{:error, :unauthorized}` for the fallback controller to render."
  def require(%Scope{membership: membership}, permission) do
    if Roles.can?(membership, permission), do: :ok, else: {:error, :unauthorized}
  end
end
