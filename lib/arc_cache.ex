defmodule ArcCache do
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
  @table ArcCache

  defstruct t1: nil, b1: nil, t2: nil, b2: nil, size: 0, target: 0

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
  Updates a `value` in `cache`. If `key` is not present in `cache` then nothing is done.
  `touch` defines if the ARC tables should be rebalanced. The function assumes that
  the element exists in the cache.
  """
  def update(name, key, value, touch \\ true) do
    Agent.update(name, __MODULE__, :handle_update, [key, value, touch])
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

  @doc false
  def handle_debug(state, :target), do: Map.get(state, :target)
  def handle_debug(state, table), do: DblTable.get_all(Map.get(state, table))

  @doc false
  def init(name, size) do
    {:ok, _} = DblTable.start_link(table_t1 = (name <> "_t1") |> String.to_atom)
    {:ok, _} = DblTable.start_link(table_b1 = (name <> "_b1") |> String.to_atom)
    {:ok, _} = DblTable.start_link(table_t2 = (name <> "_t2") |> String.to_atom)
    {:ok, _} = DblTable.start_link(table_b2 = (name <> "_b2") |> String.to_atom)
    %ArcCache{t1: table_t1, b1: table_b1, t2: table_t2, b2: table_b2, size: size, target: 0}
  end

  def handle_get(state, key, touch) do
      with nil <- get_and_update(state, :t1, key, touch),
           nil <- get_and_update(state, :t2, key, touch),
      do: nil
  end

  defp get_and_update(state, table, key, touch) do
    t = Map.get(state, table)
      case DblTable.get(t, key) do
        nil           -> nil
        {^key, value} -> touch && move_to_t2(state, t, key, value)
                         value
      end
  end

  @doc false
  def handle_put(state, key, value) do
    with false <- do_table(state, state.t1, key, value, &(&1)),
         false <- do_table(state, state.t2, key, value, &(&1)),
         false <- do_table(state, state.b1, key, value, &(&1 |> increase_target |> replace(false))),
         false <- do_table(state, state.b2, key, value, &(&1 |> decrease_target |> replace(true))),
    do: do_missed(state, key, value)
  end

  @doc false
  def handle_update(state, key, value, touch) do
    cond do
      DblTable.update(state.t1, key, value) ->
        touch && move_to_t2(state, state.t1, key, value)
      DblTable.update(state.t2, key, value) ->
        touch && move_to_t2(state, state.t2, key, value)
      true -> nil
    end
    state
  end

  @doc false
  def handle_delete(state, key) do
    with nil <- DblTable.delete(state.t1, key),
         nil <- DblTable.delete(state.t2, key),
         nil <- DblTable.delete(state.b1, key),
         nil <- DblTable.delete(state.b2, key),
    do: nil
  end

  defp do_table(state, table, key, value, action) do
    case DblTable.get(table, key) do
      {^key, _} ->
        state = state |> action.()
        move_to_t2(state, table, key, value)
        state
      nil -> false
    end
  end

  defp do_missed(state, key, value) do
    state = state |> adjust
    DblTable.put_to_mru(state.t1, key, value)
    state
  end

  defp move_to_t2(state, table, key, value) do
    DblTable.delete(table, key)
    DblTable.put_to_mru(state.t2, key, value)
  end

  defp increase_target(state) do
    len_b1 = DblTable.size(state.b1)
    len_b2 = DblTable.size(state.b2)
    new_target = min(state.size, state.target + max((len_b2/len_b1) |> Float.floor |> round, 1))
    %ArcCache{state | target: new_target}
  end

  defp decrease_target(state) do
    len_b1 = DblTable.size(state.b1)
    len_b2 = DblTable.size(state.b2)
    new_target = max(0, state.target - max((len_b1/len_b2) |> Float.floor |> round, 1))
    %ArcCache{state | target: new_target}
  end

  defp adjust(state) do
    len_t1 = DblTable.size(state.t1)
    len_t2 = DblTable.size(state.t2)
    len_b1 = DblTable.size(state.b1)
    len_b2 = DblTable.size(state.b2)
    len_l1 = len_t1 + len_b1
    len_l2 = len_t2 + len_b2
    cond do
      len_l1 >= state.size ->
        if(len_t1 < state.size) do
          DblTable.pop_lru(state.b1)
          state |> replace(false)
        else
          DblTable.pop_lru(state.t1)
          state
        end
      len_l1 < state.size and len_l1 + len_l2 >= state.size ->
        if(len_l1 + len_l2 >= 2*state.size) do
          DblTable.pop_lru(state.b2)
        end
        state |> replace(false)
      true -> state
    end
  end

  defp replace(state, was_in_b2) do
    len_t1 = DblTable.size(state.t1)
    if(len_t1 >= 1 and ((was_in_b2 and len_t1 == state.target) or (len_t1 > state.target))) do
      ghost(state.t1, state.b1)
    else
      ghost(state.t2, state.b2)
    end
    state
  end

  defp ghost(t_table, b_table) do
    {key, _value} = DblTable.pop_lru(t_table)
    DblTable.put_to_mru(b_table, key, :ghost)
  end
end
