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
  defstruct t1data: nil, t1meta: nil, b1keys: nil, b1meta: nil,
            t2data: nil, t2meta: nil, b2keys: nil, b2meta: nil,
            size: 0, target: 0

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
  def handle_debug(state, :t1), do: get_all(state.t1meta, state.t1data)
  def handle_debug(state, :t2), do: get_all(state.t2meta, state.t2data)
  def handle_debug(state, :b1), do: get_all(state.b1meta, state.b1keys)
  def handle_debug(state, :b2), do: get_all(state.b2meta, state.b2keys)

  defp get_all(meta, data) do
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

  @doc false
  def init(name, size) do
    t1data = :"#{name}_t1data"
    t1meta = :"#{name}_t1meta"
    b1keys = :"#{name}_b1keys"
    b1meta = :"#{name}_b1meta"
    t2data = :"#{name}_t2data"
    t2meta = :"#{name}_t2meta"
    b2keys = :"#{name}_b2keys"
    b2meta = :"#{name}_b2meta"
    for table <- [t1data, t2data, b1keys, b2keys], do: make_datatable(table)
    for table <- [t1meta, t2meta, b1meta, b2meta], do: make_metatable(table)
    %ArcCacheNew{t1data: t1data, t1meta: t1meta, b1keys: b1keys, b1meta: b1meta,
                 t2data: t2data, t2meta: t2meta, b2keys: b2keys, b2meta: b2meta,
                 size: size, target: 0}
  end

  defp make_datatable(table) do
    :ets.new(table, [:named_table, :public, {:read_concurrency, true}])
  end
  defp make_metatable(table) do
    :ets.new(table, [:named_table, :ordered_set])
  end

  @doc false
  def handle_get(state, key, touch) do
    with nil <- get_from_table(state, :t1data, key, touch, &move_t1_to_t2/4),
         nil <- get_from_table(state, :t2data, key, touch, &move_t2_to_t2/4),
    do: nil
  end

  defp get_from_table(state, table, key, touch, action) do
    case :ets.lookup(Map.get(state, table), key) do
      [{^key, uniq, value}] ->
        touch && action.(state, key, uniq, value)
        value
      [] -> nil
    end
  end

  @doc false
  def handle_put(state, key, value) do
#    with nil <- lookup(:t1data, state, key),
#         nil <- lookup(:t2data, state, key),
#         nil <- lookup(:b1keys, state, key),
#         nil <- lookup(:b2keys, state, key),
#    do:

    {t1_uniq, t1_value} = lookup_table(:t1data, state, key)
    {t2_uniq, t2_value} = lookup_table(:t2data, state, key)
    b1_uniq = lookup_ghost(:b1keys, state, key)
    b2_uniq = lookup_ghost(:b2keys, state, key)
    cond do
      b1_uniq  != nil -> do_in_b1(state, b1_uniq, key, value)
      b2_uniq  != nil -> do_in_b2(state, b2_uniq, key, value)
      t1_value != nil -> move_t1_to_t2(state, key, t1_uniq, value)
      t2_value != nil -> move_t2_to_t2(state, key, t2_uniq, value)
      true            -> put_to_l1_mru(state |> adjust, key, value)
    end
  end

  defp lookup(table, key) do
    case :ets.lookup(table, key) do
      []                    -> nil
      [{^key, uniq, value}] -> {uniq, value}
      [{^key, uniq}]        -> uniq
    end
  end

  defp lookup_table(table, state, key) do
    case :ets.lookup(Map.get(state,table), key) do
      []                    -> {nil, nil}
      [{^key, uniq, value}] -> {uniq, value}
    end
  end

  defp lookup_ghost(table, state, key) do
    case :ets.lookup(Map.get(state,table), key) do
      []             -> nil
      [{^key, uniq}] -> uniq
    end
  end

  defp do_in_b1(state, uniq, key, value) do
    state = state |> increase_target |> replace(false)
    :ets.delete(state.b1meta, uniq)
    :ets.delete(state.b1keys, key)
    put_to_l2_mru(state, key, value)
    state
  end

  defp do_in_b2(state, uniq, key, value) do
    state = state |> decrease_target |> replace(true)
    :ets.delete(state.b2meta, uniq)
    :ets.delete(state.b2keys, key)
    put_to_l2_mru(state, key, value)
    state
  end

  defp move_t1_to_t2(state, key, uniq, value) do
    :ets.delete(state.t1meta, uniq)
    :ets.delete(state.t1data, key)
    new_uniq = :erlang.unique_integer([:monotonic])
    :ets.insert(state.t2data, {key, new_uniq, value})
    :ets.insert(state.t2meta, {new_uniq, key})
    state
  end

  defp move_t2_to_t2(state, key, uniq, value) do
    new_uniq = :erlang.unique_integer([:monotonic])
    :ets.delete(state.t2meta, uniq)
    :ets.insert(state.t2meta, {new_uniq, key})
    :ets.update_element(state.t2data, key,  {2, new_uniq})
    :ets.update_element(state.t2data, key,  {3, value})
    state
  end

  defp put_to_l1_mru(state, key, value) do
    new_uniq = :erlang.unique_integer([:monotonic])
    :ets.insert(state.t1data, {key, new_uniq, value})
    :ets.insert(state.t1meta, {new_uniq, key})
    state
  end

  defp put_to_l2_mru(state, key, value) do
    new_uniq = :erlang.unique_integer([:monotonic])
    :ets.insert(state.t2data, {key, new_uniq, value})
    :ets.insert(state.t2meta, {new_uniq, key})
    state
  end

  defp increase_target(state) do
    len_b1 = :ets.info(state.b1keys, :size)
    len_b2 = :ets.info(state.b2keys, :size)
    new_target = min(state.size, state.target + max((len_b2/len_b1) |> Float.floor |> round, 1))
    %ArcCacheNew{state | target: new_target}
  end

  defp decrease_target(state) do
    len_b1 = :ets.info(state.b1keys, :size)
    len_b2 = :ets.info(state.b2keys, :size)
    new_target = max(0, state.target - max((len_b1/len_b2) |> Float.floor |> round, 1))
    %ArcCacheNew{state | target: new_target}
  end

  defp replace(state, was_in_b2) do
    len_t1 = :ets.info(state.t1data, :size)
    if(len_t1 >= 1 and ((was_in_b2 and len_t1 == state.target) or (len_t1 > state.target))) do
      ghost(state.t1meta, state.t1data, state.b1meta, state.b1keys)
    else
      ghost(state.t2meta, state.t2data, state.b2meta, state.b2keys)
    end
    state
  end

  defp ghost(meta_t, data_t, meta_b, keys_b) do
    case :ets.first(meta_t) do
      :"$end_of_table" -> nil
      uniq -> [{^uniq, key}] = :ets.take(meta_t, uniq)
              :ets.delete(data_t, key)
              :ets.insert(meta_b, {uniq, key})
              :ets.insert(keys_b, {key, uniq})
    end
  end

  defp remove_lru(meta, data) do

  end

  defp adjust(state) do
    len_t1 = :ets.info(state.t1data, :size)
    len_t2 = :ets.info(state.t2data, :size)
    len_b1 = :ets.info(state.b1keys, :size)
    len_b2 = :ets.info(state.b2keys, :size)
    len_l1 = len_t1 + len_b1
    len_l2 = len_t2 + len_b2
    cond do
      len_l1 >= state.size ->
        if(len_t1 < state.size) do
          case :ets.first(state.b1meta) do
            :"$end_of_table" -> nil
            uniq -> [{^uniq, key}]  = :ets.take(state.b1meta, uniq)
                    [{^key, ^uniq}] = :ets.take(state.b1keys, key)
          end
          state |> replace(false)
        else
          case :ets.first(state.t1meta) do
            :"$end_of_table" -> nil
            uniq -> [{^uniq, key}]         = :ets.take(state.t1meta, uniq)
                    [{^key, ^uniq, _value}] = :ets.take(state.t1data, key)
          end
          state
        end
      len_l1 < state.size and len_l1 + len_l2 >= state.size ->
        if(len_l1 + len_l2 >= 2*state.size) do
          case :ets.first(state.b2meta) do
            :"$end_of_table" -> nil
            uniq -> [{^uniq, key}]  = :ets.take(state.b2meta, uniq)
                    [{^key, ^uniq}] = :ets.take(state.b2keys, key)
          end
        end
        state |> replace(false)
      true -> state
    end
  end

end
