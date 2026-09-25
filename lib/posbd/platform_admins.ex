defmodule Posbd.PlatformAdmins do
  @moduledoc """
  Authentication for internal platform operators (Phase 2 §13/§45). There
  is deliberately no self-service registration here - admin accounts are
  created out-of-band (seeds/console) by someone who already has one.
  """

  import Ecto.Query, warn: false

  alias Posbd.Repo
  alias Posbd.PlatformAdmins.{PlatformAdmin, PlatformAdminToken}

  def get_by_email(email) when is_binary(email) do
    Repo.get_by(PlatformAdmin, email: String.downcase(email))
  end

  def get_by_email_and_password(email, password)
      when is_binary(email) and is_binary(password) do
    admin = get_by_email(email)
    if PlatformAdmin.valid_password?(admin, password), do: admin
  end

  def create_admin(attrs) do
    %PlatformAdmin{}
    |> PlatformAdmin.changeset(attrs)
    |> Repo.insert()
  end

  def create_api_token(%PlatformAdmin{} = admin) do
    {plaintext_token, token} = PlatformAdminToken.build_api_token(admin)
    Repo.insert!(token)
    plaintext_token
  end

  def fetch_admin_by_api_token(token) when is_binary(token) do
    case PlatformAdminToken.verify_api_token_query(token) do
      {:ok, query} -> Repo.one(query)
      :error -> nil
    end
  end

  def fetch_admin_by_api_token(_), do: nil

  def revoke_api_token(token) when is_binary(token) do
    with {:ok, hashed} <- PlatformAdminToken.token_query(token) do
      Repo.delete_all(
        from t in PlatformAdminToken, where: t.token == ^hashed and t.context == "admin-api-auth"
      )
    end

    :ok
  end
end
