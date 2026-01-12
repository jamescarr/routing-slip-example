defmodule RoutingExamples.RoutingSlip.Messenger.RabbitMQ.EventsListener do
  @moduledoc """
  GenServer that consumes events from RabbitMQ and forwards them to the subscribing process.

  Each LiveView that calls `Messenger.subscribe/0` gets its own EventsListener that:
  1. Creates an exclusive, auto-delete queue
  2. Binds it to the events fanout exchange
  3. Consumes events and sends them to the subscriber process
  4. Auto-cleans up when the subscriber dies

  This bridges RabbitMQ events to the existing LiveView `handle_info` handlers.
  """
  use GenServer

  alias RoutingExamples.RoutingSlip.Messenger.RabbitMQ.Connection

  require Logger

  # ============================================================================
  # Client API
  # ============================================================================

  @doc """
  Starts an events listener for the calling process.
  The listener monitors the subscriber and stops when they die.
  """
  def start_link(opts) do
    subscriber = Keyword.get(opts, :subscriber, self())
    GenServer.start_link(__MODULE__, %{subscriber: subscriber})
  end

  @doc """
  Stops an events listener.
  """
  def stop(pid) when is_pid(pid) do
    GenServer.stop(pid, :normal)
  end

  # ============================================================================
  # Server Callbacks
  # ============================================================================

  @impl true
  def init(%{subscriber: subscriber}) do
    # Monitor the subscriber so we stop if they die
    ref = Process.monitor(subscriber)

    state = %{
      subscriber: subscriber,
      subscriber_ref: ref,
      channel: nil,
      queue: nil,
      consumer_tag: nil
    }

    # Start consuming asynchronously
    send(self(), :setup_consumer)

    {:ok, state}
  end

  @impl true
  def handle_info(:setup_consumer, state) do
    case setup_consumer() do
      {:ok, channel, queue, consumer_tag} ->
        Logger.debug("[EventsListener] Subscribed to events queue: #{queue}")

        new_state = %{
          state
          | channel: channel,
            queue: queue,
            consumer_tag: consumer_tag
        }

        {:noreply, new_state}

      {:error, reason} ->
        Logger.warning("[EventsListener] Failed to setup consumer: #{inspect(reason)}, retrying...")
        Process.send_after(self(), :setup_consumer, 1000)
        {:noreply, state}
    end
  end

  # Handle incoming messages from RabbitMQ
  def handle_info({:basic_deliver, payload, _meta}, state) do
    case decode_event(payload) do
      {:ok, event} ->
        # Forward to subscriber (the LiveView process)
        send(state.subscriber, event)

      {:error, reason} ->
        Logger.warning("[EventsListener] Failed to decode event: #{inspect(reason)}")
    end

    {:noreply, state}
  end

  # Handle consumer registration confirmation
  def handle_info({:basic_consume_ok, %{consumer_tag: _tag}}, state) do
    Logger.debug("[EventsListener] Consumer registered")
    {:noreply, state}
  end

  # Handle consumer cancellation
  def handle_info({:basic_cancel, %{consumer_tag: _tag}}, state) do
    Logger.warning("[EventsListener] Consumer cancelled by broker")
    {:stop, :consumer_cancelled, state}
  end

  def handle_info({:basic_cancel_ok, %{consumer_tag: _tag}}, state) do
    {:noreply, state}
  end

  # Subscriber died - stop ourselves
  def handle_info({:DOWN, ref, :process, _pid, _reason}, %{subscriber_ref: ref} = state) do
    Logger.debug("[EventsListener] Subscriber died, stopping")
    {:stop, :normal, state}
  end

  @impl true
  def terminate(_reason, state) do
    # Clean up: cancel consumer and close channel
    if state.channel && state.consumer_tag do
      try do
        AMQP.Basic.cancel(state.channel, state.consumer_tag)
      catch
        _, _ -> :ok
      end
    end

    if state.channel do
      try do
        AMQP.Channel.close(state.channel)
      catch
        _, _ -> :ok
      end
    end

    :ok
  end

  # ============================================================================
  # Private Functions
  # ============================================================================

  defp setup_consumer do
    with {:ok, conn} <- AMQP.Connection.open(Connection.connection_opts()),
         {:ok, channel} <- AMQP.Channel.open(conn) do
      # Create exclusive, auto-delete queue with generated name
      {:ok, %{queue: queue}} =
        AMQP.Queue.declare(channel, "",
          exclusive: true,
          auto_delete: true
        )

      # Bind to the events fanout exchange
      :ok = AMQP.Queue.bind(channel, queue, Connection.events_exchange())

      # Start consuming
      {:ok, consumer_tag} = AMQP.Basic.consume(channel, queue, self(), no_ack: true)

      {:ok, channel, queue, consumer_tag}
    end
  end

  defp decode_event(payload) do
    try do
      event = :erlang.binary_to_term(payload)
      {:ok, event}
    rescue
      e -> {:error, e}
    end
  end
end
