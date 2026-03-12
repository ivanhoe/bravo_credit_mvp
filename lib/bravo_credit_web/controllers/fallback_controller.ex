defmodule BravoCreditWeb.FallbackController do
  @moduledoc """
  Translates structured domain errors into the API's canonical JSON envelope.
  """

  use BravoCreditWeb, :controller

  alias BravoCredit.Error
  alias BravoCredit.Errors

  def call(conn, {:error, %Error{} = error}) do
    conn
    |> put_status(error.http_status || 500)
    |> json(%{
      error: %{
        code: error.code,
        message: error.message,
        details: error.details
      }
    })
  end

  def call(conn, {:error, reason}) do
    error = Errors.internal_error("Unhandled controller error", %{reason: inspect(reason)})

    conn
    |> put_status(error.http_status)
    |> json(%{
      error: %{
        code: error.code,
        message: error.message,
        details: error.details
      }
    })
  end
end
