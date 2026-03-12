defmodule BravoCredit.Countries.Registry do
  @moduledoc """
  In-memory registry of validated country configuration loaded at application startup.
  """

  alias BravoCredit.Countries.Loader
  alias BravoCredit.Errors

  @registry_key "country_configs"

  @default_validator_registry %{
    "curp" => BravoCredit.Documents.CURP,
    "cc_basic" => BravoCredit.Documents.CC
  }
  @default_provider_registry %{
    "bank_mx" => BravoCredit.Banking.Providers.MX,
    "bank_co" => BravoCredit.Banking.Providers.CO
  }

  @spec refresh!() :: %{String.t() => BravoCredit.Countries.CountryConfig.t()}
  def refresh! do
    configs = Loader.load!(path(), validator_registry(), provider_registry())
    BravoCredit.Cache.put(@registry_key, configs)
    configs
  end

  @spec all() :: %{String.t() => BravoCredit.Countries.CountryConfig.t()}
  def all do
    case BravoCredit.Cache.get(@registry_key) do
      {:ok, configs} -> configs
      :error -> refresh!()
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
  def validator_registry do
    Application.get_env(:bravo_credit, :country_validator_registry, @default_validator_registry)
  end

  @spec provider_registry() :: %{String.t() => module()}
  def provider_registry do
    Application.get_env(:bravo_credit, :country_provider_registry, @default_provider_registry)
  end

  @spec provider_module(String.t()) :: {:ok, module()} | {:error, BravoCredit.Error.t()}
  def provider_module(adapter) when is_binary(adapter) do
    case Map.fetch(provider_registry(), adapter) do
      {:ok, module} ->
        {:ok, module}

      :error ->
        {:error, Errors.internal_error("Provider adapter is not registered", %{adapter: adapter})}
    end
  end

  @spec path() :: String.t()
  def path, do: Application.fetch_env!(:bravo_credit, :country_config_path)
end
