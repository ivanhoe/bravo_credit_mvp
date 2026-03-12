defmodule BravoCredit.Countries.Registry do
  @moduledoc """
  In-memory registry of validated country configuration loaded at application startup.
  """

  alias BravoCredit.Countries.Loader
  alias BravoCredit.Errors

  @registry_key {__MODULE__, :configs}
  @validator_registry %{
    "curp" => BravoCredit.Documents.CURP,
    "cc_basic" => BravoCredit.Documents.CC
  }
  @provider_registry %{
    "bank_mx" => BravoCredit.Banking.Providers.MX,
    "bank_co" => BravoCredit.Banking.Providers.CO
  }

  @spec refresh!() :: %{String.t() => BravoCredit.Countries.CountryConfig.t()}
  def refresh! do
    configs = Loader.load!(path(), validator_registry(), provider_registry())
    :persistent_term.put(@registry_key, configs)
    configs
  end

  @spec all() :: %{String.t() => BravoCredit.Countries.CountryConfig.t()}
  def all do
    case :persistent_term.get(@registry_key, nil) do
      nil -> refresh!()
      configs -> configs
    end
  end

  @spec get(String.t()) ::
          {:ok, BravoCredit.Countries.CountryConfig.t()} | {:error, BravoCredit.Error.t()}
  def get(country_code) do
    country_code = country_code |> String.trim() |> String.upcase()

    case Map.fetch(all(), country_code) do
      {:ok, config} -> {:ok, config}
      :error -> {:error, Errors.unsupported_country(country_code)}
    end
  end

  @spec get!(String.t()) :: BravoCredit.Countries.CountryConfig.t()
  def get!(country_code) do
    case get(country_code) do
      {:ok, config} -> config
      {:error, error} -> raise ArgumentError, "#{error.code}: #{error.message}"
    end
  end

  @spec validator_registry() :: %{String.t() => module()}
  def validator_registry, do: @validator_registry

  @spec provider_registry() :: %{String.t() => module()}
  def provider_registry, do: @provider_registry

  @spec path() :: String.t()
  def path, do: Application.fetch_env!(:bravo_credit, :country_config_path)
end
