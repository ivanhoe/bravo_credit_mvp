defmodule BravoCredit.Cache do
  @moduledoc """
  A simple, fast ETS-based cache for the application, used primarily for
  country configurations. Starts a named ETS table on boot.
  """
  use GenServer

  @table_name :bravo_credit_cache

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  @impl true
  def init(:ok) do
    :ets.new(@table_name, [
      :set,
      :public,
      :named_table,
      read_concurrency: true,
      write_concurrency: true
    ])

    {:ok, %{}}
  end

  @doc """
  Gets a value from the cache. Returns `{:ok, value}` or `:error`.
  """
  def get(key) do
    case :ets.lookup(@table_name, key) do
      [{^key, value}] -> {:ok, value}
      [] -> :error
    end
  end

  @doc """
  Puts a value into the cache.
  """
  def put(key, value) do
    :ets.insert(@table_name, {key, value})
    :ok
  end
end
