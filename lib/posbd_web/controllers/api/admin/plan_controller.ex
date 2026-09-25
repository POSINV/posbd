defmodule PosbdWeb.Api.Admin.PlanController do
  use PosbdWeb, :controller

  alias Posbd.Subscriptions
  alias PosbdWeb.Api.Admin.Authorize
  alias PosbdWeb.Api.SubscriptionJSON

  action_fallback PosbdWeb.Api.FallbackController

  @doc "Lists every plan, including inactive ones (the public plan list only shows active plans)."
  def index(conn, _params) do
    json(conn, %{data: Enum.map(Subscriptions.list_plans(true), &SubscriptionJSON.plan_json/1)})
  end

  def create(%{assigns: %{current_platform_admin: admin}} = conn, %{"plan" => params}) do
    with :ok <- Authorize.require_admin_role(admin),
         {:ok, plan} <- Subscriptions.create_plan(params) do
      conn
      |> put_status(:created)
      |> json(%{data: SubscriptionJSON.plan_json(plan)})
    end
  end

  def update(%{assigns: %{current_platform_admin: admin}} = conn, %{"id" => id, "plan" => params}) do
    with :ok <- Authorize.require_admin_role(admin),
         plan when not is_nil(plan) <- Subscriptions.get_plan(id),
         {:ok, updated} <- Subscriptions.update_plan(plan, params) do
      json(conn, %{data: SubscriptionJSON.plan_json(updated)})
    else
      nil -> {:error, :not_found}
      error -> error
    end
  end
end
