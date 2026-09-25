defmodule Posbd.PlatformAdmins.PlatformAdminToken do
  @moduledoc "Opaque bearer tokens for platform admins - same shape as `Posbd.Accounts.UserToken`, kept as a separate table so a leaked tenant-user token can never grant admin access."

  use Ecto.Schema
  import Ecto.Query

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @token_validity_days 14
  @rand_size 32

  schema "platform_admin_tokens" do
    field :token, :binary
    field :context, :string
    belongs_to :platform_admin, Posbd.PlatformAdmins.PlatformAdmin

    timestamps(type: :utc_datetime, updated_at: false)
  end

  def build_api_token(admin) do
    token = :crypto.strong_rand_bytes(@rand_size)
    hashed_token = :crypto.hash(:sha256, token)

    {Base.url_encode64(token, padding: false),
     %__MODULE__{token: hashed_token, context: "admin-api-auth", platform_admin_id: admin.id}}
  end

  def verify_api_token_query(token) do
    case Base.url_decode64(token, padding: false) do
      {:ok, decoded_token} ->
        hashed_token = :crypto.hash(:sha256, decoded_token)
        days_ago = DateTime.add(DateTime.utc_now(), -@token_validity_days, :day)

        query =
          from t in __MODULE__,
            where: t.token == ^hashed_token and t.context == "admin-api-auth",
            where: t.inserted_at > ^days_ago,
            join: admin in assoc(t, :platform_admin),
            select: admin

        {:ok, query}

      :error ->
        :error
    end
  end

  def token_query(plaintext_token) do
    with {:ok, decoded} <- Base.url_decode64(plaintext_token, padding: false) do
      {:ok, :crypto.hash(:sha256, decoded)}
    end
  end
end
