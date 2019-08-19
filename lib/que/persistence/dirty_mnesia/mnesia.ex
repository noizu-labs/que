defmodule Que.Persistence.DirtyMnesia do
  use Que.Persistence

  @moduledoc """
  Mnesia adapter to persist `Que.Job`s

  This module defines a Database and a Job Table in Mnesia to keep
  track of all Jobs, along with Mnesia transaction methods that
  provide an easy way to find, insert, update or destroy Jobs from
  the Database.

  It implements all callbacks defined in `Que.Persistence`, along
  with some `Mnesia` specific ones. You should read the
  `Que.Persistence` documentation if you just want to interact
  with the Jobs in database.


  ## Persisting to Disk

  `Que` works out of the box without any configuration needed, but
  initially all Jobs are not persisted to disk, and are only in
  memory. You'll need to create the Mnesia Schema on disk and create
  the Job Database for this to work.

  Que provides ways that automatically do this for you. First,
  specify the location where you want your Mnesia database to be
  created in your `config.exs` file. It's highly recommended that you
  specify your `Mix.env` in the path to keep development, test and
  production databases separate.

  ```
  config :mnesia, dir: 'mnesia/\#{Mix.env}/\#{node()}'
  # Notice the single quotes
  ```

  You can now either run the `Mix.Tasks.Que.Setup` mix task or call
  `Que.Persistence.Mnesia.setup!/0` to create the Schema, Database
  and Tables.
  """

  @config [db: DB, table: Jobs]
  @db     Module.concat(Que.Persistence.Mnesia, @config[:db])
  @store  Module.concat(@db, @config[:table])
  @auto_inc Module.concat([@db, AUIN])

  @db_handler     Module.concat(__MODULE__, @config[:db])
  @store_handler  Module.concat(@db, @config[:table])
  @auto_inc_handler Module.concat([@db, AUIN])

  @doc """
  Creates the Mnesia Database for `Que` on disk

  This creates the Schema, Database and Tables for
  Que Jobs on disk for the specified erlang nodes so
  Jobs are persisted across application restarts.
  Calling this momentarily stops the `:mnesia`
  application so you should make sure it's not being
  used when you do.

  If no argument is provided, the database is created
  for the current node.

  ## On Production

  For a compiled release (`Distillery` or `Exrm`),
  start the application in console mode or connect a
  shell to the running release and simply call the
  method:

  ```
  $ bin/my_app remote_console

  iex(my_app@127.0.0.1)1> Que.Persistence.Mnesia.setup!
  :ok
  ```

  You can alternatively provide a list of nodes for
  which you would like to create the schema:

  ```
  iex(my_app@host_x)1> nodes = [node() | Node.list]
  [:my_app@host_x, :my_app@host_y, :my_app@host_z]

  iex(my_app@node_x)2> Que.Persistence.Mnesia.setup!(nodes)
  :ok
  ```

  """
  @spec setup!(nodes :: list(node)) :: :ok
  def setup!(nodes \\ [node()]) do
    # Create the DB directory (if custom path given)
    if path = Application.get_env(:mnesia, :dir) do
      :ok = File.mkdir_p!(path)
    end

    # Create the Schema
    Memento.stop
    Memento.Schema.create(nodes)
    Memento.start

    # Create the DB with Disk Copies
    Memento.Table.create!(@store, disc_copies: nodes)
    Memento.Table.create!(@auto_inc, disc_copies: nodes)

    # @TODO Use Memento.Table.wait when it gets implemented
    # Wait for Tables.
    case :mnesia.wait_for_tables([@store, @auto_inc], 15000) do
      :ok -> :ok
      e -> IO.puts "Error Creating Que Tables [#{inspect e}]"
    end
  end




  @doc "Returns the Mnesia configuration for Que"
  @spec __config__ :: Keyword.t
  def __config__ do
    [
      database: @db,
      table:    @store,
      auto_increment_table:     @auto_inc,
      path:     Path.expand(Application.get_env(:mnesia, :dir))
    ]
  end





  # Callbacks in Table Definition
  # -----------------------------


  # Make sures that the DB exists (either
  # in memory or on disk)
  @doc false
  def initialize do
    Memento.Table.create(@store)
    Memento.Table.create(@auto_inc)

    Enum.reduce_while(1..1_000, 0, fn(i, acc) ->
      w = (i + 10) * 1_000
      case :mnesia.wait_for_tables([@store, @auto_inc], w)  do
        :ok -> {:halt, acc}
        _ ->
          IO.puts "QUE: Waiting on Tables - #{i}}"
          {:cont, acc + w}
      end
    end)

    case :mnesia.wait_for_tables([@store, @auto_inc], 5_000)  do
      :ok -> :ok
      _ ->
        IO.puts "QUE: Waiting on Tables - hard wait"
        :mnesia.wait_for_tables([@store, @auto_inc], :infinity)
        :ok
    end
  end

  # Cleans up Mnesia DB
  def reset do
    Memento.Table.delete(@store)
    Memento.Table.create(@store)

    Memento.Table.delete(@auto_inc)
    Memento.Table.create(@auto_inc)

    case :mnesia.wait_for_tables([@store, @auto_inc], 15000) do
      :ok -> :ok
      e -> IO.puts "Error Creating Que Tables [#{inspect e}]"
    end
  end

  # Deletes the Mnesia DB from disk and creates a fresh one in memory
  def reset! do
      Memento.stop
      File.rm_rf!(Que.Persistence.DirtyMnesia.__config__[:path])
      Memento.start
      reset()
  end

  @doc false
  defdelegate all,                to: @store_handler,   as: :all_jobs

  @doc false
  defdelegate all(worker),        to: @store_handler,   as: :all_jobs

  @doc false
  defdelegate completed,          to: @store_handler,   as: :completed_jobs

  @doc false
  defdelegate completed(worker),  to: @store_handler,   as: :completed_jobs

  @doc false
  defdelegate incomplete,         to: @store_handler,   as: :incomplete_jobs

  @doc false
  defdelegate incomplete(worker), to: @store_handler,   as: :incomplete_jobs

  @doc false
  defdelegate failed,             to: @store_handler,   as: :failed_jobs

  @doc false
  defdelegate failed(worker),     to: @store_handler,   as: :failed_jobs

  @doc false
  defdelegate find(job),          to: @store_handler,   as: :find_job

  @doc false
  defdelegate insert(job),        to: @store_handler,   as: :create_job

  @doc false
  defdelegate update(job),        to: @store_handler,   as: :update_job

  @doc false
  defdelegate destroy(job),       to: @store_handler,   as: :delete_job

end
