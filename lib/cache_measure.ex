defmodule CacheMeasure do

  def run(cache, size \\ 1024) do
    cache.start_link(:cache, size)
    {time, {total, hits, _}} = :timer.tc( fn ->
      File.stream!("priv/War_and_Peace.txt")
      |> Stream.map(&(String.replace &1, ~r/[^\w ]/, "" ))
      |> Stream.map(&String.downcase/1)
      |> Stream.filter(&(String.length(&1)>0))
      |> Stream.map(&String.split/1)
      |> Stream.flat_map(&(&1))
      |> Stream.filter(&(String.length(&1)>8))
      |> Enum.reduce({0, 0, cache}, &cache_item/2)
    end)
    Agent.stop(:cache)
    [time: time, total: total, hits: hits, ratio: "#{100.0*hits/total}%"]
  end

  defp cache_item(key, {total, hits, cache}) do
    case cache.get(:cache, key) do
      nil    -> cache.put(:cache, key, value(key))
                {total+1, hits, cache}
      _other -> {total+1, hits+1, cache}
    end
  end

  defp value(key) do
    String.length(key)
  end

end
