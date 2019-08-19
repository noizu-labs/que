defmodule Que.Queue do
  defstruct [:worker, :queued, :running]


  @moduledoc """
  Module to manage a Queue comprising of multiple jobs.

  Responsible for queueing (duh), executing and handling callbacks,
  for `Que.Job`s of a specific `Que.Worker`. Also keeps track of
  running jobs and processes them concurrently (if the worker is
  configured so).

  Meant for internal usage, so you shouldn't use this unless you
  absolutely know what you're doing.
  """


  @typedoc  "A `Que.Queue` struct"
  @type     t :: %Que.Queue{}


  @typedoc "Acceptable Priority Levels"
  @type pri :: :pri0 | :pri1 | :pri2 | :pri3

  @priority_levels [:pri0, :pri1, :pri2, :pri3]


  @doc """
  Returns a new processable Queue with defaults
  """
  @spec new(worker :: Que.Worker.t, jobs :: list(Que.Job.t)) :: Que.Queue.t
  def new(worker, jobs \\ []) do
    queued = Enum.map(@priority_levels, fn(pri) ->
      jobs = Enum.filter(jobs, &(&1.priority == pri))
      {pri, :queue.from_list(jobs)}
    end) |> Map.new()

    %Que.Queue{
      worker:  worker,
      queued:  queued,
      running: []
    }
  end




  @doc """
  Processes the Queue and runs pending jobs
  """
  @spec process(queue :: Que.Queue.t) :: Que.Queue.t
  def process(%Que.Queue{running: running, worker: worker} = q) do
    Que.Worker.validate!(worker)

    if (length(running) < worker.concurrency) do
      case fetch(q) do
        {q, nil} ->
          q

        {q, job} ->
          job =
            job
            |> Que.Job.perform
            |> Que.Persistence.update

          %{ q | running: running ++ [job] }
      end

    else
      q
    end
  end




  @doc """
  Adds one or more Jobs to the `queued` list
  """
  @spec put(queue :: Que.Queue.t, jobs :: Que.Job.t | list(Que.Job.t)) :: Que.Queue.t
  def put(%Que.Queue{queued: queued} = q, jobs) when is_list(jobs) do
    queued = Enum.map(@priority_levels, fn(pri) ->
      jq = jobs
           |> Enum.filter(&(&1.priority == pri))
           |> :queue.from_list()
      {pri, :queue.join(queued[pri], jq)}
    end)
    %{q | queued: queued}
  end

  def put(%Que.Queue{queued: queued} = q, job) do
    queued = update_in(queued, [job.priority], fn(q) -> :queue.in(job, q) end)
    %{ q | queued: queued }
  end




  @doc """
  Fetches the next Job in queue and returns a queue and Job tuple
  """
  @spec fetch(queue :: Que.Queue.t) :: { Que.Queue.t, Que.Job.t | nil }
  def fetch(%Que.Queue{queued: queue} = q) do
    Enum.reduce_while(@priority_levels, nil,
      fn(pri, _acc) ->
        case :queue.out(queue[pri]) do
          {{:value, job}, rest} ->
            {:halt, { %{q | queued: put_in(queue, [pri], rest) }, job }}
          {:empty, _} -> {:cont, nil}
        end
      end
    ) || {q, nil}
  end




  @doc """
  Finds the Job in Queue by the specified key name and value.

  If no key is specified, it's assumed to be an `:id`. If the
  specified key is a :ref, it only searches in the `:running`
  list.
  """
  @spec find(queue :: Que.Queue.t, key :: atom, value :: term) :: Que.Job.t | nil
  def find(queue, key \\ :id, value)

  def find(%Que.Queue{ running: running }, :ref, value) do
    Enum.find(running, &(Map.get(&1, :ref) == value))
  end

  def find(%Que.Queue{} = q, key, value) do
    Enum.find(queued(q),  &(Map.get(&1, key) == value)) ||
    Enum.find(running(q), &(Map.get(&1, key) == value))
  end




  @doc """
  Finds a Job in the Queue by the given Job's id, replaces it and
  returns an updated Queue
  """
  @spec update(queue :: Que.Queue.t, job :: Que.Job.t) :: Que.Queue.t
  def update(%Que.Queue{} = q, %Que.Job{} = job) do
    queued = queued(q, job.priority)
    queued_index = Enum.find_index(queued, &(&1.id == job.id))

    if queued_index do
      queued = List.replace_at(queued, queued_index, job)
      %{ q | queued: put_in(q.queued, [job.priority], :queue.from_list(queued))}
    else
      running_index = Enum.find_index(q.running, &(&1.id == job.id))

      if running_index do
        running = List.replace_at(q.running, running_index, job)
        %{ q | running: running }

      else
        raise Que.Error.JobNotFound, "Job not found in Queue"
      end
    end
  end




  @doc """
  Removes the specified Job from `running`
  """
  @spec remove(queue :: Que.Queue.t, job :: Que.Job.t) :: Que.Queue.t
  def remove(%Que.Queue{} = q, %Que.Job{} = job) do
    index = Enum.find_index(q.running, &(&1.id == job.id))

    if index do
      %{ q | running: List.delete_at(q.running, index) }
    else
      raise Que.Error.JobNotFound, "Job not found in Queue"
    end
  end




  @doc """
  Returns queued jobs in the Queue
  """
  @spec queued(queue :: Que.Queue.t) :: list(Que.Job.t)
  def queued(%Que.Queue{queued: queued}) do
    Enum.map(@priority_levels, &(:queue.to_list(queued[&1]))) |> List.flatten()
  end

  @spec queued(queue :: Que.Queue.t, pri :: pri) :: list(Que.Job.t)
  def queued(%Que.Queue{queued: queued}, pri) do
    :queue.to_list(queued[pri])
  end

  @doc """
  Returns running jobs in the Queue
  """
  @spec running(queue :: Que.Queue.t) :: list(Que.Job.t)
  def running(%Que.Queue{running: running}) do
    running
  end

end
