defmodule BravoCreditWeb.ApplicationController do
  @moduledoc """
  JSON API endpoints for credit applications.
  """

  use BravoCreditWeb, :controller

  alias BravoCredit.Applications

  action_fallback BravoCreditWeb.FallbackController

  def create(conn, params) do
    with {:ok, application} <- Applications.create(params, "public_api") do
      conn
      |> put_status(:created)
      |> render(:show, application: application)
    end
  end
end
