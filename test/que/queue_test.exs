defmodule Que.Test.Queue do
  use ExUnit.Case

  alias Que.Job
  alias Que.Queue

  alias Que.Test.Meta.Helpers
  alias Que.Test.Meta.TestWorker
  alias Que.Test.Meta.TestShardWorker
  alias Que.Test.Meta.ConcurrentWorker

  test "#shard worker for cases where throughput more critical than sequence" do
    q = Queue.new(TestShardWorker.Shard1)
    assert q.__struct__     == Queue
    assert q.worker         == TestShardWorker.Shard1
    assert Queue.queued(q)  == []
    assert Queue.running(q) == []
  end

  test "#shard worker for cases where throughput more critical than sequence - invoke" do
    capture = Helpers.capture_log(fn ->
      alias Que.Test.Meta.TestShardWorker
      Que.add(TestShardWorker, :test)
      Helpers.wait
      Process.sleep(50)
    end)
    assert capture =~ ~r/Completed Job.*TestShardWorker.Shard/
  end

  test "#new builds a new job queue with defaults" do
    q = Queue.new(TestWorker)

    assert q.__struct__     == Queue
    assert q.worker         == TestWorker
    assert Queue.queued(q)  == []
    assert Queue.running(q) == []
  end


  test "#new builds a new job queue with specified jobs" do
    q = Queue.new(TestWorker, as_jobs([1, 2, 3]))

    assert q.__struct__    == Queue
    assert Queue.queued(q) == as_jobs([1, 2, 3])
  end


  test "#queued returns list of queued jobs in the queue" do
    j1 = as_jobs([])
    j2 = as_jobs([1,2,3,4,5,6,7])

    q1 = q_fixture(j1)
    q2 = q_fixture(j2)

    assert Queue.queued(q1) == j1
    assert Queue.queued(q2) == j2
  end

  test "#queued should return items in order of priority" do
    expected = [as_job(5, :pri0), as_job(4, :pri1), as_job(8, :pri2), as_job(1, :pri3), as_job(2, :pri3), as_job(3, :pri3)]
    q1 = q_fixture(%{pri0: [5], pri1: [4], pri2: [8], pri3: [1,2,3]})
    assert Queue.queued(q1) == expected
  end

  test "#running returns list of running jobs in the queue" do
    j1 = as_jobs([])
    j2 = as_jobs([1,2,3,4,5,6,7])

    q1 = %Queue{running: j1}
    q2 = %Queue{running: j2}

    assert Queue.running(q1) == j1
    assert Queue.running(q2) == j2
  end


  test "#put adds a single job to the queued list" do
    expected = as_jobs([1,2,3,4])

    q =
      TestWorker
      |> Queue.new(as_jobs([1, 2, 3]))
      |> Queue.put(as_job(4))

    assert Queue.queued(q) == expected
  end


  test "#put adds multiple jobs to the queued list" do
    q =
      TestWorker
      |> Queue.new(as_jobs([1, 2, 3]))
      |> Queue.put(as_jobs([4, 5, 6, 7]))

    assert Queue.queued(q) == as_jobs([1, 2, 3, 4, 5, 6, 7])
  end


  test "#fetch gets the next job in queue and removes it from the list" do
    {q, job} =
      TestWorker
      |> Queue.new(as_jobs([1, 2, 3]))
      |> Queue.fetch

    assert job             == as_job(1)
    assert Queue.queued(q) == as_jobs([2, 3])
  end


  test "#fetch returns nil for empty queues" do
    {q, job} =
      TestWorker
      |> Queue.new
      |> Queue.fetch

    assert job             == nil
    assert Queue.queued(q) == []
  end


  test "#process starts the next job in queue and appends it to running" do
    capture = Helpers.capture_log(fn ->
      q =
        TestWorker
        |> Queue.new([Job.new(TestWorker)])
        |> Queue.process

      assert [%Job{status: :started}] = Queue.running(q)
      assert [] == Queue.queued(q)

      Helpers.wait
    end)

    assert capture =~ ~r/Starting/
  end

  test "#process starts jobs in sequence of priority" do
    capture = Helpers.capture_log(fn ->
      q =
        TestWorker
        |> Queue.new([Job.new(TestWorker)])
        |> Queue.process

      assert [%Job{status: :started}] = Queue.running(q)
      assert [] == Queue.queued(q)
      Helpers.wait
    end)
    assert capture =~ ~r/Starting/
  end

  test "#process does nothing when there is nothing in queue" do
    q_before = Queue.new(TestWorker)
    q_after  = Queue.process(q_before)

    assert q_after                == q_before
    assert Queue.queued(q_after)  == []
    assert Queue.running(q_after) == []
  end


  test "#process concurrently runs the specified no. of jobs" do
    capture = Helpers.capture_log(fn ->
      jobs =
        for i <- 1..4, do: Job.new(ConcurrentWorker, :"job_#{i}")

      q =
        ConcurrentWorker
        |> Queue.new(jobs)
        |> Queue.process
        |> Queue.process
        |> Queue.process
        |> Queue.process

      running = Queue.running(q)

      assert [] == Queue.queued(q)
      assert 4  == length(running)

      Enum.each(running, fn j ->
        assert %Job{status: :started} = j
      end)

      Helpers.wait
    end)

    assert capture =~ ~r/Starting/

    assert capture =~ ~r/perform: :job_1/
    assert capture =~ ~r/perform: :job_2/
    assert capture =~ ~r/perform: :job_3/
    assert capture =~ ~r/perform: :job_4/
  end


  test "#find finds the job by id when no field is specified" do
    job =
      TestWorker
      |> Queue.new(sample_job_list())
      |> Queue.find(:x)

    assert job.id     == :x
    assert job.status == :failed
  end


  test "#find finds the job by the given field" do
    job =
      TestWorker
      |> Queue.new(sample_job_list())
      |> Queue.find(:status, :failed)

    assert job.id     == :x
    assert job.status == :failed
  end


  test "#find returns nil when no results are found" do
    job =
      TestWorker
      |> Queue.new(sample_job_list())
      |> Queue.find(:y)

    assert job == nil
  end


  test "#update raises an error if the job doesn't exist in the queue" do
    assert_raise(Que.Error.JobNotFound, ~r/Job not found/, fn ->
      job = Job.new(TestWorker)
      q   = Queue.new(TestWorker)

      Queue.update(q, job)
    end)
  end


  test "#update updates a job in queued" do
    q = q_fixture(%{pri1: sample_job_list(:pri1)}, [])
    [_, _, _, job | _] = Queue.queued(q)
    assert job.id     == :x
    assert job.status == :failed

    q = Queue.update(q, %{ job | status: :queued })

    [_, _, _, job | _] = Queue.queued(q)
    assert job.status == :queued
  end


  test "#update updates a job in running" do
    q = %{ running: [_, _, _, job | _] } = q_fixture(%{}, sample_job_list())

    assert job.id     == :x
    assert job.status == :failed

    %{ running: [_, _, _, job | _] } = Queue.update(q, %{ job | status: :completed })

    assert job.status == :completed
  end


  test "#remove deletes a job from running in Queue" do
    q = %{ running: [_, _, _, job | _] } =
      %Queue{ queued: :queue.new(), running: sample_job_list() }

    assert length(Queue.running(q)) == 6

    q = Queue.remove(q, job)

    assert length(Queue.running(q)) == 5
    refute Enum.member?(Queue.running(q), job)
  end


  test "#remove raises an error if Job isn't in queue" do
    assert_raise(Que.Error.JobNotFound, ~r/Job not found/, fn ->
      job = Job.new(TestWorker)
      q   = Queue.new(TestWorker)

      Queue.remove(q, job)
    end)
  end


  ## Private
  ## Private
  defp q_fixture(q) do
    q_fixture(q, [])
  end

  defp q_fixture(queues, running, as_jobs \\ true, worker \\ TestWorker, rpri \\ :pri0)

  defp q_fixture(queues, running, as_jobs, worker, rpri) when is_list(queues) do
    q_fixture(%{rpri => queues}, running, as_jobs, worker, rpri)
  end

  defp q_fixture(queues, running, as_jobs, worker, rpri) do
    if as_jobs do
      queued = %{
        pri0: :queue.from_list(as_jobs(queues[:pri0] || [], :pri0, worker)),
        pri1: :queue.from_list(as_jobs(queues[:pri1] || [], :pri1, worker)),
        pri2: :queue.from_list(as_jobs(queues[:pri2] || [], :pri2, worker)),
        pri3: :queue.from_list(as_jobs(queues[:pri3] || [], :pri3, worker)),
      }
      running = as_jobs(running, rpri, worker)
      %Queue{ queued: queued, running: running}
    else
      queued = %{
        pri0: :queue.from_list(queues[:pri0] || []),
        pri1: :queue.from_list(queues[:pri1] || []),
        pri2: :queue.from_list(queues[:pri2] || []),
        pri3: :queue.from_list(queues[:pri3] || []),
      }
      %Queue{ queued: queued, running: running}
    end
  end

  defp as_job(entry, priority \\ :pri1, worker \\ TestWorker) do
    case entry do
      %Job{} -> entry
      _ -> Job.new(worker, entry, priority)
    end
  end

  defp as_jobs(entries, priority \\ :pri1, worker \\ TestWorker) do
    Enum.map(entries, fn(entry) ->
      case entry do
        %Job{} -> entry
        _ -> Job.new(worker, entry, priority)
      end
    end)
  end

  defp sample_job_list(priority \\ :pri1) do
    [
      Job.new(TestWorker, nil, priority),
      Job.new(TestWorker, nil, priority),
      Job.new(TestWorker, nil, priority),
      %Job{Job.new(TestWorker, nil, priority)|  id: :x, status: :failed },
      Job.new(TestWorker, nil, priority),
      Job.new(TestWorker, nil, priority)
    ]
  end
end

