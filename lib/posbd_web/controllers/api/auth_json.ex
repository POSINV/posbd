defmodule PosbdWeb.Api.AuthJSON do
  alias Posbd.Accounts.User

  def session(%{user: user, token: token}) do
    %{token: token, user: user_json(user)}
  end

  def me(%{user: user, businesses: businesses}) do
    %{
      user: user_json(user),
      businesses:
        Enum.map(businesses, fn {business, role} ->
          PosbdWeb.Api.BusinessJSON.business_summary(business, role)
        end)
    }
  end

  defp user_json(%User{} = user) do
    %{id: user.id, email: user.email, full_name: user.full_name}
  end
end
