defmodule BravoCredit.Countries.CountryConfig do
  @moduledoc """
  Normalized country configuration used by document validation, rules, and providers.
  """

  alias BravoCredit.Countries.Rule

  defmodule Document do
    @moduledoc false

    @enforce_keys [:type, :validator, :validator_module]
    defstruct [:type, :validator, :validator_module]

    @type t :: %__MODULE__{
            type: String.t(),
            validator: String.t(),
            validator_module: module()
          }
  end

  defmodule Provider do
    @moduledoc false

    @enforce_keys [:adapter, :adapter_module, :timeout_ms]
    defstruct [:adapter, :adapter_module, :timeout_ms]

    @type t :: %__MODULE__{
            adapter: String.t(),
            adapter_module: module(),
            timeout_ms: pos_integer()
          }
  end

  @enforce_keys [:country_code, :country_name, :currency, :document, :rules, :provider]
  defstruct [
    :country_code,
    :country_name,
    :currency,
    :document,
    :rules,
    :provider,
    state_transitions: %{},
    review: %{},
    metadata: %{}
  ]

  @type t :: %__MODULE__{
          country_code: String.t(),
          country_name: String.t(),
          currency: String.t(),
          document: Document.t(),
          rules: [Rule.t()],
          provider: Provider.t(),
          state_transitions: %{optional(atom()) => [atom()]},
          review: map(),
          metadata: map()
        }
end
