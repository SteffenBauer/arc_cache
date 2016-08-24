defmodule RandomCache do
  @moduledoc """
  This modules implements a simple cache, using 1 ets table for it.

  For using it, you need to start it:

      iex> RandomCache.start_link(:my_cache, 1000)

  Or add it to your supervisor tree, like: `worker(RandomCache, [:my_cache, 1000])`

  ## Using

      iex> RandomCache.start_link(:my_cache, 1000)
      {:ok, #PID<0.60.0>}

      iex> RandomCache.put(:my_cache, "id", "value")
      :ok

      iex> RandomCache.get(:my_cache, "id", touch = false)
      "value"

  ## Design

  ets table to save the key values pairs. Once the cache is full, random elements get evicted.
  """
  use GenServer
  @table RandomCache

  defstruct table: nil, size: 0

  @doc """
  Creates a Rand Cache of the given size as part of a supervision tree with a registered name
  """
  def start_link(name, size) do
    Agent.start_link(__MODULE__, :init, [name, size], [name: name])
  end

  @doc """
  Stores the given `value` under `key` in `cache`. If `cache` already has `key`, the stored
  `value` is replaced by the new one.
  """
  def put(name, key, value), do: Agent.get(name, __MODULE__, :handle_put, [key, value])

  @doc """
  Updates a `value` in `cache`. If `key` is not present in `cache` then nothing is done.
  The function assumes, that the element exists in a cache.
  """
  def update(name, key, value, _touch \\ true) do
    :ets.update_element(name, key, {2, value})
    :ok
  end

  @doc """
  Returns the `value` associated with `key` in `cache`. If `cache` does not contain `key`,
  returns nil.
  """
  def get(name, key, _touch \\ true) do
    case :ets.lookup(name, key) do
      [{_, value}] -> value
      []           -> nil
    end
  end

  @doc """
  Removes the entry stored under the given `key` from cache.
  """
  def delete(name, key) do #do: Agent.get(name, __MODULE__, :handle_delete, [key])
    :ets.delete(name, key)
    :ok
  end

  @doc false
  def init(name, size) do
    :ets.new(name, [:named_table, :public, :ordered_set, {:read_concurrency, true}])
    %RandomCache{table: name, size: size}
  end

  @doc false
  def handle_put(state = %{table: table}, key, value) do
    :ets.insert(table, {key, value})
    clean_oversize(state)
    :ok
  end

  defp clean_oversize(%{table: table, size: size}) do
    table_size = :ets.info(table, :size)
    if table_size > size do
      del_pos = :rand.uniform(table_size)-1
      [{del_key, _}] = :ets.slot(table, del_pos)
      :ets.delete(table, del_key)
      true
    else nil end
  end
end
