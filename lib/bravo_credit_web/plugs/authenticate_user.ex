defmodule BravoCreditWeb.Plugs.AuthenticateUser do
  @moduledoc """
  Authenticates API requests using a Bearer JWT and assigns the current user.
  """

  import Plug.Conn

  import Phoenix.Controller, only: [json: 2]

  alias BravoCredit.Accounts.Guardian
  alias BravoCredit.Errors

  def init(opts), do: opts

  def call(conn, _opts) do
    with ["Bearer " <> token] <- get_req_header(conn, "authorization"),
         {:ok, claims} <- Guardian.decode_and_verify(token),
         {:ok, user} <- Guardian.resource_from_claims(claims) do
      assign(conn, :current_user, user)
    else
      _error ->
        conn
        |> Plug.Conn.put_status(:unauthorized)
        |> json(%{
          error: %{
            code: Errors.unauthenticated().code,
            message: Errors.unauthenticated().message,
            details: Errors.unauthenticated().details
          }
        })
        |> halt()
    end
  end
end
