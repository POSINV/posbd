defmodule Posbd.PlatformAdmins.PlatformAdmin do
  @moduledoc """
  An internal platform operator (never a tenant/business user - see Phase 2
  §13/§45, which require this to be a completely separate, non-public
  account domain from `Posbd.Accounts.User`).
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @roles ~w(admin support)

  schema "platform_admins" do
    field :email, :string
    field :full_name, :string
    field :hashed_password, :string, redact: true
    field :password, :string, virtual: true, redact: true
    field :role, :string, default: "support"

    timestamps(type: :utc_datetime)
  end

  def roles, do: @roles

  def changeset(admin, attrs) do
    admin
    |> cast(attrs, [:email, :password, :full_name, :role])
    |> validate_required([:email, :password, :full_name, :role])
    |> validate_inclusion(:role, @roles)
    |> validate_email()
    |> validate_password()
  end

  defp validate_email(changeset) do
    changeset
    |> validate_format(:email, ~r/^[^\s]+@[^\s]+\.[^\s]+$/, message: "must be a valid email")
    |> validate_length(:email, max: 160)
    |> unsafe_validate_unique(:email, Posbd.Repo)
    |> unique_constraint(:email)
    |> update_change(:email, &String.downcase/1)
  end

  defp validate_password(changeset) do
    changeset
    |> validate_length(:password, min: 8, max: 72)
    |> maybe_hash_password()
  end

  defp maybe_hash_password(changeset) do
    password = get_change(changeset, :password)

    if password && changeset.valid? do
      changeset
      |> put_change(:hashed_password, Bcrypt.hash_pwd_salt(password))
      |> delete_change(:password)
    else
      changeset
    end
  end

  def valid_password?(%__MODULE__{hashed_password: hashed_password}, password)
      when is_binary(hashed_password) and byte_size(password) > 0 do
    Bcrypt.verify_pass(password, hashed_password)
  end

  def valid_password?(_admin, _password) do
    Bcrypt.no_user_verify()
    false
  end
end
