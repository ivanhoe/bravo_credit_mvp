defmodule BravoCredit.Countries.Validator do
  @moduledoc """
  Validates and normalizes YAML country configuration into structs.
  """

  alias BravoCredit.Countries.CountryConfig
  alias BravoCredit.Countries.CountryConfig.Document
  alias BravoCredit.Countries.CountryConfig.Provider
  alias BravoCredit.Countries.Rule
  alias BravoCredit.Applications.Application, as: CreditApplication

  @allowed_top_level_keys ~w(
    country_code
    country_name
    currency
    document
    rules
    provider
    state_transitions
    review
    metadata
  )
  @allowed_document_keys ~w(type validator)
  @allowed_provider_keys ~w(adapter timeout_ms)
  @allowed_rule_keys ~w(id kind evaluation_phase message threshold amount metadata)
  @state_lookup Enum.into(Ecto.Enum.values(CreditApplication, :status), %{}, fn state ->
                  {Atom.to_string(state), state}
                end)

  @rule_kinds %{
    "max_amount_to_income_ratio" => :max_amount_to_income_ratio,
    "min_income" => :min_income,
    "max_total_debt_to_income_ratio" => :max_total_debt_to_income_ratio
  }

  @evaluation_phases %{
    "initial" => :initial,
    "provider" => :provider
  }

  @spec validate(map(), map(), map()) :: {:ok, CountryConfig.t()} | {:error, String.t()}
  def validate(raw_config, validator_registry, provider_registry) when is_map(raw_config) do
    with :ok <- validate_allowed_keys(raw_config, @allowed_top_level_keys, "country config"),
         {:ok, country_code} <- fetch_required_string(raw_config, "country_code"),
         {:ok, country_name} <- fetch_required_string(raw_config, "country_name"),
         {:ok, currency} <- fetch_required_string(raw_config, "currency"),
         {:ok, document} <- validate_document(raw_config["document"], validator_registry),
         {:ok, rules} <- validate_rules(raw_config["rules"]),
         {:ok, provider} <- validate_provider(raw_config["provider"], provider_registry),
         {:ok, state_transitions} <- validate_state_transitions(raw_config["state_transitions"]),
         {:ok, review} <- validate_optional_map(raw_config["review"], "review"),
         {:ok, metadata} <- validate_optional_map(raw_config["metadata"], "metadata"),
         :ok <- validate_unique_rule_ids(rules) do
      {:ok,
       %CountryConfig{
         country_code: String.upcase(country_code),
         country_name: country_name,
         currency: String.upcase(currency),
         document: document,
         rules: rules,
         provider: provider,
         state_transitions: state_transitions,
         review: review,
         metadata: metadata
       }}
    end
  end

  def validate(_raw_config, _validator_registry, _provider_registry) do
    {:error, "country config must be a map"}
  end

  @spec validate!(map(), map(), map()) :: CountryConfig.t()
  def validate!(raw_config, validator_registry, provider_registry) do
    case validate(raw_config, validator_registry, provider_registry) do
      {:ok, config} -> config
      {:error, reason} -> raise ArgumentError, "invalid country config: #{reason}"
    end
  end

  defp validate_document(nil, _validator_registry), do: {:error, "document section is required"}

  defp validate_document(document, validator_registry) when is_map(document) do
    with :ok <- validate_allowed_keys(document, @allowed_document_keys, "document"),
         {:ok, type} <- fetch_required_string(document, "type"),
         {:ok, validator} <- fetch_required_string(document, "validator"),
         {:ok, validator_module} <-
           resolve_from_registry(validator_registry, validator, "validator") do
      {:ok,
       %Document{
         type: String.upcase(type),
         validator: validator,
         validator_module: validator_module
       }}
    end
  end

  defp validate_document(_document, _validator_registry), do: {:error, "document must be a map"}

  defp validate_provider(nil, _provider_registry), do: {:error, "provider section is required"}

  defp validate_provider(provider, provider_registry) when is_map(provider) do
    with :ok <- validate_allowed_keys(provider, @allowed_provider_keys, "provider"),
         {:ok, adapter} <- fetch_required_string(provider, "adapter"),
         {:ok, adapter_module} <-
           resolve_from_registry(provider_registry, adapter, "provider adapter"),
         {:ok, timeout_ms} <-
           parse_positive_integer(provider["timeout_ms"], "provider.timeout_ms") do
      {:ok,
       %Provider{
         adapter: adapter,
         adapter_module: adapter_module,
         timeout_ms: timeout_ms
       }}
    end
  end

  defp validate_provider(_provider, _provider_registry), do: {:error, "provider must be a map"}

  defp validate_rules(nil), do: {:error, "rules section is required"}
  defp validate_rules(rules) when not is_list(rules), do: {:error, "rules must be a list"}

  defp validate_rules(rules) do
    rules
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, []}, fn {raw_rule, index}, {:ok, acc} ->
      case validate_rule(raw_rule, index) do
        {:ok, rule} -> {:cont, {:ok, [rule | acc]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, validated_rules} -> {:ok, Enum.reverse(validated_rules)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp validate_rule(raw_rule, index) when not is_map(raw_rule) do
    {:error, "rule at index #{index} must be a map"}
  end

  defp validate_rule(raw_rule, index) do
    with :ok <- validate_allowed_keys(raw_rule, @allowed_rule_keys, "rule at index #{index}"),
         {:ok, id} <- fetch_required_string(raw_rule, "id"),
         {:ok, kind} <- validate_rule_kind(raw_rule["kind"]),
         {:ok, evaluation_phase} <- validate_evaluation_phase(raw_rule["evaluation_phase"]),
         {:ok, message} <- fetch_required_string(raw_rule, "message"),
         {:ok, metadata} <- validate_optional_map(raw_rule["metadata"], "rule metadata"),
         {:ok, threshold, amount} <- validate_rule_params(kind, raw_rule) do
      {:ok,
       %Rule{
         id: id,
         kind: kind,
         evaluation_phase: evaluation_phase,
         message: message,
         threshold: threshold,
         amount: amount,
         metadata: metadata
       }}
    end
  end

  defp validate_rule_kind(kind) when is_binary(kind) do
    case Map.fetch(@rule_kinds, kind) do
      {:ok, normalized_kind} -> {:ok, normalized_kind}
      :error -> {:error, "unsupported rule kind: #{inspect(kind)}"}
    end
  end

  defp validate_rule_kind(_kind), do: {:error, "rule kind must be a string"}

  defp validate_evaluation_phase(phase) when is_binary(phase) do
    case Map.fetch(@evaluation_phases, phase) do
      {:ok, normalized_phase} -> {:ok, normalized_phase}
      :error -> {:error, "unsupported evaluation_phase: #{inspect(phase)}"}
    end
  end

  defp validate_evaluation_phase(_phase), do: {:error, "evaluation_phase must be a string"}

  defp validate_rule_params(:max_amount_to_income_ratio, raw_rule) do
    with {:ok, threshold} <- parse_decimal(raw_rule["threshold"], "rule.threshold") do
      {:ok, threshold, nil}
    end
  end

  defp validate_rule_params(:max_total_debt_to_income_ratio, raw_rule) do
    with {:ok, threshold} <- parse_decimal(raw_rule["threshold"], "rule.threshold") do
      {:ok, threshold, nil}
    end
  end

  defp validate_rule_params(:min_income, raw_rule) do
    with {:ok, amount} <- parse_decimal(raw_rule["amount"], "rule.amount") do
      {:ok, nil, amount}
    end
  end

  defp validate_state_transitions(nil), do: {:ok, %{}}

  defp validate_state_transitions(state_transitions) when not is_map(state_transitions) do
    {:error, "state_transitions must be a map"}
  end

  defp validate_state_transitions(state_transitions) do
    Enum.reduce_while(state_transitions, {:ok, %{}}, fn {from_state, raw_targets}, {:ok, acc} ->
      with {:ok, normalized_from_state} <- normalize_state(from_state, "state_transitions key"),
           {:ok, normalized_targets} <- normalize_state_targets(raw_targets, from_state) do
        {:cont, {:ok, Map.put(acc, normalized_from_state, normalized_targets)}}
      else
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp validate_optional_map(nil, _section), do: {:ok, %{}}
  defp validate_optional_map(map, _section) when is_map(map), do: {:ok, map}
  defp validate_optional_map(_map, section), do: {:error, "#{section} must be a map"}

  defp validate_unique_rule_ids(rules) do
    rule_ids = Enum.map(rules, & &1.id)

    if length(rule_ids) == length(Enum.uniq(rule_ids)) do
      :ok
    else
      {:error, "rule ids must be unique per country"}
    end
  end

  defp resolve_from_registry(registry, id, label) do
    case Map.fetch(registry, id) do
      {:ok, module} -> {:ok, module}
      :error -> {:error, "unknown #{label}: #{inspect(id)}"}
    end
  end

  defp validate_allowed_keys(map, allowed_keys, label) do
    unknown_keys = map |> Map.keys() |> Enum.reject(&(&1 in allowed_keys))

    case unknown_keys do
      [] ->
        :ok

      _unknown_keys ->
        {:error, "#{label} contains unsupported keys: #{Enum.join(unknown_keys, ", ")}"}
    end
  end

  defp fetch_required_string(map, key) do
    case Map.get(map, key) do
      value when is_binary(value) ->
        trimmed = String.trim(value)

        if trimmed == "" do
          {:error, "#{key} must be a non-empty string"}
        else
          {:ok, trimmed}
        end

      _other ->
        {:error, "#{key} must be a non-empty string"}
    end
  end

  defp parse_positive_integer(value, field_name) do
    with {:ok, integer} <- parse_integer(value, field_name),
         true <- integer > 0 || {:error, "#{field_name} must be greater than 0"} do
      {:ok, integer}
    end
  end

  defp parse_integer(value, _field_name) when is_integer(value), do: {:ok, value}

  defp parse_integer(value, field_name) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {integer, ""} -> {:ok, integer}
      _other -> {:error, "#{field_name} must be an integer"}
    end
  end

  defp parse_integer(_value, field_name), do: {:error, "#{field_name} must be an integer"}

  defp parse_decimal(nil, field_name), do: {:error, "#{field_name} is required"}

  defp parse_decimal(value, field_name) do
    case Decimal.cast(value) do
      {:ok, decimal} -> {:ok, decimal}
      :error -> {:error, "#{field_name} must be a decimal"}
    end
  end

  defp normalize_state(state, field_name) when is_binary(state) do
    normalized_state =
      state
      |> String.trim()
      |> String.downcase()

    case Map.fetch(@state_lookup, normalized_state) do
      {:ok, value} -> {:ok, value}
      :error -> {:error, "#{field_name} contains unsupported state: #{inspect(state)}"}
    end
  end

  defp normalize_state(_state, field_name), do: {:error, "#{field_name} must be a string"}

  defp normalize_state_targets(raw_targets, from_state) when is_list(raw_targets) do
    raw_targets
    |> Enum.reduce_while({:ok, []}, fn raw_target, {:ok, acc} ->
      case normalize_state(raw_target, "state_transitions.#{from_state}") do
        {:ok, normalized_target} -> {:cont, {:ok, [normalized_target | acc]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, normalized_targets} -> {:ok, Enum.reverse(normalized_targets)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp normalize_state_targets(_raw_targets, from_state) do
    {:error, "state_transitions.#{from_state} must be a list"}
  end
end
