defmodule BravoCreditWeb.ApplicationJSON do
  @moduledoc """
  JSON rendering helpers for application resources.
  """

  alias BravoCredit.Applications.Application

  def index(%{applications: applications}) do
    %{data: Enum.map(applications, &data/1)}
  end

  def show(%{application: application}) do
    %{data: data(application)}
  end

  defp data(%Application{} = application) do
    %{
      id: application.id,
      country_code: application.country_code,
      status: application.status,
      risk_status: application.risk_status,
      risk_score: application.risk_score,
      amount: application.amount,
      monthly_income: application.monthly_income,
      requested_at: application.requested_at,
      lock_version: application.lock_version
    }
  end
end
