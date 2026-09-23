defmodule PosbdWeb.CORS do
  @moduledoc """
  Origins allowed to call the JSON API from a browser, i.e. the Vue
  frontend's dev and deployed URLs. Configured via env so each
  deployment can point at its own frontend without a code change.
  """

  def allowed_origins do
    Application.get_env(:posbd, :cors_origins, ["http://localhost:5173", "http://127.0.0.1:5173"])
  end
end
