defmodule BravoCreditWeb.ApplicationController do
  @moduledoc """
  JSON API endpoints for credit applications.
  """

  use BravoCreditWeb, :controller

  alias BravoCredit.Applications

  action_fallback BravoCreditWeb.FallbackController

  def index(conn, params) do
    with {:ok, applications} <- Applications.list(conn.assigns.current_user, params) do
      render(conn, :index, applications: applications)
    end
  end

  def show(conn, %{"id" => application_id}) do
    with {:ok, application} <-
           Applications.get_authorized(application_id, conn.assigns.current_user) do
      render(conn, :show,
        application: application,
        detail: true,
        available_transitions: Applications.available_transitions(application)
      )
    end
  end

  def create(conn, params) do
    with {:ok, application} <- Applications.create(params, "public_api") do
      conn
      |> put_status(:created)
      |> render(:show, application: application)
    end
  end

  def update_state(conn, %{"id" => application_id} = params) do
    with {:ok, application} <-
           Applications.update_state(application_id, params, conn.assigns.current_user) do
      render(conn, :show, application: application)
    end
  end
end
