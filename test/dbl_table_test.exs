defmodule DblTableTest do
  use ExUnit.Case
  # doctest DblTable

  test "put to mru" do
    assert {:ok, _} = DblTable.start_link(:tabletest1)
    assert :ok == DblTable.put_to_mru(:tabletest1, 1, "test")
    assert {1, "test"} = DblTable.get(:tabletest1, 1)
    assert nil == DblTable.get(:tabletest1, 2)
    assert :ok == DblTable.put_to_mru(:tabletest1, 1, "test new")
    assert {1, "test new"} = DblTable.get(:tabletest1, 1)
    assert :ok == DblTable.put_to_mru(:tabletest1, 2, "test2")
    assert {1, "test new"} = DblTable.get(:tabletest1, 1)
    assert {2, "test2"} = DblTable.get(:tabletest1, 2)
  end

  test "delete entry" do
    assert {:ok, _} = DblTable.start_link(:tabletest2)
    assert :ok == DblTable.put_to_mru(:tabletest2, 1, "test")
    assert :ok == DblTable.delete(:tabletest2, 1)
    assert nil == DblTable.get(:tabletest2, 1)
    assert nil == DblTable.delete(:tabletest2, 1)
  end

  test "pop from lru" do
    assert {:ok, _} = DblTable.start_link(:tabletest3)
    assert nil == DblTable.pop_lru(:tabletest3)
    assert :ok == DblTable.put_to_mru(:tabletest3, 1, "test")
    assert {1, "test"} = DblTable.pop_lru(:tabletest3)
    assert nil == DblTable.pop_lru(:tabletest3)
  end

  test "table size" do
    assert {:ok, _} = DblTable.start_link(:tabletest4)
    assert 0 == DblTable.size(:tabletest4)
    assert :ok == DblTable.put_to_mru(:tabletest4, 1, "test")
    assert 1 == DblTable.size(:tabletest4)
    assert :ok == DblTable.put_to_mru(:tabletest4, 2, "test")
    assert 2 == DblTable.size(:tabletest4)
    assert :ok == DblTable.delete(:tabletest4, 1)
    assert 1 == DblTable.size(:tabletest4)
    assert {2, "test"} = DblTable.pop_lru(:tabletest4)
    assert 0 == DblTable.size(:tabletest4)
  end

  test "get all" do
    assert {:ok, _} = DblTable.start_link(:tabletest5)
    assert [] == DblTable.get_all(:tabletest5)
    assert :ok == DblTable.put_to_mru(:tabletest5, 1, "test1")
    assert [{1, "test1"}] == DblTable.get_all(:tabletest5)
    assert :ok == DblTable.put_to_mru(:tabletest5, 2, "test2")
    assert [{1, "test1"}, {2, "test2"}] == DblTable.get_all(:tabletest5)
    assert :ok == DblTable.put_to_mru(:tabletest5, 3, "test3")
    assert [{1, "test1"}, {2, "test2"}, {3, "test3"}] == DblTable.get_all(:tabletest5)
    assert :ok == DblTable.delete(:tabletest5, 2)
    assert [{1, "test1"}, {3, "test3"}] == DblTable.get_all(:tabletest5)
    assert {1, "test1"} = DblTable.pop_lru(:tabletest5)
    assert [{3, "test3"}] == DblTable.get_all(:tabletest5)
    assert :ok == DblTable.put_to_mru(:tabletest5, 4, "test4")
    assert [{3, "test3"}, {4, "test4"}] == DblTable.get_all(:tabletest5)
  end

  test "update entry" do
    assert {:ok, _} = DblTable.start_link(:tabletest6)
    assert false == DblTable.update(:tabletest6, 1, "test1")
    assert :ok == DblTable.put_to_mru(:tabletest6, 1, "test1")
    assert true == DblTable.update(:tabletest6, 1, "test12")
    assert {1, "test12"} == DblTable.get(:tabletest6, 1)
    assert :ok == DblTable.put_to_mru(:tabletest6, 2, "test2")
    assert true == DblTable.update(:tabletest6, 2, "test22")
    assert true == DblTable.update(:tabletest6, 1, "test13")
    assert {1, "test13"} == DblTable.pop_lru(:tabletest6)
    assert {2, "test22"} == DblTable.pop_lru(:tabletest6)
  end

end
