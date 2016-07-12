defmodule CacheTest do
  def test1(p \\ 1, size \\ 100000) do
    time_lru = time_test(LruCache, :t1_lru, &random_test/3, p, size)
    time_arc = time_test(ArcCache, :t1_arc, &random_test/3, p, size)
    {time_lru, time_arc}
  end

  defp time_test(cache, cachename, test, p, size) do
    cache.start_link(cachename, size)
    :timer.tc(fn ->
      Enum.map(1..p, fn(i) ->
        Task.async(fn() ->
            test.(cache, cachename, i)
        end)
      end)
      |> Enum.map(&Task.await(&1, 3000000))
    end) |> elem(0)
  end

  defp random_test(cache, cachename, i) do
    Enum.map(1..100, fn(j) ->
        value = :crypto.rand_bytes(100)
        cache.put(cachename, i * 1000000000 + j, value)
        :timer.sleep(1)
        cache.get(cachename, i * 1000000000 + j, true)
      end)
  end

end
