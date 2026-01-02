defmodule RoutingExamples.RoutingSlip.Messenger.RabbitMQ.Connection do
  @moduledoc """
  Manages the AMQP connection and channel for RabbitMQ messaging.

  This GenServer:
  - Establishes and maintains an AMQP connection
  - Declares the required exchanges on startup
  - Provides a channel for publishing messages
  - Handles connection failures and reconnection

  See: https://hexdocs.pm/amqp/AMQP.Connection.html
  """
  use GenServer

  require Logger

  @reconnect_interval 5_000

  # ============================================================================
  # Client API
  # ============================================================================

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Returns the current AMQP channel for publishing.
  Returns {:ok, channel} or {:error, :not_connected}.
  """
  def get_channel do
    GenServer.call(__MODULE__, :get_channel)
  end

  @doc """
  Returns the connection options from config.
  """
  def connection_opts do
    config()[:connection] || default_connection_opts()
  end

  @doc """
  Returns the messages exchange name.
  """
  def messages_exchange do
    config()[:messages_exchange] || "routing_slip.messages"
  end

  @doc """
  Returns the events exchange name.
  """
  def events_exchange do
    config()[:events_exchange] || "routing_slip.events"
  end

  # ============================================================================
  # Server Callbacks
  # ============================================================================

  @impl true
  def init(_opts) do
    state = %{
      connection: nil,
      channel: nil,
      connection_ref: nil
    }

    # Connect asynchronously to not block supervision tree startup
    send(self(), :connect)

    {:ok, state}
  end

  @impl true
  def handle_call(:get_channel, _from, %{channel: nil} = state) do
    {:reply, {:error, :not_connected}, state}
  end

  def handle_call(:get_channel, _from, %{channel: channel} = state) do
    {:reply, {:ok, channel}, state}
  end

  @impl true
  def handle_info(:connect, state) do
    case connect() do
      {:ok, conn, chan} ->
        # Monitor the connection process
        ref = Process.monitor(conn.pid)

        Logger.info("[RabbitMQ] Connected successfully")

        new_state = %{state | connection: conn, channel: chan, connection_ref: ref}
        {:noreply, new_state}

      {:error, reason} ->
        Logger.warning("[RabbitMQ] Connection failed: #{inspect(reason)}, retrying in #{@reconnect_interval}ms")
        Process.send_after(self(), :connect, @reconnect_interval)
        {:noreply, state}
    end
  end

  def handle_info({:DOWN, ref, :process, _pid, reason}, %{connection_ref: ref} = state) do
    Logger.warning("[RabbitMQ] Connection lost: #{inspect(reason)}, reconnecting...")

    new_state = %{state | connection: nil, channel: nil, connection_ref: nil}
    Process.send_after(self(), :connect, @reconnect_interval)

    {:noreply, new_state}
  end

  @impl true
  def terminate(_reason, %{connection: conn}) when not is_nil(conn) do
    AMQP.Connection.close(conn)
  end

  def terminate(_reason, _state), do: :ok

  # ============================================================================
  # Private Functions
  # ============================================================================

  defp connect do
    with {:ok, conn} <- AMQP.Connection.open(connection_opts()),
         {:ok, chan} <- AMQP.Channel.open(conn),
         :ok <- declare_exchanges(chan) do
      {:ok, conn, chan}
    end
  end

  defp declare_exchanges(channel) do
    # Declare topic exchange for routing messages to node queues
    :ok = AMQP.Exchange.declare(channel, messages_exchange(), :topic, durable: false)

    # Declare fanout exchange for broadcasting UI events
    :ok = AMQP.Exchange.declare(channel, events_exchange(), :fanout, durable: false)

    Logger.info("[RabbitMQ] Exchanges declared: #{messages_exchange()}, #{events_exchange()}")
    :ok
  end

  defp config do
    Application.get_env(:routing_examples, RoutingExamples.RoutingSlip.Messenger.RabbitMQ, [])
  end

  defp default_connection_opts do
    [
      host: "localhost",
      port: 5672,
      username: "guest",
      password: "guest",
      virtual_host: "/"
    ]
  end
end
