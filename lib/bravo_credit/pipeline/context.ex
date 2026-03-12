defmodule BravoCredit.Pipeline.Context do
  @moduledoc """
  Stable context passed through pipeline steps.
  """

  alias BravoCredit.Applications.Application
  alias BravoCredit.Applications.CreateInput
  alias BravoCredit.Countries.CountryConfig

  @enforce_keys [:request_id, :actor, :raw_params]
  defstruct request_id: nil,
            actor: nil,
            raw_params: %{},
            input: nil,
            country_config: nil,
            application_changeset: nil,
            application: nil,
            provider_data: nil,
            decision: nil,
            events: [],
            errors: []

  @type t :: %__MODULE__{
          request_id: Ecto.UUID.t(),
          actor: term(),
          raw_params: map(),
          input: CreateInput.t() | nil,
          country_config: CountryConfig.t() | nil,
          application_changeset: Ecto.Changeset.t() | nil,
          application: Application.t() | nil,
          provider_data: map() | nil,
          decision: map() | nil,
          events: list(),
          errors: [BravoCredit.Error.t()]
        }
end
