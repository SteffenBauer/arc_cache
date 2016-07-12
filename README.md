# ArcCache

Adaptive Replacement Cache implementation in Elixir, as described in:

http://www.cs.cmu.edu/~15-440/READINGS/megiddo-computer2004.pdf

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed as:

  1. Add `arc_cache` to your list of dependencies in `mix.exs`:

    ```elixir
    def deps do
      [{:arc_cache, "~> 0.1.0"}]
    end
    ```

  2. Ensure `arc_cache` is started before your application:

    ```elixir
    def application do
      [applications: [:arc_cache]]
    end
    ```

## Usage

Typically the cache is started from a supervisor:

```elixir
worker(ArcCache, [:my_cache, 10])
```

Or start it manually:

```
ArcCache.start_link(:my_cache, 10)
```

The resulting process and ets tables will be registered under this alias.
Now you can use the cache:

```elixir
ArcCache.put(:my_cache, "id", "value")
ArcCache.get(:my_cache, "id")
ArcCache.get(:my_cache, "id", touch = false)
ArcCache.update(:my_cache, "id", "new_value", touch = false)
ArcCache.delete(:my_cache, "id")
```
