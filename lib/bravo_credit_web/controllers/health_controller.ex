defmodule BravoCreditWeb.HealthController do
  @moduledoc """
  Lightweight health endpoint for local containers and runtime checks.
  """

  use BravoCreditWeb, :controller

  alias BravoCredit.Repo

  def show(conn, _params) do
    json(conn, %{status: "ok"})
  end

  def ready(conn, _params) do
    checks = %{
      database: database_status(),
      cache: process_status(BravoCredit.Cache),
      pubsub: process_status(BravoCredit.PubSub)
    }

    if Enum.all?(checks, fn {_key, status} -> status == "ok" end) do
      json(conn, %{status: "ok", checks: checks})
    else
      conn
      |> put_status(:service_unavailable)
      |> json(%{status: "error", checks: checks})
    end
  end

  defp database_status do
    case Ecto.Adapters.SQL.query(Repo, "SELECT 1", []) do
      {:ok, _result} -> "ok"
      {:error, _error} -> "error"
    end
  end

  defp process_status(name) do
    if Process.whereis(name) do
      "ok"
    else
      "error"
    end
  end
end
