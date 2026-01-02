# Routing Examples

A Phoenix LiveView application demonstrating Enterprise Integration Patterns, specifically the **Routing Slip** pattern.

## Routing Slip Pattern

The Routing Slip pattern allows a message to carry its own itinerary, specifying the sequence of processing steps it should follow. Each processor:

1. Receives the message
2. Processes it (adds itself to the "visited" list)
3. Removes itself from the routing slip
4. Forwards to the next destination

This demo provides a real-time visualization of messages flowing through dynamically registered nodes.

## Two Messenger Implementations

This project demonstrates the power of abstraction with two interchangeable messaging backends:

| Implementation | Transport | Best For |
|----------------|-----------|----------|
| **PubSub** (default) | GenServer + Phoenix.PubSub | Development, single-node |
| **RabbitMQ** | AMQP + Broadway | Production, distributed |

Both implementations share the same `Messenger` behaviour, so the LiveView and context module work identically with either backend.

## Quick Start (PubSub - Default)

```bash
# Install dependencies and setup database
mix setup

# Start the Phoenix server
mix phx.server
```

Visit [`localhost:4000/routing-slip`](http://localhost:4000/routing-slip)

---

## RabbitMQ Setup (Distributed Messaging)

### 1. Start RabbitMQ

```bash
# Start RabbitMQ with management UI
docker-compose up -d

# Verify it's running
docker-compose ps
```

**RabbitMQ Access:**
- AMQP: `localhost:5672`
- Management UI: [localhost:15672](http://localhost:15672) (guest/guest)

### 2. Enable RabbitMQ Messenger

Edit `config/dev.exs` and uncomment the messenger config:

```elixir
# Uncomment this line to use RabbitMQ instead of PubSub
config :routing_examples, :routing_slip_messenger,
  RoutingExamples.RoutingSlip.Messenger.RabbitMQ
```

### 3. Start the Application

```bash
mix phx.server
```

### 4. Verify in RabbitMQ Management UI

1. Open [localhost:15672](http://localhost:15672) (guest/guest)
2. Go to **Exchanges** tab - you should see:
   - `routing_slip.messages` (topic)
   - `routing_slip.events` (fanout)
3. Go to **Queues** tab - as you create nodes, you'll see:
   - `node.validator`, `node.enricher`, etc.

### 5. Watch Messages Flow

1. Register some nodes in the UI
2. Send a message with a routing slip
3. In RabbitMQ Management → **Queues**, watch message counts change
4. The LiveView updates in real-time as messages flow through RabbitMQ!

### Stopping RabbitMQ

```bash
docker-compose down

# To also remove the data volume:
docker-compose down -v
```

---

## How to Use the Demo

### 1. Register Nodes

Create processing nodes by entering names in the "Register Node" form:
- `validator` - validates incoming data
- `enricher` - adds additional data
- `transformer` - transforms the format
- `persister` - saves to storage
- `notifier` - sends notifications

### 2. Build a Routing Slip

Click on registered nodes to add them to your routing slip. The order you click determines the route:

```
validator → enricher → transformer → persister
```

### 3. Send a Message

Enter a payload and click "Send Message". Watch in real-time as:
- The message travels through each node
- Visited nodes show green checkmarks with step numbers
- The current processing node pulses yellow
- Visit counts increment on each node card
- Completed journeys appear in the history

### 4. View Message Details

Click on a completed journey to see the raw JSON message with the full visited history.

---

## Architecture

### PubSub Implementation (Default)

```
┌─────────────────────────────────────────────────────────────┐
│  RoutingSlip.Supervisor                                      │
│  ├── Registry (NodeRegistry)                                │
│  └── DynamicSupervisor (NodeSupervisor)                     │
│       ├── Node GenServer ("validator")                      │
│       ├── Node GenServer ("enricher")                       │
│       └── Node GenServer ("transformer")                    │
├─────────────────────────────────────────────────────────────┤
│  Phoenix.PubSub                                              │
│  └── Topic: "routing_slip:updates"                          │
└─────────────────────────────────────────────────────────────┘
```

### RabbitMQ Implementation

```
┌─────────────────────────────────────────────────────────────┐
│  RabbitMQ.Supervisor                                         │
│  ├── NodeTracker (Agent)                                    │
│  ├── ConsumerRegistry (Registry)                            │
│  ├── ListenersRegistry (Registry)                           │
│  ├── Connection (GenServer - AMQP connection)               │
│  └── ConsumerSupervisor (DynamicSupervisor)                 │
│       ├── NodeConsumer Broadway ("validator")               │
│       ├── NodeConsumer Broadway ("enricher")                │
│       └── NodeConsumer Broadway ("transformer")             │
├─────────────────────────────────────────────────────────────┤
│  RabbitMQ Exchanges                                          │
│  ├── routing_slip.messages (topic)                          │
│  │    └── Routes to: node.* queues                          │
│  └── routing_slip.events (fanout)                           │
│       └── Routes to: per-LiveView exclusive queues          │
├─────────────────────────────────────────────────────────────┤
│  EventsListener (per LiveView)                               │
│  └── Consumes events → sends to LiveView process            │
└─────────────────────────────────────────────────────────────┘
```

---

## Key Files

| File | Description |
|------|-------------|
| `lib/routing_examples/routing_slip.ex` | Context module with public API |
| `lib/routing_examples/routing_slip/messenger.ex` | Messenger behaviour definition |
| `lib/routing_examples/routing_slip/messenger/pubsub.ex` | PubSub implementation |
| `lib/routing_examples/routing_slip/messenger/rabbitmq.ex` | RabbitMQ implementation |
| `lib/routing_examples/routing_slip/messenger/rabbitmq/connection.ex` | AMQP connection manager |
| `lib/routing_examples/routing_slip/messenger/rabbitmq/node_consumer.ex` | Broadway consumer per node |
| `lib/routing_examples/routing_slip/messenger/rabbitmq/events_listener.ex` | Events → LiveView bridge |
| `lib/routing_examples_web/live/routing_slip_live.ex` | LiveView with real-time UI |

---

## Configuration

### Switching Messengers

```elixir
# config/dev.exs

# Use PubSub (default - no config needed)
# config :routing_examples, :routing_slip_messenger,
#   RoutingExamples.RoutingSlip.Messenger.PubSub

# Use RabbitMQ
config :routing_examples, :routing_slip_messenger,
  RoutingExamples.RoutingSlip.Messenger.RabbitMQ

# RabbitMQ connection settings
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

---

## Learn More

### Enterprise Integration Patterns
- [Routing Slip Pattern](https://www.enterpriseintegrationpatterns.com/patterns/messaging/RoutingTable.html)
- [Enterprise Integration Patterns Book](https://www.enterpriseintegrationpatterns.com/)

### Libraries Used
- [Broadway](https://hexdocs.pm/broadway/) - Concurrent data processing
- [BroadwayRabbitMQ](https://hexdocs.pm/broadway_rabbitmq/) - RabbitMQ connector
- [AMQP](https://hexdocs.pm/amqp/) - Elixir AMQP client

### Phoenix Framework
- Official website: https://www.phoenixframework.org/
- Guides: https://hexdocs.pm/phoenix/overview.html
- Docs: https://hexdocs.pm/phoenix
