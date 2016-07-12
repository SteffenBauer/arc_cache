defmodule DblTable do
  @moduledoc """
  Implements a key/value store which additionally saves the order of how elements
  were stored.

  Two ETS tables are used to achieve O(log n) access complexity:
  The 'meta' table stores {order, key}, the 'data' table stores {key, order, value}
  """

  defstruct data_table: nil, meta_table: nil

  @doc """
  Creates a key/value - order/key table as part of a supervision tree with a registered name
  """
  def start_link(name) do
    Agent.start_link(__MODULE__, :init, [name], [name: name])
  end

  @doc """
  Returns the `value` associated with `key`. If `key` is not stored returns nil.
  """
  def get(name, key) do
    Agent.get(name, __MODULE__, :handle_get, [key])
  end

  @doc """
  Deletes the entry with `key`. Returns `:ok` when the element was in the store, `nil` otherwise
  """
  def delete(name, key) do
    Agent.get(name, __MODULE__, :handle_delete, [key])
  end

  @doc """
  Updates the `value`. When `key` is not stored do nothing.
  """
  def update(name, key, value) do
    Agent.get(name, __MODULE__, :handle_update, [key, value])
  end

  @doc """
  Put a new `key`/`value` pair into the table at the topmost position.
  An entry already in the store with `key` is deleted.
  """
  def put_to_mru(name, key, value) do
    Agent.get(name, __MODULE__, :handle_put_to_mru, [key, value])
  end

  @doc """
  Returns the number of elements currently stored in the table.
  """
  def size(name) do
    Agent.get(name, __MODULE__, :handle_get_current_size, [])
  end

  @doc """
  Removes the bottom (oldest) element from the table.
  Returns the entry as {key, value}.
  Returns `nil` when the table is empty.
  """
  def pop_lru(name) do
    Agent.get(name, __MODULE__, :handle_pop_lru, [])
  end

  @doc """
  Returns the whole table as a list of {key, value} pairs.
  Only for debugging / testing purposes!
  """
  def get_all(name) do
    Agent.get(name, __MODULE__, :handle_get_all, [])
  end

  @doc false
  def init(name) do
    data_table = :"#{name}_data"
    meta_table = :"#{name}_meta"
    :ets.new(meta_table, [:named_table, :ordered_set])
    :ets.new(data_table, [:named_table, :public, {:read_concurrency, true}])
    %DblTable{meta_table: meta_table, data_table: data_table}
  end

  @doc false
  def handle_get(state, key) do
    case :ets.lookup(state.data_table, key) do
      []                 -> nil
      [{^key, _, value}] -> {key, value}
    end
  end

  @doc false
  def handle_delete(state, key) do
    entry = :ets.lookup(state.data_table, key)
    case entry do
      [{^key, uniq, _}] ->
        :ets.delete(state.meta_table, uniq)
        :ets.delete(state.data_table, key)
        :ok
      [] -> nil
    end
  end

  @doc false
  def handle_update(state, key, value) do
    :ets.update_element(state.data_table, key, {3, value})
  end

  @doc false
  def handle_put_to_mru(state, key, value) do
    handle_delete(state, key)
    uniq = :erlang.unique_integer([:monotonic])
    :ets.insert(state.meta_table, {uniq, key})
    :ets.insert(state.data_table, {key, uniq, value})
    :ok
  end

  @doc false
  def handle_get_current_size(state) do
    :ets.info(state.data_table, :size)
  end

  @doc false
  def handle_pop_lru(state) do
    case :ets.first(state.meta_table) do
      :"$end_of_table" -> nil
      uniq ->
        [{^uniq, key}] = :ets.lookup(state.meta_table, uniq)
        [{^key, ^uniq, value}] = :ets.lookup(state.data_table, key)
        :ets.delete(state.meta_table, uniq)
        :ets.delete(state.data_table, key)
        {key, value}
    end
  end

  @doc false
  def handle_get_all(state) do
    handle_get_all(state, :ets.first(state.meta_table), [])
  end
  def handle_get_all(state, lastresult, result) do
    case lastresult do
      :"$end_of_table" -> result
      uniq ->
        [{^uniq, key}] = :ets.lookup(state.meta_table, uniq)
        [{^key, ^uniq, value}] = :ets.lookup(state.data_table, key)
        handle_get_all(state, :ets.next(state.meta_table, uniq), result ++ [{key, value}])
    end
  end
end
