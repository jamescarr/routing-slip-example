# RabbitMQ Messenger Implementation Plan

## Overview

Replace the in-process GenServer routing with RabbitMQ, demonstrating a true distributed routing slip pattern where messages flow through queues rather than direct process calls.

## Current State ✅

The `Messenger` behaviour abstraction is **complete**. The context module delegates all operations to the configured messenger, making implementation swapping trivial:

```elixir
# Already implemented:
# - Messenger behaviour with all callbacks
# - PubSub implementation (wraps GenServer-based nodes)
# - Context module delegates to Messenger
# - Config-based implementation switching
```

**Reference implementation:** `lib/routing_examples/routing_slip/messenger/pubsub.ex`

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                         ROUTING SLIP WITH RABBITMQ                               │
├─────────────────────────────────────────────────────────────────────────────────┤
│                                                                                  │
│  ┌──────────────┐                                                               │
│  │   LiveView   │◄───────────────────────────────────────────────┐              │
│  │  (Frontend)  │                                                 │              │
│  └──────┬───────┘                                                 │              │
│         │                                                         │              │
│         │ 1. Create Node / Send Message                           │              │
│         ▼                                                         │              │
│  ┌──────────────┐     ┌─────────────────────────────────────┐    │              │
│  │  Messenger   │────▶│        Topic Exchange               │    │              │
│  │  .RabbitMQ   │     │     routing_slip.messages           │    │              │
│  └──────────────┘     └─────────────────────────────────────┘    │              │
│                                    │                              │              │
│         ┌──────────────────────────┼──────────────────────┐      │              │
│         │                          │                      │      │              │
│         ▼                          ▼                      ▼      │              │
│  ┌─────────────┐           ┌─────────────┐        ┌─────────────┐│              │
│  │ node.alpha  │           │ node.beta   │        │ node.gamma  ││ Queues      │
│  │   (queue)   │           │   (queue)   │        │   (queue)   ││ (dynamic)   │
│  └──────┬──────┘           └──────┬──────┘        └──────┬──────┘│              │
│         │                         │                      │       │              │
│         ▼                         ▼                      ▼       │              │
│  ┌─────────────┐           ┌─────────────┐        ┌─────────────┐│              │
│  │  Broadway   │           │  Broadway   │        │  Broadway   ││ Consumers   │
│  │  Consumer   │           │  Consumer   │        │  Consumer   ││ (dynamic)   │
│  └──────┬──────┘           └──────┬──────┘        └──────┬──────┘│              │
│         │                         │                      │       │              │
│         │  Process & Republish    │                      │       │              │
│         └─────────────────────────┴──────────────────────┘       │              │
│                                    │                              │              │
│                                    ▼                              │              │
│                       ┌─────────────────────────┐                │              │
│                       │   routing_slip.events   │────────────────┘              │
│                       │   (fanout exchange)     │   UI Update Events            │
│                       └───────────┬─────────────┘                               │
│                                   │                                              │
│                                   ▼                                              │
│                       ┌─────────────────────────┐                               │
│                       │   events.{instance_id}  │  Per-LiveView queue           │
│                       │   (exclusive, auto-del) │  (subscribed on mount)        │
│                       └─────────────────────────┘                               │
│                                                                                  │
└─────────────────────────────────────────────────────────────────────────────────┘
```

## Message Flow

### 1. Creating a Node

```
LiveView                    Messenger.RabbitMQ              RabbitMQ
   │                              │                            │
   │  create_node("alpha")        │                            │
   ├─────────────────────────────▶│                            │
   │                              │  declare queue: node.alpha │
   │                              ├───────────────────────────▶│
   │                              │  bind to exchange          │
   │                              ├───────────────────────────▶│
   │                              │  start Broadway consumer   │
   │                              ├───────────────────────────▶│
   │                              │                            │
   │                              │  publish {:node_created}   │
   │                              │  to events exchange        │
   │                              ├───────────────────────────▶│
   │                              │                            │
   │◀──────────────────────────────────────────────────────────┤
   │         {:node_created, "alpha"} via events queue         │
```

### 2. Sending a Message

```
LiveView                    Messenger.RabbitMQ              RabbitMQ
   │                              │                            │
   │  send_message(payload,       │                            │
   │    ["alpha", "beta"])        │                            │
   ├─────────────────────────────▶│                            │
   │                              │  publish to exchange       │
   │                              │  routing_key: "node.alpha" │
   │                              ├───────────────────────────▶│
   │                              │                            │
   │                              │  publish {:message_started}│
   │                              │  to events exchange        │
   │                              ├───────────────────────────▶│
```

### 3. Node Processing (Broadway Consumer)

```
RabbitMQ                    Broadway Consumer               RabbitMQ
   │                              │                            │
   │  message from node.alpha     │                            │
   ├─────────────────────────────▶│                            │
   │                              │  1. Pop self from slip     │
   │                              │  2. Add to visited         │
   │                              │  3. Determine next dest    │
   │                              │                            │
   │                              │  publish {:message_processed}
   │                              │  to events exchange        │
   │                              ├───────────────────────────▶│
   │                              │                            │
   │                              │  if remaining_slip != []   │
   │                              │    publish to exchange     │
   │                              │    routing_key: "node.beta"│
   │                              ├───────────────────────────▶│
   │                              │                            │
   │                              │  else (slip empty)         │
   │                              │    publish {:message_completed}
   │                              │    to events exchange      │
   │                              ├───────────────────────────▶│
```

## Messenger Behaviour (Complete ✅)

```elixir
# lib/routing_examples/routing_slip/messenger.ex

# Event Broadcasting (UI updates)
@callback broadcast(event()) :: :ok | {:error, term()}
@callback subscribe() :: :ok | {:error, term()}
@callback unsubscribe() :: :ok | {:error, term()}

# Node Management  
@callback create_node(name :: String.t()) :: {:ok, term()} | {:error, term()}
@callback delete_node(name :: String.t()) :: :ok | {:error, term()}
@callback list_nodes() :: [String.t()]
@callback node_exists?(name :: String.t()) :: boolean()

# Message Routing
@callback route(destination :: String.t(), message()) :: :ok | {:error, term()}
```

## Components to Implement

### 1. Dependencies (`mix.exs`)

```elixir
# RabbitMQ messaging - explicit versions as of January 2026
# Note: amqp 4.x required for OTP 28+ compatibility
{:amqp, "~> 4.1"},              # Elixir AMQP client for publishing
{:broadway, "~> 1.2"},          # Data processing pipeline
{:broadway_rabbitmq, "~> 0.8"}  # RabbitMQ connector for Broadway
```

**Documentation References:**

| Package | Hex | Docs | Purpose |
|---------|-----|------|---------|
| `amqp` | [hex.pm/packages/amqp](https://hex.pm/packages/amqp) | [hexdocs.pm/amqp](https://hexdocs.pm/amqp/) | AMQP 0-9-1 client for publishing messages |
| `broadway` | [hex.pm/packages/broadway](https://hex.pm/packages/broadway) | [hexdocs.pm/broadway](https://hexdocs.pm/broadway/) | Concurrent data processing pipelines |
| `broadway_rabbitmq` | [hex.pm/packages/broadway_rabbitmq](https://hex.pm/packages/broadway_rabbitmq) | [hexdocs.pm/broadway_rabbitmq](https://hexdocs.pm/broadway_rabbitmq/) | RabbitMQ producer for Broadway |

**Why both `amqp` and `broadway_rabbitmq`?**
- `broadway_rabbitmq` handles **consuming** messages from queues
- `amqp` is needed for **publishing** messages (routing to next node, broadcasting events)

### 2. New Modules

| Module | Purpose |
|--------|---------|
| `Messenger.RabbitMQ` | Implements `Messenger` behaviour using AMQP |
| `Messenger.RabbitMQ.Connection` | Manages AMQP connection (GenServer) |
| `Messenger.RabbitMQ.NodeConsumer` | Broadway consumer for processing node messages |
| `Messenger.RabbitMQ.EventsListener` | GenServer that consumes events and forwards to local PubSub |
| `Messenger.RabbitMQ.Supervisor` | Supervises connection, node consumers, event listeners |

### 3. Exchange & Queue Topology

| Exchange | Type | Purpose |
|----------|------|---------|
| `routing_slip.messages` | topic | Routes messages to node queues |
| `routing_slip.events` | fanout | Broadcasts UI events to all subscribers |

| Queue Pattern | Binding | Purpose |
|---------------|---------|---------|
| `node.{name}` | `routing_slip.messages` with key `node.{name}` | Per-node message queue |
| `events.{instance_id}` | `routing_slip.events` (fanout) | Per-LiveView events queue |

## Implementation Steps

### Phase 0: Abstraction Layer ✅ COMPLETE

- [x] Expand `Messenger` behaviour with all callbacks
- [x] Implement `Messenger.PubSub` with GenServer-based nodes
- [x] Refactor context module to delegate to `Messenger`
- [x] Config-based implementation switching works

### Phase 1: Infrastructure Setup

- [ ] Add `amqp` and `broadway_rabbitmq` dependencies to `mix.exs`
- [ ] Create `Messenger.RabbitMQ.Connection` GenServer for connection management
- [ ] Create `Messenger.RabbitMQ.Supervisor` to supervise connection and dynamic consumers
- [ ] Add RabbitMQ config to `config/dev.exs`
- [ ] Declare exchanges on connection startup

### Phase 2: Events Pipeline (UI Updates)

- [ ] Create `Messenger.RabbitMQ.EventsListener` GenServer
- [ ] On `subscribe/0`: create exclusive queue, bind to events exchange, start consuming
- [ ] Consumer decodes events and forwards to local Phoenix.PubSub
- [ ] LiveView receives events via existing `handle_info` handlers (no changes needed)
- [ ] On `unsubscribe/0`: stop consumer, queue auto-deletes

### Phase 3: Node Management

- [ ] Implement `create_node/1`: declare queue, bind to messages exchange, start Broadway consumer
- [ ] Implement `delete_node/1`: stop Broadway consumer, delete queue
- [ ] Implement `list_nodes/0`: track nodes in ETS or Agent (RabbitMQ API is slow)
- [ ] Implement `node_exists?/1`: check local tracking
- [ ] Create `Messenger.RabbitMQ.NodeConsumer` Broadway module

### Phase 4: Message Routing

- [ ] Implement `route/2`: publish JSON-encoded message to messages exchange with routing key
- [ ] Broadway consumer processes message:
  1. Decode JSON message
  2. Update visited list with node name + step + timestamp
  3. Pop self from routing slip
  4. Publish `{:message_processed, ...}` to events exchange
  5. If more destinations: publish to messages exchange with next routing key
  6. If complete: publish `{:message_completed, ...}` to events exchange

### Phase 5: Integration & Testing

- [ ] Add config switch to use RabbitMQ messenger
- [ ] Test with local RabbitMQ (Docker)
- [ ] Verify UI works identically with both implementations
- [ ] Add graceful shutdown handling

## Configuration

**RabbitMQ Server:**
- Docker: `docker run -d --name rabbitmq -p 5672:5672 -p 15672:15672 rabbitmq:3-management`
- Management UI: http://localhost:15672 (guest/guest)
- Docs: [rabbitmq.com/docs](https://www.rabbitmq.com/docs)

```elixir
# config/dev.exs

# Switch to RabbitMQ (default is PubSub)
config :routing_examples, :routing_slip_messenger,
  RoutingExamples.RoutingSlip.Messenger.RabbitMQ

config :routing_examples, RoutingExamples.RoutingSlip.Messenger.RabbitMQ,
  connection: [
    host: "localhost",
    port: 5672,
    username: "guest",
    password: "guest",
    virtual_host: "/"
  ],
  messages_exchange: "routing_slip.messages",
  events_exchange: "routing_slip.events"
```

## Module Structure

```
lib/routing_examples/routing_slip/messenger/
├── pubsub.ex                    # ✅ Complete - GenServer implementation
└── rabbitmq/
    ├── rabbitmq.ex              # Main implementation (implements Messenger behaviour)
    ├── connection.ex            # AMQP connection GenServer
    ├── supervisor.ex            # Supervises connection + dynamic consumers
    ├── node_consumer.ex         # Broadway consumer for node message processing
    └── events_listener.ex       # Consumes events, forwards to local PubSub
```

## Broadway Consumer

See [BroadwayRabbitMQ.Producer options](https://hexdocs.pm/broadway_rabbitmq/BroadwayRabbitMQ.Producer.html) for full configuration reference.

```elixir
defmodule RoutingExamples.RoutingSlip.Messenger.RabbitMQ.NodeConsumer do
  @moduledoc """
  Broadway consumer for processing routing slip messages.
  
  Each node gets its own Broadway pipeline consuming from a dedicated queue.
  See: https://hexdocs.pm/broadway/Broadway.html
  """
  use Broadway

  alias Broadway.Message
  alias RoutingExamples.RoutingSlip.Messenger.RabbitMQ

  def start_link(opts) do
    node_name = Keyword.fetch!(opts, :node_name)
    connection = Keyword.fetch!(opts, :connection)
    
    Broadway.start_link(__MODULE__,
      name: via_tuple(node_name),
      producer: [
        module: {BroadwayRabbitMQ.Producer,
          queue: "node.#{node_name}",
          connection: connection,
          on_failure: :reject,  # Reject failed messages (could use :reject_and_requeue)
          qos: [prefetch_count: 10]
        }
      ],
      processors: [default: [concurrency: 2]],
      context: %{node_name: node_name}
    )
  end

  def via_tuple(node_name) do
    {:via, Registry, {RabbitMQ.ConsumerRegistry, node_name}}
  end

  @impl true
  def handle_message(_, %Message{data: data} = message, context) do
    %{node_name: node_name} = context
    
    slip_message = Jason.decode!(data, keys: :atoms)
    updated = process_slip_message(slip_message, node_name)
    
    # Broadcast progress event
    RabbitMQ.publish_event({:message_processed, node_name, updated})
    
    # Route to next or complete
    case updated.routing_slip do
      [next | _] -> 
        RabbitMQ.publish_message(next, updated)
      [] -> 
        RabbitMQ.publish_event({:message_completed, updated})
    end
    
    message
  end

  defp process_slip_message(message, node_name) do
    step_number = length(message.visited) + 1
    new_visited = message.visited ++ [{node_name, step_number, DateTime.utc_now()}]
    [_current | remaining_slip] = message.routing_slip
    
    %{message | visited: new_visited, routing_slip: remaining_slip}
  end
end
```

## Testing Strategy

1. **Unit tests**: Mock AMQP calls, test message transformation logic
2. **Integration tests**: Use Docker RabbitMQ (`docker run -d -p 5672:5672 rabbitmq:3`)
3. **Comparison tests**: Same inputs through PubSub vs RabbitMQ messenger, verify identical UI events

## Open Questions

1. **Persistence**: Should node definitions survive restarts? 
   - Recommendation: No, keep queues non-durable for demo simplicity
   
2. **Error handling**: DLQ strategy for failed messages?
   - Recommendation: Log and ack for now, add DLQ later if needed
   
3. **Visualization delay**: Keep the `@forward_delay_ms` for demo purposes?
   - Recommendation: Yes, add optional delay in Broadway consumer for visual effect
   
4. **Multiple Phoenix instances**: How to handle multiple instances subscribing to events?
   - Handled: Each instance gets its own exclusive auto-delete queue bound to fanout exchange

## Rollback Plan

The `Messenger` behaviour allows instant rollback via config:

```elixir
# Switch back to PubSub (or just remove the config line)
config :routing_examples, :routing_slip_messenger,
  RoutingExamples.RoutingSlip.Messenger.PubSub
```

---

## Next Steps

**Phase 1: Infrastructure Setup** - Ready to begin!

1. Add dependencies
2. Create connection GenServer  
3. Create supervisor
4. Declare exchanges
