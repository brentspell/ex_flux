defmodule Inflex.Database do
  @moduledoc """
  Configuration of a single database's connection pool, queue and supervision
  tree. Since InfluxDB uses a single UDP port on the server per database, this
  library's goal is to make it easy to do 1:1 mappings of a pool of UDP
  connections to that destination port and batching of datapoints.

  To get started, create your own module and do something like:

      use Inflex.Database, otp_app: :your_app, database: "your_db_name"

  In your application, simply add `YourApp.YourInflexDatabase` to the children:

      children = [
        ...,
        YourApp.YourInflexDatabase
      ]

  The database name isn't used for the UDP connection in anyway, but it is used
  to create database-specific workers. To support querying interfaces and HTTP
  based sending, the database would need to be known. To support these features
  in the future, the database name is held by all workers in their
  configuration.

  Where possible, `Inflex.Database.Supervisor` provides sane defaults for
  configuration options to make it as close as working out of the box as
  possible. A full list of configuration options and their types can be found
  there.
  """

  defmacro __using__(opts) do
    quote bind_quoted: [opts: opts] do
      @otp_app Keyword.fetch!(opts, :otp_app)
      @database Keyword.get(opts, :database)

      alias Inflex.Database.QueueWorker
      alias Inflex.Database.Supervisor, as: DBSupervisor

      def child_spec(opts) do
        %{
          id: __MODULE__,
          start: {__MODULE__, :start_link, [opts]},
          type: :supervisor
        }
      end

      def start_link(opts \\ []) do
        opts = Keyword.put_new(opts, :database, @database)
        DBSupervisor.start_link(__MODULE__, @otp_app, opts)
      end

      def push(%{} = point) do
        GenServer.cast(
          @database |> database_name() |> QueueWorker.via_tuple(),
          {:push, point}
        )
      end

      @spec database_name(prov :: String.t()) :: String.t()
      defp database_name(prov) when is_binary(prov), do: prov

      defp database_name(_prov) do
        @otp_app
        |> Application.get_env(__MODULE__, [])
        |> Keyword.get(:database)
      end

      defoverridable child_spec: 1
    end
  end

  @doc """
  queue a single data point (may trigger a batch being sent asynchronously)
  """
  @callback push(point :: Inflex.Point.t() | map()) :: :ok
end
