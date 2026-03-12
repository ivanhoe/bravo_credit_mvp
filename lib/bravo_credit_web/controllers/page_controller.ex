defmodule BravoCreditWeb.PageController do
  use BravoCreditWeb, :controller

  def home(conn, _params) do
    redirect(conn, to: ~p"/operations")
  end
end
