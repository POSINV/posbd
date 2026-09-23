defmodule Posbd.Accounts do
  @moduledoc """
  User registration, authentication, and API bearer-token management.
  """

  import Ecto.Query, warn: false

  alias Posbd.Repo
  alias Posbd.Accounts.{User, UserToken, Scope}

  ## Users

  def get_user(id), do: Repo.get(User, id)

  def get_user_by_email(email) when is_binary(email) do
    Repo.get_by(User, email: String.downcase(email))
  end

  def get_user_by_email_and_password(email, password)
      when is_binary(email) and is_binary(password) do
    user = get_user_by_email(email)
    if User.valid_password?(user, password), do: user
  end

  def register_user(attrs) do
    %User{}
    |> User.registration_changeset(attrs)
    |> Repo.insert()
  end

  ## API tokens

  @doc """
  Creates a bearer token for the user and returns the plaintext token.
  """
  def create_api_token(%User{} = user) do
    {plaintext_token, user_token} = UserToken.build_api_token(user)
    Repo.insert!(user_token)
    plaintext_token
  end

  @doc """
  Looks up the user for a bearer token and, if found, returns a base
  `%Scope{}` for the request. Returns nil for missing/expired tokens.
  """
  def fetch_scope_by_api_token(token) when is_binary(token) do
    case UserToken.verify_api_token_query(token) do
      {:ok, query} ->
        case Repo.one(query) do
          %User{} = user -> Scope.for_user(user)
          nil -> nil
        end

      :error ->
        nil
    end
  end

  def fetch_scope_by_api_token(_), do: nil

  @doc "Revokes the bearer token so it can no longer be used."
  def revoke_api_token(token) when is_binary(token) do
    with {:ok, hashed} <- UserToken.token_query(token) do
      Repo.delete_all(from t in UserToken, where: t.token == ^hashed and t.context == "api-auth")
    end

    :ok
  end
end
