defmodule Posbd.Businesses do
  @moduledoc """
  Business (tenant) creation/onboarding and membership management.

  Every function that reads or writes tenant-scoped data takes a
  `%Scope{}` and filters by the scope's business/user, so a caller can
  never reach another tenant's rows just by guessing an id.
  """

  import Ecto.Query, warn: false

  alias Posbd.AuditLogs
  alias Posbd.Repo
  alias Posbd.Subscriptions
  alias Posbd.Accounts.Scope
  alias Posbd.Businesses.{Business, Membership}

  @doc "Lists the businesses the scope's user belongs to, with their role."
  def list_businesses_for_user(%Scope{user: user}) do
    from(b in Business,
      join: m in Membership,
      on: m.business_id == b.id,
      where: m.user_id == ^user.id,
      order_by: [asc: b.inserted_at],
      select: {b, m.role}
    )
    |> Repo.all()
  end

  @doc """
  Creates a new business, makes the scope's user its owner, and starts its
  free trial (Phase 2 §4), all in a single transaction so a partially-
  created tenant can never exist.
  """
  def create_business(%Scope{user: user}, attrs) do
    Repo.transact(fn ->
      with {:ok, business} <- %Business{} |> Business.changeset(attrs) |> Repo.insert(),
           {:ok, _membership} <-
             %Membership{}
             |> Membership.owner_changeset(business.id, user.id)
             |> Repo.insert(),
           {:ok, _subscription} <- Subscriptions.start_trial(business) do
        {:ok, business}
      end
    end)
  end

  @doc "Fetches a business by id with no user/membership scoping - platform-admin use only, never exposed to tenant-scoped routes."
  def get_business(id), do: Repo.get(Business, id)

  @doc "Fetches a business for the scope's user, returning nil if not a member."
  def get_business_for_user(%Scope{user: user}, business_id) do
    from(b in Business,
      join: m in Membership,
      on: m.business_id == b.id,
      where: b.id == ^business_id and m.user_id == ^user.id,
      select: {b, m}
    )
    |> Repo.one()
  end

  def update_business(%Scope{} = scope, %Business{} = business, attrs) do
    changeset = Business.changeset(business, attrs)

    case Repo.update(changeset) do
      {:ok, updated} = ok ->
        changed_fields = changeset.changes |> Map.keys() |> Enum.map(&to_string/1)

        if changed_fields != [] do
          AuditLogs.record(scope, "business.settings_updated", "Business", updated.id, %{
            fields: changed_fields
          })
        end

        ok

      error ->
        error
    end
  end

  def complete_onboarding(%Scope{} = scope, %Business{} = business) do
    case business |> Business.complete_onboarding_changeset() |> Repo.update() do
      {:ok, updated} = ok ->
        AuditLogs.record(scope, "business.onboarding_completed", "Business", updated.id, %{})
        ok

      error ->
        error
    end
  end

  @doc "Loads the scope's membership for the given business, or nil."
  def get_membership(%Scope{user: user}, business_id) do
    Repo.get_by(Membership, business_id: business_id, user_id: user.id)
  end
end
