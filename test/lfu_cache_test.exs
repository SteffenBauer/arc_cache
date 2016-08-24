defmodule LfuCacheTest do
  use ExUnit.Case

  test "basic usage" do
    assert {:ok, _}    = LfuCache.start_link(:lfutest1, 10)
    assert nil        == LfuCache.get(:lfutest1, 1)
    assert :ok        == LfuCache.put(:lfutest1, 1, "entry1")
    assert "entry1"   == LfuCache.get(:lfutest1, 1)
    assert nil        == LfuCache.get(:lfutest1, 2, false)
    assert :ok        == LfuCache.put(:lfutest1, 2, "test2")
    assert "test2"    == LfuCache.get(:lfutest1, 2, false)
    assert :ok        == LfuCache.put(:lfutest1, 1, "newtest1")
    assert "newtest1" == LfuCache.get(:lfutest1, 1, false)
    assert :ok        == LfuCache.delete(:lfutest1, 1)
    assert nil        == LfuCache.get(:lfutest1, 1, false)
  end
end
