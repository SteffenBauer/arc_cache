defmodule ArcCacheNewTest do
  use ExUnit.Case
  # doctest ArcCacheNew

  test "basic usage" do
    assert {:ok, _}    = ArcCacheNew.start_link(:arcnewtest1, 10)
    assert nil        == ArcCacheNew.get(:arcnewtest1, 1)
    assert :ok        == ArcCacheNew.put(:arcnewtest1, 1, "entry1")
    assert "entry1"   == ArcCacheNew.get(:arcnewtest1, 1)
    assert nil        == ArcCacheNew.get(:arcnewtest1, 2, false)
    assert :ok        == ArcCacheNew.put(:arcnewtest1, 2, "test2")
    assert "test2"    == ArcCacheNew.get(:arcnewtest1, 2, false)
    assert :ok        == ArcCacheNew.put(:arcnewtest1, 1, "newtest1")
    assert "newtest1" == ArcCacheNew.get(:arcnewtest1, 1, false)
    assert :ok        == ArcCacheNew.delete(:arcnewtest1, 1)
    assert nil        == ArcCacheNew.get(:arcnewtest1, 1, false)
  end

  test "cache get with and without touching" do
    assert {:ok, _} = ArcCacheNew.start_link(:arcnewtest2, 10)
    assert :ok      == ArcCacheNew.put(:arcnewtest2, 1, "test1")
    assert :ok      == ArcCacheNew.put(:arcnewtest2, 2, "test2")
    assert ArcCacheNew.debug(:arcnewtest2, :t1) == [{1, "test1"}, {2, "test2"}]
    assert ArcCacheNew.debug(:arcnewtest2, :t2) == []
    assert "test1"  == ArcCacheNew.get(:arcnewtest2, 1, false)
    assert "test2"  == ArcCacheNew.get(:arcnewtest2, 2, false)
    assert ArcCacheNew.debug(:arcnewtest2, :t1) == [{1, "test1"}, {2, "test2"}]
    assert ArcCacheNew.debug(:arcnewtest2, :t2) == []
    assert "test1"  == ArcCacheNew.get(:arcnewtest2, 1, true)
    assert ArcCacheNew.debug(:arcnewtest2, :t1) == [{2, "test2"}]
    assert ArcCacheNew.debug(:arcnewtest2, :t2) == [{1, "test1"}]
    assert "test2"  == ArcCacheNew.get(:arcnewtest2, 2, true)
    assert ArcCacheNew.debug(:arcnewtest2, :t1) == []
    assert ArcCacheNew.debug(:arcnewtest2, :t2) == [{1, "test1"}, {2, "test2"}]
  end

  test "cache update with and without touching" do
    assert {:ok, _} = ArcCacheNew.start_link(:arcnewtest3, 10)
    assert :ok      == ArcCacheNew.put(:arcnewtest3, 1, "test1")
    assert :ok      == ArcCacheNew.put(:arcnewtest3, 2, "test2")
    assert :ok      == ArcCacheNew.update(:arcnewtest3, 1, "test12", false)
    assert ArcCacheNew.debug(:arcnewtest3, :t1) == [{1, "test12"}, {2, "test2"}]
    assert ArcCacheNew.debug(:arcnewtest3, :t2) == []
    assert :ok      == ArcCacheNew.update(:arcnewtest3, 1, "test13", true)
    assert ArcCacheNew.debug(:arcnewtest3, :t1) == [{2, "test2"}]
    assert ArcCacheNew.debug(:arcnewtest3, :t2) == [{1, "test13"}]
  end

  # Test to reproduce the table fillup in reference implementation described at
  # http://code.activestate.com/recipes/576532/
  test "Python recipe 576532 test" do
    assert {:ok, _} = ArcCacheNew.start_link(:arcnewtest4, 10)
    keys = Enum.to_list(0..19) ++ Enum.to_list(11..14) ++ Enum.to_list(0..19) ++
           Enum.to_list(11..39) ++ [39, 38, 37, 36, 35, 34, 33, 32, 16, 17, 11, 41]
    for key <- keys do
      assert :ok == ArcCacheNew.put(:arcnewtest4, key, "Entry")
    end
    assert ArcCacheNew.debug(:arcnewtest4, :t1) == for(k <- [41], do: {k, "Entry"})
    assert ArcCacheNew.debug(:arcnewtest4, :t2) == for(k <- [37, 36, 35, 34, 33, 32, 16, 17, 11], do: {k, "Entry"})
    assert ArcCacheNew.debug(:arcnewtest4, :b1) == [30, 31]
    assert ArcCacheNew.debug(:arcnewtest4, :b2) == [12, 13, 14, 15, 18, 19, 39, 38]
    assert ArcCacheNew.debug(:arcnewtest4, :target) == 5
  end

end
