defmodule ArcCacheTest do
  use ExUnit.Case
  # doctest ArcCache

  test "basic usage" do
    assert {:ok, _}    = ArcCache.start_link(:arctest1, 10)
    assert nil        == ArcCache.get(:arctest1, 1)
    assert :ok        == ArcCache.put(:arctest1, 1, "entry1")
    assert "entry1"   == ArcCache.get(:arctest1, 1)
    assert nil        == ArcCache.get(:arctest1, 2, false)
    assert :ok        == ArcCache.put(:arctest1, 2, "test2")
    assert "test2"    == ArcCache.get(:arctest1, 2, false)
    assert :ok        == ArcCache.put(:arctest1, 1, "newtest1")
    assert "newtest1" == ArcCache.get(:arctest1, 1, false)
    assert :ok        == ArcCache.delete(:arctest1, 1)
    assert nil        == ArcCache.get(:arctest1, 1, false)
  end

  test "cache get with and without touching" do
    assert {:ok, _} = ArcCache.start_link(:arctest2, 10)
    assert :ok      == ArcCache.put(:arctest2, 1, "test1")
    assert :ok      == ArcCache.put(:arctest2, 2, "test2")
    assert ArcCache.debug(:arctest2, :t1) == [{1, "test1"}, {2, "test2"}]
    assert ArcCache.debug(:arctest2, :t2) == []
    assert "test1"  == ArcCache.get(:arctest2, 1, false)
    assert "test2"  == ArcCache.get(:arctest2, 2, false)
    assert ArcCache.debug(:arctest2, :t1) == [{1, "test1"}, {2, "test2"}]
    assert ArcCache.debug(:arctest2, :t2) == []
    assert "test1"  == ArcCache.get(:arctest2, 1, true)
    assert ArcCache.debug(:arctest2, :t1) == [{2, "test2"}]
    assert ArcCache.debug(:arctest2, :t2) == [{1, "test1"}]
    assert "test2"  == ArcCache.get(:arctest2, 2, true)
    assert ArcCache.debug(:arctest2, :t1) == []
    assert ArcCache.debug(:arctest2, :t2) == [{1, "test1"}, {2, "test2"}]
  end

  test "cache update with and without touching" do
    assert {:ok, _} = ArcCache.start_link(:arctest3, 10)
    assert :ok      == ArcCache.put(:arctest3, 1, "test1")
    assert :ok      == ArcCache.put(:arctest3, 2, "test2")
    assert :ok      == ArcCache.update(:arctest3, 1, "test12", false)
    assert ArcCache.debug(:arctest3, :t1) == [{1, "test12"}, {2, "test2"}]
    assert ArcCache.debug(:arctest3, :t2) == []
    assert :ok      == ArcCache.update(:arctest3, 1, "test13", true)
    assert ArcCache.debug(:arctest3, :t1) == [{2, "test2"}]
    assert ArcCache.debug(:arctest3, :t2) == [{1, "test13"}]
  end

  # Test to reproduce the table fillup in reference implementation described at
  # http://code.activestate.com/recipes/576532/
  test "Python recipe 576532 test" do
    assert {:ok, _} = ArcCache.start_link(:arctest4, 10)
    keys = Enum.to_list(0..19) ++ Enum.to_list(11..14) ++ Enum.to_list(0..19) ++
           Enum.to_list(11..39) ++ [39, 38, 37, 36, 35, 34, 33, 32, 16, 17, 11, 41]
    for key <- keys do
      assert :ok == ArcCache.put(:arctest4, key, "Entry")
    end
    assert ArcCache.debug(:arctest4, :t1) == for(k <- [41], do: {k, "Entry"})
    assert ArcCache.debug(:arctest4, :t2) == for(k <- [37, 36, 35, 34, 33, 32, 16, 17, 11], do: {k, "Entry"})
    assert ArcCache.debug(:arctest4, :b1) == [30, 31]
    assert ArcCache.debug(:arctest4, :b2) == [12, 13, 14, 15, 18, 19, 39, 38]
    assert ArcCache.debug(:arctest4, :target) == 5
  end

end
