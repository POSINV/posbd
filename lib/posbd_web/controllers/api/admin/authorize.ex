defmodule PosbdWeb.Api.Admin.Authorize do
  @moduledoc "Restricts destructive/financial admin actions to the 'admin' role - 'support' accounts are read-only (Phase 2 §45)."

  alias Posbd.PlatformAdmins.PlatformAdmin

  def require_admin_role(%PlatformAdmin{role: "admin"}), do: :ok
  def require_admin_role(%PlatformAdmin{}), do: {:error, :unauthorized}
end
