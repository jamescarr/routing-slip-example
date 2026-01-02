defmodule RoutingExamples.RoutingSlip.Messenger do
  @moduledoc """
  Behaviour for message transport in the Routing Slip pattern.

  This abstracts the messaging protocol, allowing different implementations:
  - `PubSub` - Phoenix.PubSub with GenServer nodes for in-process communication
  - `RabbitMQ` - RabbitMQ exchanges and queues for distributed messaging

  ## Usage

  Configure the messenger in your application config:

      config :routing_examples, :routing_slip_messenger,
        RoutingExamples.RoutingSlip.Messenger.PubSub

  Or use the default PubSub implementation.

  ## Callbacks

  Implementations must provide:

  ### Event Broadcasting (UI updates)
  - `broadcast/1` - Send events to all subscribers
  - `subscribe/0` - Subscribe calling process to events
  - `unsubscribe/0` - Unsubscribe calling process

  ### Node Management
  - `create_node/1` - Create a processing node
  - `delete_node/1` - Remove a processing node
  - `list_nodes/0` - List all registered nodes
  - `node_exists?/1` - Check if a node exists

  ### Message Routing
  - `route/2` - Route a message to a destination node
  """

  @type message :: %{
          id: String.t(),
          payload: any(),
          routing_slip: [String.t()],
          visited: [{String.t(), pos_integer(), DateTime.t()}],
          created_at: DateTime.t()
        }

  @type event ::
          {:node_created, node_name :: String.t()}
          | {:message_started, message()}
          | {:message_processed, node_name :: String.t(), message()}
          | {:message_completed, message()}

  # ============================================================================
  # Event Broadcasting Callbacks
  # ============================================================================

  @doc """
  Broadcasts an event to all subscribers.
  """
  @callback broadcast(event()) :: :ok | {:error, term()}

  @doc """
  Subscribes the calling process to receive events.
  """
  @callback subscribe() :: :ok | {:error, term()}

  @doc """
  Unsubscribes the calling process from events.
  """
  @callback unsubscribe() :: :ok | {:error, term()}

  # ============================================================================
  # Node Management Callbacks
  # ============================================================================

  @doc """
  Creates and registers a new processing node with the given name.
  """
  @callback create_node(name :: String.t()) :: {:ok, term()} | {:error, term()}

  @doc """
  Deletes a processing node by name.
  """
  @callback delete_node(name :: String.t()) :: :ok | {:error, term()}

  @doc """
  Lists all registered node names.
  """
  @callback list_nodes() :: [String.t()]

  @doc """
  Checks if a node with the given name exists.
  """
  @callback node_exists?(name :: String.t()) :: boolean()

  # ============================================================================
  # Message Routing Callbacks
  # ============================================================================

  @doc """
  Routes a message to the specified destination node.
  The node will process the message according to the routing slip pattern.
  """
  @callback route(destination :: String.t(), message()) :: :ok | {:error, term()}

  # ============================================================================
  # Convenience Functions (delegate to configured implementation)
  # ============================================================================

  @doc """
  Returns the configured messenger implementation.
  Defaults to `RoutingExamples.RoutingSlip.Messenger.PubSub`.
  """
  def impl do
    Application.get_env(
      :routing_examples,
      :routing_slip_messenger,
      RoutingExamples.RoutingSlip.Messenger.PubSub
    )
  end

  # Event Broadcasting

  @doc "Broadcasts an event using the configured messenger."
  def broadcast(event), do: impl().broadcast(event)

  @doc "Subscribes the calling process using the configured messenger."
  def subscribe, do: impl().subscribe()

  @doc "Unsubscribes the calling process using the configured messenger."
  def unsubscribe, do: impl().unsubscribe()

  # Node Management

  @doc "Creates a node using the configured messenger."
  def create_node(name), do: impl().create_node(name)

  @doc "Deletes a node using the configured messenger."
  def delete_node(name), do: impl().delete_node(name)

  @doc "Lists nodes using the configured messenger."
  def list_nodes, do: impl().list_nodes()

  @doc "Checks node existence using the configured messenger."
  def node_exists?(name), do: impl().node_exists?(name)

  # Message Routing

  @doc "Routes a message using the configured messenger."
  def route(destination, message), do: impl().route(destination, message)
end
