defmodule RandomCacheTest do
  use ExUnit.Case

  test "basic usage" do
    assert {:ok, _}    = RandomCache.start_link(:randtest1, 10)
    assert nil        == RandomCache.get(:randtest1, 1)
    assert :ok        == RandomCache.put(:randtest1, 1, "entry1")
    assert "entry1"   == RandomCache.get(:randtest1, 1)
    assert nil        == RandomCache.get(:randtest1, 2, false)
    assert :ok        == RandomCache.put(:randtest1, 2, "test2")
    assert "test2"    == RandomCache.get(:randtest1, 2, false)
    assert :ok        == RandomCache.put(:randtest1, 1, "newtest1")
    assert "newtest1" == RandomCache.get(:randtest1, 1, false)
    assert :ok        == RandomCache.delete(:randtest1, 1)
    assert nil        == RandomCache.get(:randtest1, 1, false)
  end
end
