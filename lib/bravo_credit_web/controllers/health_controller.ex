defmodule BravoCreditWeb.HealthController do
  @moduledoc """
  Lightweight health endpoint for local containers and runtime checks.
  """

  use BravoCreditWeb, :controller

  def show(conn, _params) do
    json(conn, %{status: "ok"})
  end
end
