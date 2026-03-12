defmodule BravoCredit.Pipeline.Runner do
  @moduledoc """
  Sequentially executes pipeline steps and annotates structured errors with their origin.
  """

  alias BravoCredit.Error
  alias BravoCredit.Errors
  alias BravoCredit.Pipeline.Context

  @spec run(Context.t(), [module()]) :: {:ok, Context.t()} | {:error, Error.t()}
  def run(%Context{} = context, steps) when is_list(steps) do
    Enum.reduce_while(steps, {:ok, context}, fn step, {:ok, ctx} ->
      case step.call(ctx) do
        {:ok, %Context{} = next_ctx} ->
          {:cont, {:ok, next_ctx}}

        {:error, %Error{} = error} ->
          {:halt, {:error, Errors.with_step(error, step_name(step))}}
      end
    end)
  end

  defp step_name(step) do
    step
    |> Module.split()
    |> List.last()
    |> Macro.underscore()
    |> String.to_atom()
  end
end
