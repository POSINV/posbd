defmodule PosbdWeb.ConnCase do
  @moduledoc """
  This module defines the test case to be used by
  tests that require setting up a connection.

  Such tests rely on `Phoenix.ConnTest` and also
  import other functionality to make it easier
  to build common data structures and query the data layer.

  Finally, if the test case interacts with the database,
  we enable the SQL sandbox, so changes done to the database
  are reverted at the end of every test. If you are using
  PostgreSQL, you can even run database tests asynchronously
  by setting `use PosbdWeb.ConnCase, async: true`, although
  this option is not recommended for other databases.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      # The default endpoint for testing
      @endpoint PosbdWeb.Endpoint

      use PosbdWeb, :verified_routes
      use Oban.Testing, repo: Posbd.Repo

      # Import conveniences for testing with connections
      import Plug.Conn
      import Phoenix.ConnTest
      import PosbdWeb.ConnCase
    end
  end

  setup tags do
    Posbd.DataCase.setup_sandbox(tags)
    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end

  @doc """
  Builds a fresh conn authenticated as the scope's user and scoped to
  their business. `Phoenix.ConnTest`'s request helpers only recycle the
  `authorization` header between chained calls (not custom ones), so
  tests that issue several tenant-scoped requests in a row should build
  a fresh conn per request with this helper rather than reusing the conn
  returned by a previous request.
  """
  def authed_conn(scope) do
    token = Posbd.Accounts.create_api_token(scope.user)

    Phoenix.ConnTest.build_conn()
    |> Plug.Conn.put_req_header("authorization", "Bearer #{token}")
    |> Plug.Conn.put_req_header("x-business-id", scope.business.id)
  end
end
