defmodule BravoCredit.Applications.Queries do
  @moduledoc """
  Read models and filtering logic for application listing and retrieval.
  """

  import Ecto.Query

  alias BravoCredit.Accounts.User
  alias BravoCredit.Applications.Application
  alias BravoCredit.Errors
  alias BravoCredit.Repo

  @spec get(Ecto.UUID.t()) :: Application.t() | nil
  def get(application_id), do: Repo.get(Application, application_id)

  @spec list(User.t(), map()) :: {:ok, [Application.t()]} | {:error, BravoCredit.Error.t()}
  def list(%User{} = user, params \\ %{}) when is_map(params) do
    with {:ok, countries} <- resolve_countries(user, params),
         {:ok, status_filter} <-
           parse_status(Map.get(params, "status") || Map.get(params, :status)),
         {:ok, date_from} <-
           parse_date_boundary(Map.get(params, "date_from") || Map.get(params, :date_from), :from),
         {:ok, date_to} <-
           parse_date_boundary(Map.get(params, "date_to") || Map.get(params, :date_to), :to) do
      query =
        Application
        |> where([application], application.country_code in ^countries)
        |> maybe_filter_status(status_filter)
        |> maybe_filter_date_from(date_from)
        |> maybe_filter_date_to(date_to)
        |> order_by([application], desc: application.requested_at)

      {:ok, Repo.all(query)}
    end
  end

  defp resolve_countries(%User{country_access: country_access}, params) do
    case Map.get(params, "country") || Map.get(params, :country) do
      nil ->
        {:ok, country_access}

      country_code when is_binary(country_code) ->
        normalized_country_code = String.trim(country_code) |> String.upcase()

        if normalized_country_code in country_access do
          {:ok, [normalized_country_code]}
        else
          {:error, Errors.forbidden_country(normalized_country_code)}
        end
    end
  end

  defp parse_status(nil), do: {:ok, nil}

  defp parse_status(status) when is_binary(status) do
    normalized_status =
      status
      |> String.trim()
      |> String.downcase()
      |> String.to_existing_atom()

    if normalized_status in Ecto.Enum.values(Application, :status) do
      {:ok, normalized_status}
    else
      {:error, Errors.invalid_params(%{fields: %{status: ["is invalid"]}})}
    end
  rescue
    ArgumentError ->
      {:error, Errors.invalid_params(%{fields: %{status: ["is invalid"]}})}
  end

  defp parse_date_boundary(nil, _position), do: {:ok, nil}

  defp parse_date_boundary(value, position) when is_binary(value) do
    case Date.from_iso8601(String.trim(value)) do
      {:ok, date} ->
        {:ok, to_datetime_boundary(date, position)}

      {:error, _reason} ->
        {:error, Errors.invalid_params(%{fields: %{date: ["must be ISO8601 date"]}})}
    end
  end

  defp to_datetime_boundary(date, :from), do: DateTime.new!(date, ~T[00:00:00], "Etc/UTC")
  defp to_datetime_boundary(date, :to), do: DateTime.new!(date, ~T[23:59:59], "Etc/UTC")

  defp maybe_filter_status(query, nil), do: query

  defp maybe_filter_status(query, status),
    do: where(query, [application], application.status == ^status)

  defp maybe_filter_date_from(query, nil), do: query

  defp maybe_filter_date_from(query, date_from) do
    where(query, [application], application.requested_at >= ^date_from)
  end

  defp maybe_filter_date_to(query, nil), do: query

  defp maybe_filter_date_to(query, date_to) do
    where(query, [application], application.requested_at <= ^date_to)
  end
end
