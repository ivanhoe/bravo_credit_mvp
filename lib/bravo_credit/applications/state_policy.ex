defmodule BravoCredit.Applications.StatePolicy do
  @moduledoc """
  Resolves per-country state transition policies with a safe default.
  """

  alias BravoCredit.Countries.CountryConfig
  alias BravoCredit.Countries.Registry

  @default_transitions %{
    pending: [:provider_processing, :cancelled],
    provider_processing: [:evaluating, :cancelled],
    evaluating: [:approved, :rejected, :in_review],
    in_review: [:approved, :rejected, :cancelled],
    approved: [:cancelled],
    rejected: [],
    cancelled: []
  }

  @spec transitions_for(String.t() | CountryConfig.t()) :: %{optional(atom()) => [atom()]}
  def transitions_for(%CountryConfig{state_transitions: state_transitions}) do
    Map.merge(@default_transitions, state_transitions || %{})
  end

  def transitions_for(country_code) when is_binary(country_code) do
    case Registry.get(country_code) do
      {:ok, country_config} -> transitions_for(country_config)
      {:error, _error} -> @default_transitions
    end
  end

  @spec available_transitions(String.t() | CountryConfig.t(), atom()) :: [atom()]
  def available_transitions(country_code_or_config, current_state) when is_atom(current_state) do
    country_code_or_config
    |> transitions_for()
    |> Map.get(current_state, [])
  end

  @spec allowed?(String.t() | CountryConfig.t(), atom(), atom()) :: boolean()
  def allowed?(country_code_or_config, from_state, to_state)
      when is_atom(from_state) and is_atom(to_state) do
    to_state in available_transitions(country_code_or_config, from_state)
  end
end
