defmodule Exq.Stats.Server do
  use GenServer
  use Timex
  alias Exq.Redis.Connection
  alias Exq.Redis.JobQueue
  alias Exq.Redis.JobStat
  alias Exq.Support.Json
  alias Exq.Stats.Process
  require Logger

  @default_name :exq_stats

  defmodule State do
    defstruct redis: nil
  end

  def add_process(pid, namespace, worker, host, job) do
    GenServer.cast(pid, {:add_process, namespace,
      %Process{pid: worker, host: host, job: job, started_at: DateFormat.format!(Date.universal, "{ISO}")}})
  end

##===========================================================
## gen server callbacks
##===========================================================

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, @default_name)
    GenServer.start_link(__MODULE__, [opts], [{:name, name}])
  end

  # These are the callbacks that GenServer.Behaviour will use
  def init([opts]) do
    {:ok, %State{redis: Keyword.get(opts, :redis)}}
  end

  def default_name, do: @default_name

  def handle_cast({:add_process, namespace, process}, state) do
    JobStat.add_process(state.redis, namespace, process)
    {:noreply, state}
  end

  def handle_cast({:record_processed, namespace, job}, state) do
    JobStat.record_processed(state.redis, namespace, job)
    {:noreply, state}
  end

  def handle_cast({:record_failure, namespace, error, job}, state) do
    if job do
      JobQueue.retry_or_fail_job(state.redis, namespace, job, error)
    end
    JobStat.record_failure(state.redis, namespace, error, job)
    {:noreply, state}
  end

  def handle_cast({:process_terminated, namespace, hostname, pid}, state) do
    {:ok, _} = JobStat.remove_process(state.redis, namespace, hostname, pid)
    {:noreply, state}
  end

  def handle_cast(data, state) do
    Logger.error("INVALID MESSAGE #{data}")
    {:noreply, state}
  end

  def handle_call({:stop}, _from, state) do
    { :stop, :normal, :ok, state }
  end

  def handle_info(info, state) do
    Logger.error("INVALID MESSAGE #{info}")
    {:noreply, state}
  end

  def terminate(_reason, _state) do
    {:ok}
  end

  def code_change(_old_version, state, _extra) do
    {:ok, state}
  end

##===========================================================
## Methods
##===========================================================

end
