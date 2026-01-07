# Plan: Process Manager — GDPR User Offboarding

## Overview

Implement the **Process Manager** pattern using a GDPR-compliant user offboarding workflow. The Process Manager acts as a central orchestrator that tracks the state of long-running, multi-step processes, handles parallel execution with scatter/gather semantics, and provides full visibility into workflow progress.

From EIP (page 315):
> *"A Process Manager is a central processing unit that maintains the state of the sequence and determines the next processing step based on intermediate results."*

**Key distinction from Routing Slip**: The Process Manager maintains state externally (not in the message), enabling visibility, human intervention, and complex branching logic.

## Domain: GDPR User Offboarding

When a user requests account deletion (GDPR "right to erasure"), we must:

1. **Gather** all user data from various services
2. **Transfer** ownership of shared assets to designated successors  
3. **Generate** a data export ZIP file
4. **Store** the export in S3 and create a signed download URL
5. **Notify** the user when their export is ready
6. **Purge** user data from all systems
7. **Confirm** deletion and log audit trail

This workflow is perfect for Process Manager because:
- It's long-running (could take minutes to hours)
- Has parallel steps (gather data from multiple sources simultaneously)
- Requires intermediate results (gathered data feeds into the ZIP generation)
- Different users may take different routes (some have shared assets, some don't)
- Needs full auditability for compliance

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                          PROCESS MANAGER ARCHITECTURE                            │
├─────────────────────────────────────────────────────────────────────────────────┤
│                                                                                  │
│  ┌─────────────────────────────────────────────────────────────────────────┐   │
│  │                      PROCESS DEFINITION (Template)                       │   │
│  │                                                                          │   │
│  │   ┌─────────┐    ┌────────────────────────────────┐    ┌───────────┐   │   │
│  │   │ INIT    │───►│       GATHERING DATA           │───►│ PACKAGING │   │   │
│  │   └─────────┘    │   (Scatter/Gather Parallel)    │    └─────┬─────┘   │   │
│  │                  └────────────────────────────────┘          │         │   │
│  │                                                              ▼         │   │
│  │   ┌─────────┐    ┌────────────────────────────────┐    ┌───────────┐   │   │
│  │   │COMPLETE │◄───│         PURGING DATA           │◄───│ UPLOADING │   │   │
│  │   └─────────┘    │   (Scatter/Gather Parallel)    │    └───────────┘   │   │
│  │                  └────────────────────────────────┘                    │   │
│  └─────────────────────────────────────────────────────────────────────────┘   │
│                                                                                  │
│  ┌─────────────────────────────────────────────────────────────────────────┐   │
│  │                       PROCESS INSTANCE (Runtime)                         │   │
│  │                                                                          │   │
│  │   correlation_id: "offboard_user_123_abc"                                │   │
│  │   current_step: "gathering"                                              │   │
│  │   context: %{user_id: "user_123", email: "jane@example.com", ...}       │   │
│  │   intermediate_results: %{                                               │   │
│  │     "gather:documents" => %{status: :completed, data: [...], at: ...},  │   │
│  │     "gather:profile" => %{status: :completed, data: {...}, at: ...},    │   │
│  │     "gather:folders" => %{status: :pending}                              │   │
│  │   }                                                                      │   │
│  │   created_at: ~U[2026-01-06 10:00:00Z]                                  │   │
│  │   updated_at: ~U[2026-01-06 10:05:30Z]                                  │   │
│  └─────────────────────────────────────────────────────────────────────────┘   │
│                                                                                  │
└─────────────────────────────────────────────────────────────────────────────────┘
```

---

## Key Concepts

### 1. Process Definition vs Process Instance (EIP page 315)

**Process Definition (Template)**: The static workflow structure—steps, transitions, and conditions. Defined once, reused for every offboarding.

```elixir
# Process Definition - the "template"
defmodule RoutingExamples.ProcessManager.Offboarding.Definition do
  @steps [
    :init,
    :gathering,        # Scatter/Gather: parallel data collection
    :transferring,     # Optional: transfer shared assets
    :packaging,        # Generate ZIP from gathered data
    :uploading,        # Store in S3, get signed URL
    :notifying,        # Email user with download link
    :purging,          # Scatter/Gather: parallel data deletion
    :completed
  ]
  
  @transitions %{
    init: [:gathering],
    gathering: [:transferring, :packaging],  # Branch based on shared assets
    transferring: [:packaging],
    packaging: [:uploading],
    uploading: [:notifying],
    notifying: [:purging],
    purging: [:completed]
  }
end
```

**Process Instance**: A running execution of the template for a specific user. Contains correlation ID, current state, and all intermediate results.

```elixir
# Process Instance - a "live" execution
%ProcessInstance{
  id: "inst_abc123",
  correlation_id: "offboard_user_123",
  definition: :offboarding,
  current_step: :gathering,
  context: %{
    user_id: "user_123",
    email: "jane@example.com",
    has_shared_assets: true,
    successor_user_id: "user_456"
  },
  intermediate_results: %{...},
  message_history: [...],
  started_at: ~U[2026-01-06 10:00:00Z],
  updated_at: ~U[2026-01-06 10:05:30Z]
}
```

### 2. Correlation IDs

Every message in the system carries a `correlation_id` that links it back to its Process Instance:

```elixir
%Message{
  id: "msg_xyz789",
  correlation_id: "offboard_user_123",  # Links to ProcessInstance
  type: :gather_documents_completed,
  payload: %{documents: [...], count: 42},
  timestamp: ~U[2026-01-06 10:02:15Z]
}
```

The Process Manager uses this to route incoming messages to the correct instance:

```elixir
def handle_message(message) do
  instance = ProcessStore.get_by_correlation_id(message.correlation_id)
  updated_instance = apply_message(instance, message)
  ProcessStore.save(updated_instance)
  broadcast_update(updated_instance)
end
```

### 3. Intermediate Results Storage

Results from each step are stored in the Process Instance, available for downstream steps:

```elixir
%{
  intermediate_results: %{
    "gather:profile" => %{
      status: :completed,
      completed_at: ~U[2026-01-06 10:01:30Z],
      data: %{name: "Jane Doe", email: "jane@example.com", ...}
    },
    "gather:documents" => %{
      status: :completed,
      completed_at: ~U[2026-01-06 10:02:15Z],
      data: [%{id: "doc_1", name: "Report.pdf", size: 1024}, ...]
    },
    "gather:folders" => %{
      status: :completed,
      completed_at: ~U[2026-01-06 10:02:45Z],
      data: [%{id: "folder_1", name: "Projects", item_count: 15}, ...]
    },
    "package:zip" => %{
      status: :completed,
      completed_at: ~U[2026-01-06 10:05:00Z],
      data: %{zip_path: "/tmp/user_123_export.zip", size_bytes: 52428800}
    },
    "upload:s3" => %{
      status: :completed,
      completed_at: ~U[2026-01-06 10:05:30Z],
      data: %{
        bucket: "gdpr-exports",
        key: "exports/user_123/data.zip",
        signed_url: "https://...",
        expires_at: ~U[2026-01-13 10:05:30Z]
      }
    }
  }
}
```

### 4. Scatter/Gather (Parallel Execution with Aggregation)

The "gathering" and "purging" steps use scatter/gather:

```
                            SCATTER/GATHER: DATA GATHERING
┌────────────────────────────────────────────────────────────────────────────────┐
│                                                                                 │
│                          ┌─────────────────┐                                   │
│                          │ Process Manager │                                   │
│                          │  (Orchestrator) │                                   │
│                          └────────┬────────┘                                   │
│                                   │                                            │
│                    ┌──────────────┼──────────────┐                            │
│                    │ SCATTER      │              │                            │
│                    ▼              ▼              ▼                            │
│             ┌───────────┐  ┌───────────┐  ┌───────────┐                       │
│             │  Gather   │  │  Gather   │  │  Gather   │                       │
│             │ Documents │  │  Profile  │  │  Folders  │                       │
│             │  Worker   │  │  Worker   │  │  Worker   │                       │
│             └─────┬─────┘  └─────┬─────┘  └─────┬─────┘                       │
│                   │              │              │                             │
│                   │   GATHER     │              │                             │
│                   ▼              ▼              ▼                             │
│             ┌───────────────────────────────────────┐                         │
│             │        Process Manager                │                         │
│             │  Aggregates results, checks all done  │                         │
│             │  Stores in intermediate_results       │                         │
│             └───────────────────────────────────────┘                         │
│                                                                                │
└────────────────────────────────────────────────────────────────────────────────┘
```

Implementation (using `Task.async_stream` for parallel execution):

```elixir
defmodule RoutingExamples.ProcessManager.Offboarding.Steps.Gathering do
  @moduledoc """
  Scatter/Gather step for collecting user data from multiple sources.
  Uses Task.async_stream for efficient parallel execution with back-pressure.
  """
  
  @gather_tasks [:profile, :documents, :folders, :activity_log, :preferences]
  
  @doc """
  Execute all gather tasks in parallel using Task.async_stream.
  Returns updated instance with results in intermediate_results.
  """
  def execute(instance) do
    # Scatter: Execute all tasks in parallel with Task.async_stream
    # Always use timeout: :infinity for potentially long-running operations
    results =
      @gather_tasks
      |> Task.async_stream(
        fn task -> {task, gather_data(task, instance.context)} end,
        timeout: :infinity,
        max_concurrency: System.schedulers_online()
      )
      |> Enum.reduce(%{}, fn {:ok, {task, data}}, acc ->
        Map.put(acc, "gather:#{task}", %{
          status: :completed,
          completed_at: DateTime.utc_now(),
          data: data
        })
      end)
    
    # Update instance with all gathered results
    %{instance | 
      current_step: :gathering,
      intermediate_results: Map.merge(instance.intermediate_results, results)
    }
  end
  
  @doc """
  Handle individual task completion (for async worker-based approach).
  Uses proper struct field access and rebinds block results.
  """
  def handle_result(instance, task, result) do
    # Update intermediate results using Map functions (not struct access syntax)
    updated_results = Map.put(
      instance.intermediate_results,
      "gather:#{task}",
      %{status: :completed, completed_at: DateTime.utc_now(), data: result}
    )
    
    updated = %{instance | intermediate_results: updated_results}
    
    # Rebind result of conditional - don't modify inside block
    if all_tasks_complete?(updated) do
      transition_to_next_step(updated)
    else
      updated
    end
  end
  
  # Predicate functions use ? suffix (not is_ prefix)
  defp all_tasks_complete?(instance) do
    Enum.all?(@gather_tasks, fn task -> 
      key = "gather:#{task}"
      case Map.get(instance.intermediate_results, key) do
        %{status: :completed} -> true
        _ -> false
      end
    end)
  end
  
  defp gather_data(task, context) do
    # Simulated data gathering - replace with real implementations
    Process.sleep(:rand.uniform(500) + 200)  # Simulate latency
    FakeDataGenerator.generate(task, context)
  end
end
```

### 5. Message History / Message Store

Every message that affects a Process Instance is recorded. Uses a GenServer wrapper around ETS for proper OTP supervision:

```elixir
defmodule RoutingExamples.ProcessManager.MessageStore do
  @moduledoc """
  GenServer-wrapped ETS store for full audit trail.
  
  Stores all messages by correlation_id for:
  - Debugging workflow execution
  - Compliance auditing
  - Replaying failed processes
  
  Uses GenServer to ensure proper lifecycle management under supervision.
  """
  use GenServer
  
  @table_name :process_messages
  
  # ============================================================================
  # Client API
  # ============================================================================
  
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end
  
  @doc "Store a message in the history"
  def store(message) do
    :ets.insert(@table_name, {message.correlation_id, message})
    :ok
  end
  
  @doc "Get full message history for a correlation_id, sorted by timestamp"
  def get_history(correlation_id) do
    @table_name
    |> :ets.lookup(correlation_id)
    |> Enum.map(fn {_id, msg} -> msg end)
    |> Enum.sort_by(fn msg -> msg.timestamp end, DateTime)
  end
  
  @doc "Get messages of a specific type for a correlation_id"
  def get_by_type(correlation_id, type) do
    correlation_id
    |> get_history()
    |> Enum.filter(fn msg -> msg.type == type end)
  end
  
  @doc "Check if any messages exist for a correlation_id"
  def exists?(correlation_id) do
    case :ets.lookup(@table_name, correlation_id) do
      [] -> false
      _ -> true
    end
  end
  
  @doc "Get message count for a correlation_id"
  def count(correlation_id) do
    @table_name
    |> :ets.lookup(correlation_id)
    |> length()
  end
  
  # ============================================================================
  # Server Callbacks
  # ============================================================================
  
  @impl true
  def init(_opts) do
    # Create ETS table owned by this GenServer
    table = :ets.new(@table_name, [:bag, :named_table, :public, read_concurrency: true])
    {:ok, %{table: table}}
  end
  
  @impl true
  def terminate(_reason, state) do
    # ETS table is automatically deleted when owner process terminates
    :ok
  end
end
```

### 6. Conditional Branching (Different Routes)

Users take different paths based on their data:

```elixir
defmodule RoutingExamples.ProcessManager.Offboarding.Router do
  @doc """
  Determines the next step based on process state and context.
  """
  def next_step(instance, completed_step) do
    case {completed_step, instance.context} do
      # After gathering, check if user has shared assets
      {:gathering, %{has_shared_assets: true}} ->
        :transferring
        
      {:gathering, %{has_shared_assets: false}} ->
        :packaging  # Skip transfer step
        
      # Standard linear transitions
      {:transferring, _} -> :packaging
      {:packaging, _} -> :uploading
      {:uploading, _} -> :notifying
      {:notifying, _} -> :purging
      {:purging, _} -> :completed
      
      _ -> raise "Invalid transition from #{completed_step}"
    end
  end
end
```

---

## Module Structure

> **Important**: Each file contains exactly ONE module to avoid cyclic dependencies and compilation errors. Never nest multiple modules in the same file.

```
lib/routing_examples/
├── process_manager.ex                  # Context module (like routing_slip.ex)
│
├── process_manager/
│   ├── core/
│   │   ├── definition.ex               # Process Definition behaviour
│   │   ├── instance.ex                 # ProcessInstance struct
│   │   ├── message.ex                  # Message struct with correlation_id
│   │   ├── step_result.ex              # Step execution result types
│   │   └── transition.ex               # State transition logic
│   │
│   ├── store/
│   │   ├── process_store.ex            # ETS-backed process instance store (GenServer)
│   │   └── message_store.ex            # Message history store (GenServer)
│   │
│   ├── offboarding/
│   │   ├── definition.ex               # Offboarding process definition
│   │   ├── router.ex                   # Conditional routing logic
│   │   ├── test_scenarios.ex           # Test data scenarios
│   │   ├── fake_data_generator.ex      # Simulated data for demos
│   │   └── steps/
│   │       ├── init.ex                 # Initialize offboarding
│   │       ├── gathering.ex            # Scatter: gather user data
│   │       ├── transferring.ex         # Transfer shared assets
│   │       ├── packaging.ex            # Create ZIP from gathered data
│   │       ├── uploading.ex            # Upload to S3 (LocalStack)
│   │       ├── notifying.ex            # Send notification
│   │       └── purging.ex              # Scatter: delete user data
│   │
│   ├── workers/
│   │   ├── worker.ex                   # GenServer worker behaviour
│   │   ├── gather_worker.ex            # Data gathering worker
│   │   ├── purge_worker.ex             # Data purging worker
│   │   └── s3_worker.ex                # S3 upload worker (uses Req for HTTP)
│   │
│   ├── messenger/
│   │   ├── messenger.ex                # Messenger behaviour
│   │   └── pubsub.ex                   # Phoenix.PubSub implementation
│   │
│   └── supervisor.ex                   # Supervision tree with Registry + DynamicSupervisor
│
├── routing_examples_web/
│   └── live/
│       └── process_manager_live.ex     # LiveView for visualization
│
└── test/
    ├── process_manager/
    │   ├── instance_test.exs           # Unit tests for ProcessInstance
    │   ├── store_test.exs              # Tests for ProcessStore (uses start_supervised!)
    │   ├── message_store_test.exs      # Tests for MessageStore
    │   └── gathering_test.exs          # Tests for scatter/gather step
    │
    └── routing_examples_web/
        └── live/
            └── process_manager_live_test.exs  # LiveView tests (uses has_element?)
```

---

## Infrastructure: LocalStack for S3

Add LocalStack to `docker-compose.yml`:

```yaml
services:
  # ... existing rabbitmq service ...
  
  localstack:
    image: localstack/localstack:3.0
    container_name: routing_slip_localstack
    ports:
      - "4566:4566"              # LocalStack gateway
      - "4510-4559:4510-4559"    # External service ports
    environment:
      - SERVICES=s3
      - DEBUG=1
      - PERSISTENCE=1
      - AWS_DEFAULT_REGION=us-east-1
    volumes:
      - localstack_data:/var/lib/localstack
      - "/var/run/docker.sock:/var/run/docker.sock"

volumes:
  rabbitmq_data:
  localstack_data:
```

Add `ex_aws` dependencies to `mix.exs`:

```elixir
defp deps do
  [
    # ... existing deps ...
    # S3 integration with LocalStack
    {:ex_aws, "~> 2.5"},
    {:ex_aws_s3, "~> 2.5"},
    {:sweet_xml, "~> 0.7"},
    # Note: Req is already included in the project for HTTP.
    # We configure ex_aws to use Req's underlying Finch adapter.
  ]
end
```

Configure ex_aws to use Finch (Req's HTTP client) instead of hackney:

```elixir
# config/config.exs
config :ex_aws,
  http_client: ExAws.Request.Finch,
  json_codec: Jason
```

Configure LocalStack in `config/dev.exs`:

```elixir
config :ex_aws,
  access_key_id: "test",
  secret_access_key: "test",
  region: "us-east-1"

config :ex_aws, :s3,
  scheme: "http://",
  host: "localhost",
  port: 4566
```

---

## UI Design: EIP-Style Process Visualization

The UI will show the process flow similar to EIP diagrams, with:
- Process definition as a flowchart
- Real-time highlighting of current step
- Intermediate results visible at each step
- Message history timeline

### Visual Design

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                         GDPR User Offboarding                                    │
│                      Process Manager Demonstration                               │
├─────────────────────────────────────────────────────────────────────────────────┤
│                                                                                  │
│  ┌─────────────────────────────────────────────────────────────────────────┐   │
│  │                     PROCESS FLOW (Live View)                             │   │
│  │                                                                          │   │
│  │   ┌──────┐    ┌───────────┐    ┌────────────┐    ┌─────────┐           │   │
│  │   │ INIT │───►│ GATHERING │───►│TRANSFERRING│───►│PACKAGING│           │   │
│  │   │  ✓   │    │    ◉      │    │     ○      │    │    ○    │           │   │
│  │   └──────┘    └───────────┘    └────────────┘    └─────────┘           │   │
│  │                     │                                  │                │   │
│  │              ┌──────┴──────┐                          │                │   │
│  │              │   No shared │                          ▼                │   │
│  │              │    assets   │────────────────►   ┌─────────┐           │   │
│  │              └─────────────┘                    │UPLOADING│           │   │
│  │                                                 │    ○    │           │   │
│  │   ┌──────────┐    ┌─────────┐    ┌─────────┐   └────┬────┘           │   │
│  │   │ COMPLETE │◄───│ PURGING │◄───│NOTIFYING│◄───────┘                │   │
│  │   │    ○     │    │    ○    │    │    ○    │                         │   │
│  │   └──────────┘    └─────────┘    └─────────┘                         │   │
│  │                                                                          │   │
│  │   Legend:  ✓ Completed   ◉ In Progress   ○ Pending                      │   │
│  └─────────────────────────────────────────────────────────────────────────┘   │
│                                                                                  │
│  ┌─────────────────────────────────────────────────────────────────────────┐   │
│  │                    SCATTER/GATHER: GATHERING                             │   │
│  │                                                                          │   │
│  │   ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐   │   │
│  │   │  Profile    │  │  Documents  │  │   Folders   │  │   Activity  │   │   │
│  │   │     ✓       │  │      ✓      │  │     🔄      │  │      ○      │   │   │
│  │   │  1.2s ago   │  │   0.8s ago  │  │  Running... │  │   Pending   │   │   │
│  │   └─────────────┘  └─────────────┘  └─────────────┘  └─────────────┘   │   │
│  │                                                                          │   │
│  │   Progress: 2/4 tasks complete                    [━━━━━━━━░░░░] 50%    │   │
│  └─────────────────────────────────────────────────────────────────────────┘   │
│                                                                                  │
│  ┌──────────────────────────┐  ┌────────────────────────────────────────────┐ │
│  │    INTERMEDIATE RESULTS  │  │           MESSAGE HISTORY                   │ │
│  │                          │  │                                             │ │
│  │  gather:profile          │  │  10:00:01  process_started                 │ │
│  │  ├─ status: completed    │  │  10:00:02  gather:profile started          │ │
│  │  ├─ data: {name: "Jane"} │  │  10:00:02  gather:documents started        │ │
│  │  └─ completed_at: 10:01  │  │  10:00:03  gather:folders started          │ │
│  │                          │  │  10:00:04  gather:activity started         │ │
│  │  gather:documents        │  │  10:01:15  gather:profile completed ✓      │ │
│  │  ├─ status: completed    │  │  10:01:45  gather:documents completed ✓    │ │
│  │  ├─ data: [42 docs]      │  │  10:02:00  gather:folders running...       │ │
│  │  └─ completed_at: 10:02  │  │                                             │ │
│  │                          │  │                                             │ │
│  └──────────────────────────┘  └────────────────────────────────────────────┘ │
│                                                                                  │
└─────────────────────────────────────────────────────────────────────────────────┘
```

### LiveView Component Structure

Following Phoenix 1.8 and LiveView best practices:

```elixir
defmodule RoutingExamplesWeb.ProcessManagerLive do
  use RoutingExamplesWeb, :live_view
  
  alias RoutingExamples.ProcessManager
  alias RoutingExamples.ProcessManager.{Messenger, TestScenarios}
  
  # Main sections:
  # 1. Header with process info
  # 2. Process flow diagram (similar to EIP diagrams)
  # 3. Scatter/gather task panel (when in parallel step)
  # 4. Intermediate results inspector
  # 5. Message history timeline (uses streams!)
  # 6. Control panel (start new, cancel, retry)
  
  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Messenger.subscribe()
    end
    
    socket =
      socket
      |> assign(:current_process, nil)
      |> assign(:definition, ProcessManager.get_definition(:offboarding))
      |> assign(:test_scenarios, TestScenarios.list_scenarios())
      |> assign(:scenario_form, to_form(%{"scenario_id" => ""}))
      # Use streams for collections to avoid memory issues
      |> stream(:message_history, [])
      |> stream(:processes, ProcessManager.list_active_processes())
    
    {:ok, socket}
  end
  
  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="min-h-screen">
        <%!-- Header with EIP-style title --%>
        <div class="text-center mb-8">
          <h1 class="text-3xl font-bold bg-gradient-to-r from-primary to-accent bg-clip-text text-transparent">
            Process Manager Pattern
          </h1>
          <p class="text-base-content/60 mt-2">
            GDPR User Offboarding — Central orchestration with state tracking
          </p>
        </div>
        
        <div class="grid grid-cols-12 gap-6 max-w-7xl mx-auto">
          <%!-- Main content area --%>
          <div class="col-span-8 space-y-6">
            <.process_flow_diagram 
              definition={@definition}
              instance={@current_process}
            />
            
            <%= if @current_process && scatter_gather_active?(@current_process) do %>
              <.scatter_gather_panel 
                step={@current_process.current_step}
                tasks={get_parallel_tasks(@current_process)}
              />
            <% end %>
            
            <.control_panel 
              process={@current_process}
              scenarios={@test_scenarios}
              form={@scenario_form}
            />
          </div>
          
          <%!-- Sidebar with results and history --%>
          <div class="col-span-4 space-y-6">
            <%= if @current_process do %>
              <.intermediate_results_panel 
                results={@current_process.intermediate_results} 
              />
            <% end %>
            
            <%!-- Message history uses streams for efficiency --%>
            <div class="card bg-base-200 shadow-xl">
              <div class="card-body">
                <h2 class="card-title text-lg">
                  <.icon name="hero-clock" class="size-5" /> Message History
                </h2>
                <div 
                  id="message-history" 
                  phx-update="stream" 
                  class="space-y-2 max-h-64 overflow-y-auto"
                >
                  <div class="hidden only:block text-center py-4 text-base-content/50">
                    <.icon name="hero-inbox" class="size-8 mx-auto mb-2 opacity-50" />
                    <p>No messages yet</p>
                  </div>
                  <div 
                    :for={{id, msg} <- @streams.message_history} 
                    id={id}
                    class="text-sm font-mono p-2 bg-base-300 rounded"
                  >
                    <span class="text-base-content/60">{format_time(msg.timestamp)}</span>
                    <span class={[
                      "ml-2",
                      msg.type == :completed && "text-success",
                      msg.type == :error && "text-error"
                    ]}>{msg.description}</span>
                  </div>
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end
  
  # ============================================================================
  # Event Handlers
  # ============================================================================
  
  @impl true
  def handle_event("start_process", %{"scenario_id" => scenario_id}, socket) do
    case ProcessManager.start_offboarding(scenario_id) do
      {:ok, instance} ->
        socket =
          socket
          |> assign(:current_process, instance)
          |> stream_insert(:processes, instance)
          |> put_flash(:info, "Offboarding started for scenario: #{scenario_id}")
        
        {:noreply, socket}
      
      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to start: #{inspect(reason)}")}
    end
  end
  
  # ============================================================================
  # PubSub Handlers (real-time updates)
  # ============================================================================
  
  @impl true
  def handle_info({:process_started, instance}, socket) do
    socket =
      socket
      |> assign(:current_process, instance)
      |> stream_insert(:message_history, %{
        id: "msg_#{System.unique_integer()}",
        timestamp: DateTime.utc_now(),
        type: :started,
        description: "Process started"
      })
    
    {:noreply, socket}
  end
  
  def handle_info({:step_completed, correlation_id, step, _result}, socket) do
    # Only update if this is our current process
    socket =
      if socket.assigns.current_process &&
         socket.assigns.current_process.correlation_id == correlation_id do
        socket
        |> update(:current_process, &ProcessManager.refresh_instance/1)
        |> stream_insert(:message_history, %{
          id: "msg_#{System.unique_integer()}",
          timestamp: DateTime.utc_now(),
          type: :completed,
          description: "Step #{step} completed"
        })
        # Push event to JS hook for diagram animation
        |> push_event("step_completed", %{step: step})
      else
        socket
      end
    
    {:noreply, socket}
  end
  
  def handle_info({:task_completed, correlation_id, task_id, _result}, socket) do
    socket =
      if socket.assigns.current_process &&
         socket.assigns.current_process.correlation_id == correlation_id do
        socket
        |> update(:current_process, &ProcessManager.refresh_instance/1)
        |> stream_insert(:message_history, %{
          id: "msg_#{System.unique_integer()}",
          timestamp: DateTime.utc_now(),
          type: :task_done,
          description: "Task #{task_id} completed"
        })
      else
        socket
      end
    
    {:noreply, socket}
  end
  
  # ============================================================================
  # Helper Functions
  # ============================================================================
  
  # Predicate functions use ? suffix
  defp scatter_gather_active?(nil), do: false
  defp scatter_gather_active?(process) do
    process.current_step in [:gathering, :purging]
  end
  
  defp get_parallel_tasks(process) do
    # Access struct field directly (not with [] syntax)
    process.intermediate_results
    |> Enum.filter(fn {key, _} -> 
      String.starts_with?(key, "#{process.current_step}:")
    end)
  end
  
  defp format_time(datetime) do
    Calendar.strftime(datetime, "%H:%M:%S")
  end
end
```

---

## Test Scenarios (Different Routes)

Seed data with various user scenarios to demonstrate conditional routing:

```elixir
defmodule RoutingExamples.ProcessManager.TestScenarios do
  @moduledoc """
  Predefined test scenarios demonstrating different offboarding paths.
  
  Each scenario represents a different user type with varying data and
  workflow requirements. Use these to demonstrate conditional routing
  and the scatter/gather pattern.
  """
  
  # Define scenario struct for type safety
  defmodule Scenario do
    @moduledoc false
    defstruct [:id, :name, :description, :user, :expected_path, :notes]
  end
  
  @scenarios [
    %Scenario{
      id: "scenario_1",
      name: "Basic User (No Shared Assets)",
      description: "Standard offboarding path, skips asset transfer step",
      user: %{
        id: "user_basic",
        email: "basic@example.com",
        has_shared_assets: false,
        data_sources: [:profile, :documents, :preferences]
      },
      expected_path: [:init, :gathering, :packaging, :uploading, :notifying, :purging, :completed]
    },
    %Scenario{
      id: "scenario_2", 
      name: "Team Admin (Shared Assets)",
      description: "User with shared folders that need ownership transfer",
      user: %{
        id: "user_admin",
        email: "admin@example.com",
        has_shared_assets: true,
        successor_user_id: "user_new_admin",
        shared_folders: ["team_docs", "projects"],
        data_sources: [:profile, :documents, :folders, :activity_log, :preferences]
      },
      expected_path: [:init, :gathering, :transferring, :packaging, :uploading, :notifying, :purging, :completed]
    },
    %Scenario{
      id: "scenario_3",
      name: "Large Data User",
      description: "User with extensive data, longer gathering phase",
      user: %{
        id: "user_large",
        email: "large@example.com",
        has_shared_assets: false,
        document_count: 5000,
        data_sources: [:profile, :documents, :folders, :activity_log, :preferences, :backups]
      },
      expected_path: [:init, :gathering, :packaging, :uploading, :notifying, :purging, :completed],
      notes: "Demonstrates parallel gathering with many items"
    },
    %Scenario{
      id: "scenario_4",
      name: "Enterprise User (Full Path)",
      description: "Enterprise user with all features: shared assets, large data, custom metadata",
      user: %{
        id: "user_enterprise",
        email: "enterprise@megacorp.com",
        has_shared_assets: true,
        successor_user_id: "user_successor",
        shared_folders: ["department_shared", "cross_team"],
        custom_metadata: %{department: "Engineering", cost_center: "CC-123"},
        data_sources: [:profile, :documents, :folders, :activity_log, :preferences, :integrations, :api_keys]
      },
      expected_path: [:init, :gathering, :transferring, :packaging, :uploading, :notifying, :purging, :completed]
    }
  ]
  
  @doc "List all available test scenarios"
  @spec list_scenarios() :: [Scenario.t()]
  def list_scenarios, do: @scenarios
  
  @doc "Get a scenario by ID"
  @spec get_scenario(String.t()) :: Scenario.t() | nil
  def get_scenario(id) do
    # Access struct field directly (not map syntax)
    Enum.find(@scenarios, fn scenario -> scenario.id == id end)
  end
  
  @doc "Check if a scenario exists"
  @spec exists?(String.t()) :: boolean()
  def exists?(id) do
    Enum.any?(@scenarios, fn scenario -> scenario.id == id end)
  end
  
  @doc "Get scenarios that include the transfer step"
  @spec scenarios_with_transfer() :: [Scenario.t()]
  def scenarios_with_transfer do
    Enum.filter(@scenarios, fn scenario ->
      :transferring in scenario.expected_path
    end)
  end
end
```

---

## Messenger Integration (Reuse from Routing Slip)

We'll follow the same pattern as `RoutingExamples.RoutingSlip.Messenger`:

```elixir
defmodule RoutingExamples.ProcessManager.Messenger do
  @moduledoc """
  Behaviour for message transport in the Process Manager pattern.
  
  Reuses the same abstraction as Routing Slip, allowing:
  - `PubSub` - Phoenix.PubSub for real-time UI updates
  - Extensible for RabbitMQ or other transports
  """
  
  @behaviour RoutingExamples.RoutingSlip.Messenger
  
  @topic "process_manager:updates"
  
  # Event types for Process Manager
  @type event ::
    {:process_started, ProcessInstance.t()}
    | {:step_started, correlation_id :: String.t(), step :: atom()}
    | {:step_completed, correlation_id :: String.t(), step :: atom(), result :: map()}
    | {:task_started, correlation_id :: String.t(), task_id :: String.t()}
    | {:task_completed, correlation_id :: String.t(), task_id :: String.t(), result :: map()}
    | {:process_completed, ProcessInstance.t()}
    | {:process_failed, correlation_id :: String.t(), error :: term()}
    | {:intermediate_result_updated, correlation_id :: String.t(), key :: String.t(), value :: map()}
  
  # Delegate to configured implementation
  def broadcast(event), do: impl().broadcast(event)
  def subscribe, do: impl().subscribe()
  def unsubscribe, do: impl().unsubscribe()
  
  defp impl do
    Application.get_env(
      :routing_examples,
      :process_manager_messenger,
      __MODULE__.PubSub
    )
  end
end
```

---

## Implementation Order

### Phase 1: Core Infrastructure
1. [ ] Create `ProcessInstance` struct and `Message` struct
2. [ ] Implement `ProcessStore` (ETS-backed)
3. [ ] Implement `MessageStore` (ETS-backed)
4. [ ] Create `Supervisor` with Registry and DynamicSupervisor

### Phase 2: Process Definition
5. [ ] Define `Definition` behaviour
6. [ ] Implement `Offboarding.Definition` with steps and transitions
7. [ ] Implement `Offboarding.Router` for conditional branching
8. [ ] Create step modules (init, gathering, etc.) with placeholder logic

### Phase 3: Workers and Execution
9. [ ] Create `Worker` GenServer behaviour
10. [ ] Implement `GatherWorker` for data collection
11. [ ] Implement scatter/gather coordination in `Gathering` step
12. [ ] Add simulated delays and fake data generation

### Phase 4: S3 Integration
13. [ ] Add LocalStack to docker-compose.yml
14. [ ] Add ex_aws dependencies
15. [ ] Implement `S3Worker` for upload and signed URL generation
16. [ ] Test with LocalStack locally

### Phase 5: Messenger and PubSub
17. [ ] Create `ProcessManager.Messenger` following Routing Slip pattern
18. [ ] Implement `Messenger.PubSub` for real-time updates
19. [ ] Add event broadcasting at key points

### Phase 6: LiveView UI
20. [ ] Create `ProcessManagerLive` with basic structure
21. [ ] Implement process flow diagram component (EIP-style)
22. [ ] Add scatter/gather visualization panel
23. [ ] Create intermediate results inspector
24. [ ] Build message history timeline
25. [ ] Add test scenario selector and control panel
26. [ ] Style to match EIP aesthetic and routing slip example

### Phase 7: Testing (Following Best Practices)
27. [ ] Write tests using `start_supervised!/1` for all GenServers
28. [ ] Use `Process.monitor/1` instead of `Process.sleep/1` for async tests
29. [ ] Use `:sys.get_state/1` for synchronization before assertions
30. [ ] Test LiveView with `has_element?/2`, not raw HTML matching
31. [ ] Add integration tests for full workflow execution

Example test structure:

```elixir
defmodule RoutingExamples.ProcessManager.InstanceTest do
  use ExUnit.Case, async: true

  alias RoutingExamples.ProcessManager.{ProcessStore, Instance}

  setup do
    # ✅ GOOD - start_supervised! guarantees cleanup
    store = start_supervised!({ProcessStore, name: :"store_#{System.unique_integer()}"})
    %{store: store}
  end

  test "creates process instance with correct initial state", %{store: store} do
    {:ok, instance} = ProcessStore.create(store, %{user_id: "user_123"})
    
    # Access struct fields directly
    assert instance.current_step == :init
    assert instance.correlation_id != nil
  end

  test "worker completes gather task" do
    {:ok, pid} = start_supervised!({GatherWorker, task: :profile, context: %{}})
    
    GatherWorker.execute(pid)
    
    # ✅ GOOD - use monitor instead of sleep
    ref = Process.monitor(pid)
    assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 5000
  end

  test "process transitions through steps" do
    {:ok, pid} = start_supervised!({ProcessManager, scenario: "scenario_1"})
    
    ProcessManager.start(pid)
    
    # ✅ GOOD - use :sys.get_state for synchronization
    _ = :sys.get_state(pid)
    
    state = ProcessManager.get_state(pid)
    assert state.current_step in [:init, :gathering]
  end
end
```

### Phase 8: Polish
32. [ ] Add comprehensive test scenarios
33. [ ] Add documentation with examples
34. [ ] Final UI polish and animations
35. [ ] Performance profiling for large data scenarios

---

## Key Differences from Routing Slip

| Aspect | Routing Slip | Process Manager |
|--------|--------------|-----------------|
| **State Location** | In the message | External store |
| **Coordination** | Choreography | Orchestration |
| **Parallelism** | Sequential only | Scatter/Gather |
| **Intermediate Data** | Not stored | Full history |
| **Conditional Routes** | Not supported | First-class |
| **Message History** | Visited list | Full audit log |
| **UI Focus** | Message journey | Process state machine |

---

## Questions for Review

1. **Persistence**: Should we use ETS (fast, in-memory) or add Postgres persistence for durability?
2. **Worker Isolation**: Should each parallel task be its own GenServer, or use Task.async_stream?
3. **Error Handling**: How should we handle failed tasks in scatter/gather? Retry? Skip? Fail whole process?
4. **UI Refresh Rate**: Real-time PubSub vs polling for process status?
5. **S3 Signed URL Expiry**: How long should download links be valid (7 days suggested for GDPR)?

---

## Elixir & Phoenix Best Practices

This section documents the modern Elixir/Phoenix patterns we'll follow throughout implementation.

### Elixir Guidelines

#### Struct Access

**Never** use map access syntax on structs. Access fields directly:

```elixir
# ❌ BAD - structs don't implement Access by default
instance[:current_step]

# ✅ GOOD - direct field access
instance.current_step

# ✅ GOOD - pattern matching
%ProcessInstance{current_step: step} = instance
```

#### Parallel Execution with Task.async_stream

Use `Task.async_stream/3` for concurrent operations with back-pressure. **Always** pass `timeout: :infinity` for long-running tasks:

```elixir
defmodule RoutingExamples.ProcessManager.Offboarding.Steps.Gathering do
  @gather_tasks [:profile, :documents, :folders, :activity_log, :preferences]
  
  def execute_parallel(instance) do
    # ✅ GOOD - Task.async_stream with timeout: :infinity
    results =
      @gather_tasks
      |> Task.async_stream(
        fn task -> gather_data(task, instance.context) end,
        timeout: :infinity,
        max_concurrency: System.schedulers_online()
      )
      |> Enum.map(fn {:ok, result} -> result end)
    
    # Aggregate results into intermediate_results
    build_intermediate_results(results)
  end
end
```

#### Process Naming with Registry and DynamicSupervisor

OTP primitives require explicit naming in child specs:

```elixir
defmodule RoutingExamples.ProcessManager.Supervisor do
  use Supervisor

  def start_link(init_arg) do
    Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    children = [
      # ✅ GOOD - explicit names in child specs
      {Registry, keys: :unique, name: RoutingExamples.ProcessManager.InstanceRegistry},
      {DynamicSupervisor, name: RoutingExamples.ProcessManager.WorkerSupervisor, strategy: :one_for_one}
    ]

    Supervisor.init(children, strategy: :one_for_all)
  end
end
```

#### Predicate Function Naming

Use question marks for predicate functions (not `is_` prefix):

```elixir
# ❌ BAD
def is_complete(instance), do: instance.current_step == :completed

# ✅ GOOD
def complete?(instance), do: instance.current_step == :completed
def gathering_complete?(instance), do: all_gather_tasks_complete?(instance)
```

#### Binding Block Expression Results

Always rebind the result of `if`/`case`/`cond` expressions:

```elixir
# ❌ BAD - rebinding inside the block doesn't work
def handle_result(instance, task, result) do
  if all_gather_tasks_complete?(instance) do
    instance = transition_to_next_step(instance)
  end
  instance
end

# ✅ GOOD - rebind the result
def handle_result(instance, task, result) do
  instance =
    if all_gather_tasks_complete?(instance) do
      transition_to_next_step(instance)
    else
      instance
    end
  
  instance
end
```

### Phoenix 1.8 Guidelines

#### LiveView Template Structure

**Always** begin templates with `<Layouts.app flash={@flash}>`:

```elixir
def render(assigns) do
  ~H"""
  <Layouts.app flash={@flash}>
    <div class="min-h-screen">
      <%!-- Content here --%>
    </div>
  </Layouts.app>
  """
end
```

#### Use Core Components

**Always** use the imported `<.icon>` and `<.input>` components:

```elixir
# ✅ GOOD - use core components
~H"""
<.icon name="hero-check-circle" class="size-5 text-success" />

<.form for={@form} id="scenario-form" phx-submit="start_process">
  <.input field={@form[:scenario_id]} type="select" options={@scenarios} label="Select Scenario" />
  <.button type="submit">Start Offboarding</.button>
</.form>
"""
```

#### Conditional Classes with Lists

**Always** use list syntax for conditional classes:

```elixir
~H"""
<div class={[
  "rounded-lg border-2 p-4 transition-all duration-300",
  if(@step_status == :completed, do: "border-success bg-success/10", else: "border-base-300"),
  @current_step == @step && "ring-2 ring-primary animate-pulse"
]}>
  {step_label(@step)}
</div>
"""
```

### LiveView Best Practices

#### Use Streams for Collections

**Always** use streams for message history and other collections to avoid memory issues:

```elixir
def mount(_params, _session, socket) do
  socket =
    socket
    |> assign(:current_process, nil)
    |> stream(:message_history, [])  # ✅ Use stream, not assign
    |> stream(:processes, [])
  
  {:ok, socket}
end

def handle_info({:message_received, message}, socket) do
  {:noreply, stream_insert(socket, :message_history, message)}
end
```

Template with streams:

```elixir
~H"""
<div id="message-history" phx-update="stream" class="space-y-2">
  <div class="hidden only:block text-base-content/50">No messages yet</div>
  <div :for={{id, msg} <- @streams.message_history} id={id} class="text-sm font-mono">
    <span class="text-base-content/60">{format_time(msg.timestamp)}</span>
    <span>{msg.type}</span>
  </div>
</div>
"""
```

#### Colocated JS Hooks

Use colocated hooks with `.` prefix for inline JavaScript:

```elixir
~H"""
<div 
  id="process-flow-diagram" 
  phx-hook=".ProcessFlowDiagram"
  phx-update="ignore"
  class="w-full h-64"
/>

<script :type={Phoenix.LiveView.ColocatedHook} name=".ProcessFlowDiagram">
  export default {
    mounted() {
      this.handleEvent("update_flow", (data) => {
        this.updateDiagram(data);
      });
    },
    updateDiagram(data) {
      // Custom diagram rendering logic
    }
  }
</script>
"""
```

#### PubSub Event Handling

Properly handle PubSub events and rebind socket with `push_event`:

```elixir
@impl true
def handle_info({:step_completed, correlation_id, step, result}, socket) do
  socket =
    socket
    |> update_process_state(correlation_id, step, result)
    |> push_event("step_completed", %{step: step, status: :completed})
  
  {:noreply, socket}
end
```

### Testing Best Practices

#### Use start_supervised!/1

**Always** use `start_supervised!/1` to guarantee cleanup between tests:

```elixir
defmodule RoutingExamples.ProcessManager.InstanceTest do
  use ExUnit.Case, async: true

  setup do
    # ✅ GOOD - guarantees cleanup
    store = start_supervised!({ProcessStore, name: :test_store})
    %{store: store}
  end

  test "creates process instance", %{store: store} do
    instance = ProcessStore.create(store, %{user_id: "user_123"})
    assert instance.current_step == :init
  end
end
```

#### Use Process.monitor Instead of Sleep

**Never** use `Process.sleep/1`. Use `Process.monitor/1` and assert on messages:

```elixir
# ❌ BAD
test "worker completes task" do
  {:ok, pid} = Worker.start_task(:gather_profile, context)
  Process.sleep(1000)  # Don't do this!
  assert Worker.complete?(pid)
end

# ✅ GOOD - use monitor
test "worker completes task" do
  {:ok, pid} = Worker.start_task(:gather_profile, context)
  ref = Process.monitor(pid)
  
  assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 5000
end

# ✅ GOOD - use :sys.get_state for synchronization
test "worker updates state" do
  {:ok, pid} = Worker.start_task(:gather_profile, context)
  Worker.process(pid, some_message)
  
  # Ensure the message was processed before asserting
  _ = :sys.get_state(pid)
  
  assert Worker.get_result(pid) == expected_result
end
```

#### Test Element Presence, Not Content

Use `has_element?/2` instead of testing raw HTML:

```elixir
test "displays process flow diagram", %{conn: conn} do
  {:ok, view, _html} = live(conn, ~p"/process-manager")
  
  # ✅ GOOD - test element presence
  assert has_element?(view, "#process-flow-diagram")
  assert has_element?(view, "#scenario-form")
  assert has_element?(view, "#message-history")
end
```

### HTTP Client

**Always** use the already-included `Req` library for HTTP requests:

```elixir
# ❌ BAD - don't use these
{:httpoison, "~> 2.0"}
{:tesla, "~> 1.0"}

# ✅ GOOD - Req is already included
defmodule RoutingExamples.ProcessManager.Workers.NotifyWorker do
  def send_notification(user_email, download_url) do
    Req.post!("https://api.email.com/send",
      json: %{
        to: user_email,
        subject: "Your data export is ready",
        body: "Download your data: #{download_url}"
      }
    )
  end
end
```

### Tailwind CSS v4

No `tailwind.config.js` needed. Use the new `app.css` import syntax:

```css
/* assets/css/app.css */
@import "tailwindcss" source(none);
@source "../css";
@source "../js";
@source "../../lib/routing_examples_web";

/* Custom properties for process manager theme */
@layer base {
  :root {
    --step-pending: theme(colors.gray.400);
    --step-active: theme(colors.primary);
    --step-complete: theme(colors.success);
  }
}
```

**Never** use `@apply` in raw CSS. Write Tailwind classes directly in templates.

---

## References

- [Process Manager Pattern](https://www.enterpriseintegrationpatterns.com/patterns/messaging/ProcessManager.html) — EIP book
- [Scatter-Gather Pattern](https://www.enterpriseintegrationpatterns.com/patterns/messaging/BroadcastAggregate.html) — EIP book  
- [Correlation Identifier](https://www.enterpriseintegrationpatterns.com/patterns/messaging/CorrelationIdentifier.html) — EIP book
- [Message History](https://www.enterpriseintegrationpatterns.com/patterns/messaging/MessageHistory.html) — EIP book
- [LocalStack Documentation](https://docs.localstack.cloud/user-guide/aws/s3/) — S3 emulation
- [Phoenix 1.8 Release Notes](https://hexdocs.pm/phoenix/1.8.0/changelog.html) — Phoenix framework
- [LiveView Streams Guide](https://hexdocs.pm/phoenix_live_view/Phoenix.LiveView.html#module-streams) — Efficient collection handling

