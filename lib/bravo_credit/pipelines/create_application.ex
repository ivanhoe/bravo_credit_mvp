defmodule BravoCredit.Pipelines.CreateApplication do
  @moduledoc """
  Synchronous pipeline for validating and creating a credit application request.
  """

  alias BravoCredit.Errors
  alias BravoCredit.Pipeline.Context
  alias BravoCredit.Pipeline.Runner
  alias BravoCredit.Pipeline.Steps

  @steps [
    Steps.ValidateParams,
    Steps.ResolveCountryConfig,
    Steps.ValidateDocument,
    Steps.ValidateInitialRules,
    Steps.BuildApplicationChangeset,
    Steps.PersistApplication
  ]

  @spec call(map(), term()) :: {:ok, Context.t()} | {:error, BravoCredit.Error.t()}
  def call(params, actor \\ "public_api")

  def call(params, actor) when is_map(params) do
    %Context{
      request_id: Ecto.UUID.generate(),
      actor: actor,
      raw_params: params
    }
    |> Runner.run(@steps)
  end

  def call(_params, _actor) do
    {:error, Errors.invalid_params(%{fields: %{base: ["must be a map"]}})}
  end
end
