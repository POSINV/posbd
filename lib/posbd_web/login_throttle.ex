defmodule PosbdWeb.LoginThrottle do
  @moduledoc """
  Limits failed-login guessing per email address (10 attempts per 15
  minutes by default). Keyed on the email rather than the client IP, so it
  still protects an account when every request arrives through the same
  proxy IP, and one attacker can't lock out other users' addresses.
  """

  import Plug.Conn
  import Phoenix.Controller, only: [json: 2]

  alias Posbd.RateLimiter

  @window_ms :timer.minutes(15)

  def check(conn, realm, email) do
    case RateLimiter.hit(key(realm, email), limit(), @window_ms) do
      :ok ->
        :ok

      {:error, retry_after} ->
        conn =
          conn
          |> put_resp_header("retry-after", Integer.to_string(retry_after))
          |> put_status(:too_many_requests)
          |> json(%{
            error: %{message: "Too many login attempts. Please try again in a few minutes."}
          })

        {:halt, conn}
    end
  end

  def reset(realm, email), do: RateLimiter.reset(key(realm, email))

  defp key(realm, email) when is_binary(email),
    do: {:login, realm, email |> String.trim() |> String.downcase()}

  defp key(realm, _email), do: {:login, realm, :invalid}

  defp limit, do: Application.get_env(:posbd, :login_attempt_limit, 10)
end
