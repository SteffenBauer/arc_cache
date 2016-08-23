defmodule ArcCacheNew do
  @moduledoc """
  This modules implements an ARC cache as described in:

  http://www.cs.cmu.edu/~15-440/READINGS/megiddo-computer2004.pdf

  For using it, you need to start it:

      iex> ArcCache.start_link(:my_cache, 1000)

  Or add it to your supervisor tree, like: `worker(ArcCache, [:my_cache, 1000])`

  ## Using

      iex> ArcCache.start_link(:my_cache, 1000)
      {:ok, #PID<0.60.0>}

      iex> ArcCache.put(:my_cache, "id", "value")
      :ok

      iex> ArcCache.get(:my_cache, "id", touch = false)
      "value"
  """
  use GenServer
  @table ArcCacheNew
  defstruct t1: nil, t2: nil, b1: nil, b2: nil, size: 0, target: 0

  #
  # -- Public API --
  #

  @doc """
  Creates an ARC cache of the given size as part of a supervision tree with a registered name
  """
  def start_link(name, size) do
    Agent.start_link(__MODULE__, :init, [name |> to_string, size], [name: name])
  end

  @doc """
  Stores the given `value` under `key` in `cache`. If `cache` already has `key`, the stored
  `value` is replaced by the new one. This rebalances the ARC tables.
  """
  def put(name, key, value) do
    Agent.update(name, __MODULE__, :handle_put, [key, value])
  end

  @doc """
  Returns the `value` associated with `key` in `cache`. If `cache` does not contain `key`,
  returns nil. `touch` defines if the ARC tables should be rebalanced.
  """
  def get(name, key, touch \\ true) do
    Agent.get(name, __MODULE__, :handle_get, [key, touch])
  end

  @doc """
  Removes the entry stored under the given `key` from cache.
  """
  def delete(name, key) do
    Agent.get(name, __MODULE__, :handle_delete, [key])
  end

  @doc """
  Returns the contents of an ARC table or the current target value.
  Only for debugging / testing uses.
  """
  def debug(name, table) do
    Agent.get(name, __MODULE__, :handle_debug, [table])
  end

  #
  # -- Callback functions --
  #

  @doc false
  def handle_debug(state, :target), do: Map.get(state, :target)
  def handle_debug(state, table), do: get_all(state, table)

  @doc false
  def handle_delete(state, key) do
    with nil <- do_delete(state.t1, key),
         nil <- do_delete(state.t2, key),
         nil <- do_delete(state.b1, key),
         nil <- do_delete(state.b2, key),
    do: nil
  end

  @doc false
  defp do_delete(table, key) do
    entry = :ets.lookup(table.data, key)
    case entry do
      [{^key, uniq, _}] ->
        :ets.delete(table.meta, uniq)
        :ets.delete(table.data, key)
        :ok
      [] -> nil
    end
  end

  @doc false
  defp get_all(state, table) do
    meta = state |> Map.get(table) |> Map.get(:meta)
    data = state |> Map.get(table) |> Map.get(:data)
    get_all(meta, data, :ets.first(meta), [])
  end
  defp get_all(meta, data, lastresult, result) do
    case lastresult do
      :"$end_of_table" -> result
      uniq ->
        [{^uniq, key}] = :ets.lookup(meta, uniq)
        case :ets.lookup(data, key) do
          [{^key, ^uniq, value}] ->
            get_all(meta, data, :ets.next(meta, uniq), result ++ [{key, value}])
          [{^key, ^uniq}] ->
            get_all(meta, data, :ets.next(meta, uniq), result ++ [key])
        end
    end
  end

  @doc false
  def init(name, size) do
    t1data = :"#{name}_t1data"
    t1meta = :"#{name}_t1meta"
    b1data = :"#{name}_b1data"
    b1meta = :"#{name}_b1meta"
    t2data = :"#{name}_t2data"
    t2meta = :"#{name}_t2meta"
    b2data = :"#{name}_b2data"
    b2meta = :"#{name}_b2meta"
    for table <- [t1data, t2data, b1data, b2data], do: make_datatable(table)
    for table <- [t1meta, t2meta, b1meta, b2meta], do: make_metatable(table)
    t1 = %{meta: t1meta, data: t1data}
    t2 = %{meta: t2meta, data: t2data}
    b1 = %{meta: b1meta, data: b1data}
    b2 = %{meta: b2meta, data: b2data}
    %ArcCacheNew{t1: t1, t2: t2, b1: b1, b2: b2, size: size, target: 0}
  end

  defp make_datatable(table) do
    :ets.new(table, [:named_table, :public, {:read_concurrency, true}])
  end
  defp make_metatable(table) do
    :ets.new(table, [:named_table, :ordered_set])
  end

  defp datatable(state, table) do
    state |> Map.get(table) |> Map.get(:data)
  end
  defp metatable(state, table) do
    state |> Map.get(table) |> Map.get(:meta)
  end

  @doc false
  def handle_get(state, key, touch) do
    with nil <- get_from_table(state, :t1, key, touch, &move_t1_to_t2/4),
         nil <- get_from_table(state, :t2, key, touch, &move_t2_to_t2/4),
    do: nil
  end

  defp get_from_table(state, table, key, touch, action) do
    case state |> datatable(table) |> :ets.lookup(key) do
      [{^key, uniq, value}] ->
        touch && action.(state, key, uniq, value)
        value
      [] -> nil
    end
  end

  @doc false
  def handle_put(state, key, value) do
    case do_lookup(state, key) do
      {:t1, t1_uniq} -> move_t1_to_t2(state, key, t1_uniq, value)
      {:t2, t2_uniq} -> move_t2_to_t2(state, key, t2_uniq, value)
      {:b1, b1_uniq} -> do_in_b1(state, b1_uniq, key, value)
      {:b2, b2_uniq} -> do_in_b2(state, b2_uniq, key, value)
      true           -> put_to_mru(state |> adjust, :t1, key, value)
    end
  end

  defp do_lookup(state, key) do
    with {:t2, nil} <- {:t2, lookup(state.t2.data, key)},
         {:t1, nil} <- {:t1, lookup(state.t1.data, key)},
         {:b2, nil} <- {:b2, lookup(state.b2.data, key)},
         {:b1, nil} <- {:b1, lookup(state.b1.data, key)},
    do: true
  end

  defp lookup(table, key) do
    case :ets.lookup(table, key) do
      []                     -> nil
      [{^key, uniq, _value}] -> uniq
      [{^key, uniq}]         -> uniq
    end
  end

  def delete(state, table, uniq, key) do
    state |> metatable(table) |> :ets.delete(uniq)
    state |> datatable(table) |> :ets.delete(key)
  end

  defp do_in_b1(state, uniq, key, value) do
    state = state |> target(:increase) |> replace(false)
    delete(state, :b1, uniq, key)
    put_to_mru(state, :t2, key, value)
    state
  end

  defp do_in_b2(state, uniq, key, value) do
    state = state |> target(:decrease) |> replace(true)
    delete(state, :b2, uniq, key)
    put_to_mru(state, :t2, key, value)
    state
  end

  defp move_t1_to_t2(state, key, uniq, value) do
    delete(state, :t1, uniq, key)
    new_uniq = :erlang.unique_integer([:monotonic])
    :ets.insert(datatable(state, :t2), {key, new_uniq, value})
    :ets.insert(metatable(state, :t2), {new_uniq, key})
    state
  end

  defp move_t2_to_t2(state, key, uniq, value) do
    new_uniq = :erlang.unique_integer([:monotonic])
    :ets.delete(metatable(state, :t2), uniq)
    :ets.insert(metatable(state, :t2), {new_uniq, key})
    :ets.update_element(datatable(state, :t2), key,  {2, new_uniq})
    :ets.update_element(datatable(state, :t2), key,  {3, value})
    state
  end

  defp put_to_mru(state, table, key, value) do
    new_uniq = :erlang.unique_integer([:monotonic])
    :ets.insert(datatable(state, table), {key, new_uniq, value})
    :ets.insert(metatable(state, table), {new_uniq, key})
    state
  end

  defp target(state, action) do
    len_b1 = :ets.info(datatable(state, :b1), :size)
    len_b2 = :ets.info(datatable(state, :b2), :size)
    new_target = case action do
      :increase -> min(state.size, state.target + max((len_b2/len_b1) |> Float.floor |> round, 1))
      :decrease -> max(0,          state.target - max((len_b1/len_b2) |> Float.floor |> round, 1))
    end
    %ArcCacheNew{state | target: new_target}
  end

  defp replace(state, was_in_b2) do
    len_t1 = :ets.info(datatable(state, :t1), :size)
    if(len_t1 >= 1 and ((was_in_b2 and len_t1 == state.target) or (len_t1 > state.target))) do
      ghost(state, :t1, :b1)
    else
      ghost(state, :t2, :b2)
    end
    state
  end

  defp ghost(state, from, to) do
    case state |> metatable(from) |> :ets.first do
      :"$end_of_table" -> nil
      uniq -> [{^uniq, key}] = state |> metatable(from) |> :ets.take(uniq)
              state |> datatable(from) |> :ets.delete(key)
              state |> metatable(to) |> :ets.insert({uniq, key})
              state |> datatable(to) |> :ets.insert({key, uniq})
    end
  end

  defp remove_lru(state, table) do
    case state |> metatable(table) |> :ets.first do
      :"$end_of_table" -> nil
      uniq -> [{^uniq, key}] = state |> metatable(table) |> :ets.take(uniq)
              state |> datatable(table) |> :ets.take(key)
    end
  end

  defp adjust(state) do
    len_t1 = :ets.info(datatable(state, :t1), :size)
    len_t2 = :ets.info(datatable(state, :t2), :size)
    len_b1 = :ets.info(datatable(state, :b1), :size)
    len_b2 = :ets.info(datatable(state, :b2), :size)
    len_l1 = len_t1 + len_b1
    len_l2 = len_t2 + len_b2
    cond do
      len_l1 >= state.size ->
        if(len_t1 < state.size) do
          remove_lru(state, :b1)
          state |> replace(false)
        else
          remove_lru(state, :t1)
          state
        end
      len_l1 < state.size and len_l1 + len_l2 >= state.size ->
        if(len_l1 + len_l2 >= 2*state.size) do
          remove_lru(state, :b2)
        end
        state |> replace(false)
      true -> state
    end
  end

end
