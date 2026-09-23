defmodule Posbd.Accounts.UserToken do
  use Ecto.Schema
  import Ecto.Query

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  # API bearer tokens are valid for 60 days of inactivity.
  @api_token_validity_days 60
  @rand_size 32

  schema "user_tokens" do
    field :token, :binary
    field :context, :string
    field :sent_to, :string
    belongs_to :user, Posbd.Accounts.User

    timestamps(type: :utc_datetime, updated_at: false)
  end

  @doc """
  Builds an opaque bearer token for the given user and returns both the
  plaintext token (to hand back to the client) and the token struct to
  insert (which stores only a hash, so the DB never holds the raw secret).
  """
  def build_api_token(user) do
    token = :crypto.strong_rand_bytes(@rand_size)
    hashed_token = :crypto.hash(:sha256, token)

    {Base.url_encode64(token, padding: false),
     %__MODULE__{token: hashed_token, context: "api-auth", user_id: user.id}}
  end

  @doc """
  Returns a query to fetch the user for a given plaintext bearer token,
  provided it hasn't expired.
  """
  def verify_api_token_query(token) do
    case Base.url_decode64(token, padding: false) do
      {:ok, decoded_token} ->
        hashed_token = :crypto.hash(:sha256, decoded_token)
        days_ago = DateTime.add(DateTime.utc_now(), -@api_token_validity_days, :day)

        query =
          from token in by_token_and_context_query(hashed_token, "api-auth"),
            join: user in assoc(token, :user),
            where: token.inserted_at > ^days_ago,
            select: user

        {:ok, query}

      :error ->
        :error
    end
  end

  def by_token_and_context_query(token, context) do
    from t in __MODULE__, where: t.token == ^token and t.context == ^context
  end

  def by_user_and_context_query(user, context) do
    from t in __MODULE__, where: t.user_id == ^user.id and t.context == ^context
  end

  def token_query(plaintext_token) do
    with {:ok, decoded} <- Base.url_decode64(plaintext_token, padding: false) do
      {:ok, :crypto.hash(:sha256, decoded)}
    end
  end
end
