defmodule PosbdWeb.Api.AppConfigControllerTest do
  # Flips global application env, so it can't run alongside async tests.
  use PosbdWeb.ConnCase, async: false

  setup do
    on_exit(fn ->
      Application.put_env(:posbd, :app_env, "test")
      Application.put_env(:posbd, :integrations_enabled, true)
    end)
  end

  test "reports integrations as disabled in local", %{conn: conn} do
    Application.put_env(:posbd, :app_env, "local")
    Application.put_env(:posbd, :integrations_enabled, false)

    data = conn |> get(~p"/api/v1/app_config") |> json_response(200) |> Map.fetch!("data")

    assert data["app_env"] == "local"

    for name <- ~w(email whatsapp razorpay) do
      assert data["integrations"][name]["enabled"] == false
    end
  end

  test "reports integrations as enabled when switched on", %{conn: conn} do
    data = conn |> get(~p"/api/v1/app_config") |> json_response(200) |> Map.fetch!("data")

    assert data["integrations"]["razorpay"] == %{"enabled" => true, "configured" => true}
    assert data["integrations"]["whatsapp"] == %{"enabled" => true, "configured" => true}
  end

  test "provider webhooks are refused in local", %{conn: conn} do
    Application.put_env(:posbd, :app_env, "local")
    Application.put_env(:posbd, :integrations_enabled, false)

    assert conn |> post(~p"/api/v1/webhooks/razorpay", %{}) |> json_response(503)
    assert build_conn() |> get(~p"/api/v1/webhooks/whatsapp", %{}) |> json_response(503)
  end
end
