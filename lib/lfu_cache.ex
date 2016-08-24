defmodule LfuCache do
  @moduledoc """
  This modules implements a simple LRU cache, using 2 ets tables for it.

  For using it, you need to start it:

      iex> LruCache.start_link(:my_cache, 1000)

  Or add it to your supervisor tree, like: `worker(LruCache, [:my_cache, 1000])`

  ## Using

      iex> LruCache.start_link(:my_cache, 1000)
      {:ok, #PID<0.60.0>}

      iex> LruCache.put(:my_cache, "id", "value")
      :ok

      iex> LruCache.get(:my_cache, "id", touch = false)
      "value"

  ## Design

  First ets table save the key values pairs, the second save order of inserted elements.
  """
  use GenServer
  @table LfuCache

  defstruct table: nil, freq_table: nil, size: 0

  @doc """
  Creates an LRU of the given size as part of a supervision tree with a registered name
  """
  def start_link(name, size) do
    Agent.start_link(__MODULE__, :init, [name, size], [name: name])
  end

  @doc """
  Stores the given `value` under `key` in `cache`. If `cache` already has `key`, the stored
  `value` is replaced by the new one. This updates the order of LFU cache.
  """
  def put(name, key, value), do: Agent.get(name, __MODULE__, :handle_put, [key, value])

  @doc """
  Updates a `value` in `cache`. If `key` is not present in `cache` then nothing is done.
  `touch` defines, if the order in LFU should be actualized. The function assumes, that
  the element exists in a cache.
  """
  def update(name, key, value, touch \\ true) do
    if :ets.update_element(name, key, {3, value}) do
      touch && Agent.get(name, __MODULE__, :handle_touch, [key])
    end
    :ok
  end

  @doc """
  Returns the `value` associated with `key` in `cache`. If `cache` does not contain `key`,
  returns nil. `touch` defines, if the order in LFU should be actualized.
  """
  def get(name, key, touch \\ true) do
    case :ets.lookup(name, key) do
      [{_, _, value}] ->
        touch && Agent.get(name, __MODULE__, :handle_touch, [key])
        value
      [] ->
        nil
    end
  end

  @doc """
  Removes the entry stored under the given `key` from cache.
  """
  def delete(name, key), do: Agent.get(name, __MODULE__, :handle_delete, [key])

  @doc """
  Returns the contents of the LFU Cache.
  Only for debugging / testing uses.
  """
  def debug(name) do
    Agent.get(name, __MODULE__, :handle_debug, [])
  end
  def handle_debug(state) do
    get_all(state, :ets.first(state.freq_table), [])
  end

  @doc false
  defp get_all(state, lastresult, result) do
    case lastresult do
      :"$end_of_table" -> result
      uniq ->
        [{^uniq, key}] = :ets.lookup(state.freq_table, uniq)
        case :ets.lookup(state.table, key) do
          [{^key, ^uniq, value}] ->
            get_all(state, :ets.next(state.freq_table, uniq), result ++ [{key, value}])
        end
    end
  end

  @doc false
  def init(name, size) do
    freq_table = :"#{name}_freq"
    :ets.new(freq_table, [:named_table, :ordered_set])
    :ets.new(name, [:named_table, :public, {:read_concurrency, true}])
    %LfuCache{freq_table: freq_table, table: name, size: size}
  end

  @doc false
  def handle_put(state, key, value) do
    case :ets.lookup(state.table, key) do
      [{_, old_freq, _}] ->
        update_entry(state, key, old_freq, value)
      _ ->
        new_entry(state, key, value)
        clean_oversize(state)
    end
    :ok
  end

  defp new_entry(state, key, value) do
    freq = :rand.uniform
    :ets.insert(state.freq_table, {freq, key})
    :ets.insert(state.table, {key, freq, value})
  end

  defp update_entry(state, key, freq, value) do
    :ets.delete(state.freq_table, freq)
    newfreq = freq + 1.0
    :ets.insert(state.freq_table, {newfreq, key})
    :ets.update_element(state.table, key, [{2, newfreq}, {3, value}])
  end


  @doc false
  def handle_touch(state, key) do
    case :ets.lookup(state.table, key) do
      [{_, old_freq, _}] ->
        new_freq = old_freq + 1.0
        :ets.delete(state.freq_table, old_freq)
        :ets.insert(state.freq_table, {new_freq, key})
        :ets.update_element(state.table, key, [{2, new_freq}])
      _ ->
        nil
    end
    :ok
  end

  @doc false
  def handle_delete(state, key) do
    case :ets.lookup(state.table, key) do
      [{_, old_freq, _}] ->
        :ets.delete(state.freq_table, old_freq)
        :ets.delete(state.table, key)
      _ ->
        nil
    end
    :ok
  end

  defp clean_oversize(%{freq_table: freq_table, table: table, size: size}) do
    if :ets.info(table, :size) > size do
      least_used = :ets.first(freq_table)
      [{_, old_key}] = :ets.lookup(freq_table, least_used)
      :ets.delete(freq_table, least_used)
      :ets.delete(table, old_key)
      true
    else nil end
  end
end
