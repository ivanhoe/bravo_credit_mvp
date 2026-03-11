defmodule BravoCreditWeb.PageController do
  use BravoCreditWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
