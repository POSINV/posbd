defmodule Posbd.Integrations do
  @moduledoc """
  Single switch for the external integrations (email, WhatsApp, Razorpay).

  They only ever talk to the real providers in **staging** and
  **production**. In **local** development they are turned off whatever
  keys happen to be in the shell, so nobody sends a real WhatsApp message,
  creates a real Razorpay order or delivers a real email from a laptop.

  The deployment environment comes from `APP_ENV` at runtime
  (`config/runtime.exs`), because staging and production are both built
  with `MIX_ENV=prod`:

  | APP_ENV      | integrations |
  |--------------|--------------|
  | `local`      | off          |
  | `staging`    | on           |
  | `production` | on (default for a `MIX_ENV=prod` build) |

  The test suite turns them on, since every provider call there is stubbed
  with `Req.Test`.
  """

  @integrations [:email, :whatsapp, :razorpay]

  @doc "The deployment environment: `\"local\"`, `\"staging\"`, `\"production\"` or `\"test\"`."
  def app_env, do: Application.get_env(:posbd, :app_env, "local")

  @doc "Whether external integrations may run in this environment at all."
  def enabled?, do: Application.get_env(:posbd, :integrations_enabled, false) == true

  @doc "Whether `integration` (`:email`, `:whatsapp` or `:razorpay`) may talk to its real provider."
  def enabled?(integration) when integration in @integrations, do: enabled?()

  @doc "The error returned by a call into an integration that is turned off here."
  def disabled_error(integration) when integration in @integrations do
    {:error, %{message: disabled_message(integration), integration_disabled: true}}
  end

  def disabled_message(integration) when integration in @integrations do
    "#{label(integration)} is disabled in the #{app_env()} environment. " <>
      "It only runs in staging and production."
  end

  @doc "What the frontend needs to know to show or hide integration features."
  def status do
    %{
      app_env: app_env(),
      integrations:
        Map.new(@integrations, fn integration ->
          {integration, %{enabled: enabled?(integration), configured: configured?(integration)}}
        end)
    }
  end

  defp configured?(:razorpay), do: Posbd.Payments.Razorpay.configured?()
  defp configured?(:whatsapp), do: Posbd.Whatsapp.Provider.configured?()

  defp configured?(:email) do
    adapter = Application.get_env(:posbd, Posbd.Mailer, [])[:adapter]
    adapter not in [nil, Swoosh.Adapters.Local, Swoosh.Adapters.Test]
  end

  defp label(:email), do: "Email"
  defp label(:whatsapp), do: "WhatsApp"
  defp label(:razorpay), do: "Razorpay"
end
