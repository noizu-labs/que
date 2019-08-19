defmodule Que.ServerSupervisor do
  use Supervisor

  @module __MODULE__

  @moduledoc """
  This Supervisor is responsible for spawning a `Que.Server`
  for each worker. You shouldn't start this manually unless
  you absolutely know what you're doing.
  """




  @doc """
  Starts the Supervision Tree
  """
  @spec start_link() :: Supervisor.on_start
  def start_link do
    Que.Helpers.log("Booting Server Supervisor for Workers", :low)
    pid = Supervisor.start_link(@module, :ok, name: @module)

    # Resume Pending Jobs
    resume_queued_jobs()
    pid
  end




  @doc """
  Starts a `Que.Server` for the given worker
  """
  @spec start_server(worker :: Que.Worker.t) :: Supervisor.on_start_child | no_return
  def start_server(worker) do
    Que.Worker.validate!(worker)
    Supervisor.start_child(@module, [worker])
  end




  # If the server for the worker is running, add job to it.
  # If not, spawn a new server first and then add it.
  @doc false
  def add(worker, args) do
    add(:pri1, worker, args)
  end

  @doc false
  def add(priority, worker, args) do

    is_shard = try do
      worker._is_shard?
      rescue _ -> false
      catch _ -> false
    end

    add(:pri1, worker, args)
  end

  @doc false
  def add(priority, worker, args) do

    is_shard = try do
      worker._is_shard?
    rescue _ -> false
    catch _ -> false
    end

    if is_shard do
      shards = worker._shards()
      pick = :"Shard#{:rand.uniform(shards)}"
      shard = Module.concat([worker, pick])
      unless Que.Server.exists?(shard) do
        start_server(shard)
      end
      Que.Server.add(priority, shard, args)
    else
      unless Que.Server.exists?(worker) do
        start_server(worker)
      end
      Que.Server.add(priority, worker, args)
    end


  end

  @doc false
  def pri0(worker, args) do
    add(:pri0, worker, args)
  end

  @doc false
  def pri1(worker, args) do
    add(:pri1, worker, args)
  end

  @doc false
  def pri2(worker, args) do
    add(:pri2, worker, args)
  end

  @doc false
  def pri3(worker, args) do
    add(:pri3, worker, args)
  end

  def remote_add(remote, worker, args) do
    :rpc.call(remote, __MODULE__, :add, [worker, args])
  end

  def remote_add(remote, priority, worker, args) do
    :rpc.call(remote, __MODULE__, :add, [priority, worker, args])
  end

  def remote_async_add(remote, worker, args) do
    :rpc.cast(remote, __MODULE__, :add, [worker, args])
    :ok
  end

  def remote_async_add(remote, priority, worker, args) do
    :rpc.cast(remote, __MODULE__, :add, [priority, worker, args])
    :ok
  end


  @doc false
  def init(:ok) do
    children = [
      worker(Que.Server, [])
    ]

    supervise(children, strategy: :simple_one_for_one)
  end




  # Spawn all (valid) Workers with queued jobs
  defp resume_queued_jobs do
    {valid, invalid} =
      Que.Persistence.incomplete
      |> Enum.map(&(&1.worker))
      |> Enum.uniq
      |> Enum.split_with(&Que.Worker.valid?/1)

    # Notify user about pending jobs for Invalid Workers
    if length(invalid) > 0 do
      Que.Helpers.log("Found pending jobs for invalid workers: #{inspect(invalid)}")
    end

    # Process pending jobs for valid workers
    if length(valid) > 0 do
      Que.Helpers.log("Found pending jobs for: #{inspect(valid)}")
      Enum.map(valid, &start_server/1)
    end
  end

end

