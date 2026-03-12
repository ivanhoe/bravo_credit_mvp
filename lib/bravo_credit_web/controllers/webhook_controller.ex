defmodule BravoCreditWeb.WebhookController do
  @moduledoc """
  Public JSON API endpoints for receiving provider callbacks.
  """

  use BravoCreditWeb, :controller

  alias BravoCredit.Webhooks

  action_fallback BravoCreditWeb.FallbackController

  def provider(conn, params) do
    params =
      case get_req_header(conn, "x-idempotency-key") do
        [idempotency_key | _rest] -> Map.put_new(params, "idempotency_key", idempotency_key)
        [] -> params
      end

    with {:ok, webhook_event} <- Webhooks.receive_provider(params) do
      conn
      |> put_status(:accepted)
      |> render(:show, webhook_event: webhook_event)
    end
  end
end
