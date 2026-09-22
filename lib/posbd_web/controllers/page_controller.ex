defmodule PosbdWeb.PageController do
  use PosbdWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
