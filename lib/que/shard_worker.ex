defmodule Que.ShardWorker do

  @doc false
  defmacro __using__(opts \\ []) do
    quote bind_quoted: [opts: opts] do
      @after_compile __MODULE__
      @concurrency   opts[:concurrency] || 64
      @shards @concurrency

      module = __MODULE__
      for i <- 0 .. @shards do # @note OB1
        defmodule :"#{module}.Shard#{i}" do
          @module module
          use Que.Worker, concurrency: 1
          defdelegate perform(t), to: @module
          defdelegate on_success(t), to: @module
          defdelegate on_failure(t, e), to: @module
        end
      end

      def _shards(), do: @shards

      def _is_shard?, do: true

      ## Default implementations of on_success and on_failure callbacks

      def on_success(_arg) do
      end


      def on_failure(arg, err) do
        IO.puts "FAILRE: #{inspect arg}, #{inspect err}"
      end


      defoverridable [on_success: 1, on_failure: 2]



      # Make sure the Worker is valid
      def __after_compile__(_env, _bytecode) do

        # Raises error if the Worker doesn't export a perform/1 method
        unless Module.defines?(__MODULE__, {:perform, 1}) do
          raise Que.Error.InvalidWorker,
                "#{ExUtils.Module.name(__MODULE__)} must export a perform/1 method"
        end


        # Raise error if the concurrency option in invalid
        unless @concurrency == :infinity or (is_integer(@concurrency) and @concurrency > 0) do
          raise Que.Error.InvalidWorker,
                "#{ExUtils.Module.name(__MODULE__)} has an invalid concurrency value"
        end
      end

    end
  end

end