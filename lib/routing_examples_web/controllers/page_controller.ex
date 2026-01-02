defmodule RoutingExamplesWeb.PageController do
  use RoutingExamplesWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
