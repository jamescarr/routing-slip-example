# Routing Examples

A Phoenix LiveView application demonstrating Enterprise Integration Patterns, specifically the **Routing Slip** pattern.

## Routing Slip Pattern

The Routing Slip pattern allows a message to carry its own itinerary, specifying the sequence of processing steps it should follow. Each processor:

1. Receives the message
2. Processes it (adds itself to the "visited" list)
3. Removes itself from the routing slip
4. Forwards to the next destination

This demo provides a real-time visualization of messages flowing through dynamically registered GenServer nodes.

## Getting Started

### Prerequisites

- Elixir 1.15+
- PostgreSQL (for Ash/Ecto)

### Setup

```bash
# Install dependencies and setup database
mix setup

# Start the Phoenix server
mix phx.server

# Or start inside IEx for interactive debugging
iex -S mix phx.server
```

### Access the Demo

Visit [`localhost:4000/routing-slip`](http://localhost:4000/routing-slip) in your browser.

## How to Use

### 1. Register Nodes

Create GenServer nodes by entering names in the "Register Node" form. Example node names:
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

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                     Application                              │
├─────────────────────────────────────────────────────────────┤
│  RoutingSlip.Supervisor                                      │
│  ├── Registry (NodeRegistry)                                │
│  └── DynamicSupervisor (NodeSupervisor)                     │
│       ├── Node GenServer ("validator")                      │
│       ├── Node GenServer ("enricher")                       │
│       └── Node GenServer ("transformer")                    │
├─────────────────────────────────────────────────────────────┤
│  Phoenix.PubSub                                              │
│  └── Topic: "routing_slip:updates"                          │
│       ├── {:node_created, name}                             │
│       ├── {:message_started, message}                       │
│       ├── {:message_processed, node_name, message}          │
│       └── {:message_completed, message}                     │
├─────────────────────────────────────────────────────────────┤
│  RoutingSlipLive (LiveView)                                  │
│  └── Subscribes to PubSub for real-time updates             │
└─────────────────────────────────────────────────────────────┘
```

## Key Files

| File | Description |
|------|-------------|
| `lib/routing_examples/routing_slip.ex` | Context module with public API |
| `lib/routing_examples/routing_slip/node.ex` | GenServer for each routing node |
| `lib/routing_examples/routing_slip/supervisor.ex` | Supervisor for Registry & DynamicSupervisor |
| `lib/routing_examples_web/live/routing_slip_live.ex` | LiveView with real-time UI |

## Learn More

### Enterprise Integration Patterns
- [Routing Slip Pattern](https://www.enterpriseintegrationpatterns.com/patterns/messaging/RoutingTable.html)
- [Enterprise Integration Patterns Book](https://www.enterpriseintegrationpatterns.com/)

### Phoenix Framework
- Official website: https://www.phoenixframework.org/
- Guides: https://hexdocs.pm/phoenix/overview.html
- Docs: https://hexdocs.pm/phoenix
- Forum: https://elixirforum.com/c/phoenix-forum
