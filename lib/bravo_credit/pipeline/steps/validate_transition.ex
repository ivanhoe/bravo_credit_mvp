defmodule BravoCredit.Pipeline.Steps.ValidateTransition do
  @moduledoc """
  Validates state transitions according to the application's state machine.
  """

  @behaviour BravoCredit.Pipeline.Step

  alias BravoCredit.Errors

  @allowed_transitions %{
    pending: [:provider_processing, :cancelled],
    provider_processing: [:evaluating, :cancelled],
    evaluating: [:approved, :rejected, :in_review],
    in_review: [:approved, :rejected, :cancelled],
    approved: [:cancelled]
  }

  @impl true
  def call(%{application: application, raw_params: raw_params} = context) do
    with {:ok, target_state} <- parse_target_state(raw_params),
         :ok <- ensure_transition_allowed(application.status, target_state) do
      {:ok, %{context | decision: %{target_state: target_state}}}
    end
  end

  defp parse_target_state(raw_params) do
    raw_state = Map.get(raw_params, "state") || Map.get(raw_params, :state)

    if is_binary(raw_state) do
      try do
        normalized_state =
          raw_state
          |> String.trim()
          |> String.downcase()
          |> String.to_existing_atom()

        {:ok, normalized_state}
      rescue
        ArgumentError ->
          {:error, Errors.invalid_params(%{fields: %{state: ["is invalid"]}})}
      end
    else
      {:error, Errors.invalid_params(%{fields: %{state: ["must be present"]}})}
    end
  end

  defp ensure_transition_allowed(current_state, target_state) do
    allowed_states = Map.get(@allowed_transitions, current_state, [])

    if target_state in allowed_states do
      :ok
    else
      {:error, Errors.invalid_transition(current_state, target_state)}
    end
  end
end
