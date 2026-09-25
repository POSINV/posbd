defmodule PosbdWeb.Api.Admin.SessionJSON do
  alias Posbd.PlatformAdmins.PlatformAdmin

  def session(%{admin: admin, token: token}) do
    %{data: %{token: token, admin: admin_json(admin)}}
  end

  def me(%{admin: admin}) do
    %{data: admin_json(admin)}
  end

  defp admin_json(%PlatformAdmin{} = admin) do
    %{id: admin.id, email: admin.email, full_name: admin.full_name, role: admin.role}
  end
end
