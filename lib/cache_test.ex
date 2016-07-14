defmodule CacheTest do
  def test1(p \\ 1, size \\ 100000) do
    time_lru = time_test(LruCache, :t1_lru, &random_test/3, p, size)
    time_arc = time_test(ArcCacheNew, :t1_arc, &random_test/3, p, size)
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
    Enum.map(1..1000, fn(j) ->
        value = :crypto.rand_bytes(100)
        cache.put(cachename, i * 1000000000 + j, value)
#        :timer.sleep(1)
        ^value = cache.get(cachename, i * 1000000000 + j, true)
      end)
  end

  def test2(p \\ 1, size \\ 100000) do
    time_lru = time_test2(LruCache, :t2_lru, p, size)
    time_arc = time_test2(ArcCacheNew, :t2_arc, p, size)
    {time_lru, time_arc}
  end

  defp time_test2(cache, cachename, p, size) do
    cache.start_link(cachename, size)
    time_write = :timer.tc(fn ->
      Enum.map(1..p, fn(i) ->
        Task.async(fn() ->
          test2_write(cache, cachename, i)
        end)
      end)
      |> Enum.map(&Task.await(&1, 3000000))
    end) |> elem(0)
    time_read = :timer.tc(fn ->
      Enum.map(1..p, fn(i) ->
        Task.async(fn() ->
          test2_read(cache, cachename, i)
        end)
      end)
      |> Enum.map(&Task.await(&1, 3000000))
    end) |> elem(0)
    {time_write, time_read}
  end

  defp test2_write(cache, cachename, i) do
    Enum.map(1..1000, fn(j) ->
      value = :crypto.hash(:md5, j |> to_string) |> :base64.encode
      cache.put(cachename, i * 1000000000 + j, value)
    end)
  end

  defp test2_read(cache, cachename, i) do
    Enum.map(1..1000, fn(j) ->
      value = cache.get(cachename, i * 1000000000 + j, false)
#      if value == nil do
#        :timer.sleep(1)
#        value = :crypto.rand_bytes(100)
#        cache.put(cachename, i * 1000000000 + j, value)
#      end
    end)
  end

end
