defmodule RoutingExamplesWeb.ProcessManagerLive do
  @moduledoc """
  LiveView for the Process Manager pattern demonstration.

  Features:
  - EIP-style process flow visualization
  - Real-time step and task progress tracking
  - Scatter/gather parallel task panel
  - Intermediate results inspector
  - Message history timeline
  - Test scenario selector
  """
  use RoutingExamplesWeb, :live_view

  alias RoutingExamples.ProcessManager
  alias RoutingExamples.ProcessManager.{Messenger, Offboarding.Definition, Offboarding.TestScenarios}
  alias RoutingExamples.ProcessManager.Core.Instance

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Messenger.subscribe()
    end

    # Get initial scenario data
    initial_scenario = TestScenarios.get_scenario("scenario_1")

    socket =
      socket
      |> assign(:current_process, nil)
      |> assign(:definition, Definition.get())
      |> assign(:test_scenarios, TestScenarios.list_scenarios())
      |> assign(:scenario_form, to_form(%{"scenario_id" => "scenario_1"}))
      |> assign(:selected_scenario, "scenario_1")
      |> assign(:selected_scenario_data, initial_scenario)
      |> stream(:message_history, [])

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} full_width>
      <div class="min-h-screen">
        <%!-- Header with EIP-style title --%>
        <div class="text-center mb-6">
          <h1 class="text-3xl font-bold bg-gradient-to-r from-emerald-400 to-cyan-400 bg-clip-text text-transparent">
            Process Manager Pattern
          </h1>
          <p class="text-base-content/60 mt-2">
            GDPR User Offboarding — Central orchestration with state tracking
          </p>
        </div>

        <div class="space-y-6">
          <%!-- Process Flow Diagram (full width) - includes inline scatter/gather visualization --%>
          <.process_flow_diagram
            definition={@definition}
            instance={@current_process}
            selected_scenario={@selected_scenario_data}
          />

          <%!-- Download Link (when available) - full width --%>
          <%= if @current_process && get_download_url(@current_process) do %>
            <.download_panel
              url={get_download_url(@current_process)}
              uploaded_at={get_download_expiry(@current_process)}
              download_info={get_download_info(@current_process)}
            />
          <% end %>

          <%!-- Two column layout for Control Panel, Results, and History --%>
          <div class="grid grid-cols-1 lg:grid-cols-2 gap-6">
            <%!-- Left column: Control Panel --%>
            <.control_panel
              process={@current_process}
              scenarios={@test_scenarios}
              form={@scenario_form}
              selected={@selected_scenario}
            />

            <%!-- Right column: Intermediate Results --%>
            <%= if @current_process do %>
              <.intermediate_results_panel
                results={@current_process.intermediate_results}
              />
            <% else %>
              <div class="card bg-base-200 shadow-xl">
                <div class="card-body">
                  <h2 class="card-title text-lg">
                    <.icon name="hero-document-text" class="size-5" /> Intermediate Results
                  </h2>
                  <div class="text-center py-4 text-base-content/50">
                    <.icon name="hero-inbox" class="size-8 mx-auto mb-2 opacity-50" />
                    <p class="text-sm">Start a process to see results</p>
                  </div>
                </div>
              </div>
            <% end %>
          </div>

          <%!-- Message History (full width at bottom) --%>
          <.message_history_panel streams={@streams} />
        </div>
      </div>
    </Layouts.app>
    """
  end

  # ============================================================================
  # Components
  # ============================================================================

  attr :definition, :map, required: true
  attr :instance, :any, required: true
  attr :selected_scenario, :map, default: nil

  defp process_flow_diagram(assigns) do
    current_step = if assigns.instance, do: assigns.instance.current_step, else: nil
    intermediate_results = if assigns.instance, do: assigns.instance.intermediate_results, else: %{}

    # Use instance context if running, otherwise fall back to selected scenario
    context =
      cond do
        assigns.instance -> assigns.instance.context
        assigns.selected_scenario -> assigns.selected_scenario.user
        true -> %{}
      end

    has_shared_assets = Map.get(context, :has_shared_assets, false)

    # Get data sources from context to know what parallel tasks exist
    data_sources = Map.get(context, :data_sources, [:profile, :documents, :preferences])

    # Get the actual task statuses from intermediate_results (nested in "gathering" and "purging")
    gather_results = get_nested_task_results(intermediate_results, "gathering")
    purge_results = get_nested_task_results(intermediate_results, "purging")

    # Generate Mermaid diagram definition
    mermaid_def = generate_mermaid_diagram(current_step, intermediate_results, data_sources, gather_results, purge_results, has_shared_assets)

    assigns =
      assigns
      |> assign(:current_step, current_step)
      |> assign(:intermediate_results, intermediate_results)
      |> assign(:mermaid_def, mermaid_def)

    ~H"""
    <div class="card bg-base-200 shadow-xl">
      <div class="card-body">
        <h2 class="card-title text-lg mb-4">
          <.icon name="hero-map" class="size-5" /> Process Flow
        </h2>

        <%!-- Mermaid.js Flowchart - phx-update="ignore" keeps DOM stable, hook handles updates --%>
        <div
          id="mermaid-diagram"
          phx-hook=".MermaidDiagram"
          phx-update="ignore"
          data-diagram={@mermaid_def}
          class="flex justify-center overflow-x-auto py-4 min-h-[500px]"
        >
          <div class="text-center text-base-content/50">
            <span class="loading loading-dots loading-md"></span>
            <p class="text-sm mt-2">Loading diagram...</p>
          </div>
        </div>

        <%!-- Colocated JS Hook for Mermaid - uses pushEvent for updates --%>
        <script :type={Phoenix.LiveView.ColocatedHook} name=".MermaidDiagram">
          export default {
            mounted() {
              this.lastDiagram = null;
              this.renderDiagram();

              // Listen for diagram updates from LiveView
              this.handleEvent("update_diagram", ({diagram}) => {
                if (diagram !== this.lastDiagram) {
                  this.el.dataset.diagram = diagram;
                  this.renderDiagram();
                }
              });
            },
            renderDiagram() {
              const diagramDef = this.el.dataset.diagram;
              if (!diagramDef || !window.mermaid) {
                setTimeout(() => this.renderDiagram(), 100);
                return;
              }

              // Skip if same diagram
              if (diagramDef === this.lastDiagram) return;
              this.lastDiagram = diagramDef;

              const id = `mermaid-${Date.now()}`;

              window.mermaid.render(id, diagramDef).then(({svg}) => {
                this.el.innerHTML = svg;

                const svgEl = this.el.querySelector('svg');
                if (svgEl) {
                  svgEl.style.maxWidth = '100%';
                  svgEl.style.height = 'auto';
                  svgEl.style.minHeight = '450px';

                  // Add subtle glow animation to Process Manager node only
                  const pmNode = svgEl.querySelector('[id*="flowchart-PM"]');
                  if (pmNode) {
                    pmNode.classList.add('pm-glow');
                  }
                }

                // Inject CSS animations if not already present
                if (!document.getElementById('mermaid-animations')) {
                  const style = document.createElement('style');
                  style.id = 'mermaid-animations';
                  style.textContent = `
                    .pm-glow {
                      animation: pmGlow 2s ease-in-out infinite;
                    }
                    @keyframes pmGlow {
                      0%, 100% { filter: drop-shadow(0 0 3px #8b5cf6); }
                      50% { filter: drop-shadow(0 0 8px #a855f7); }
                    }
                  `;
                  document.head.appendChild(style);
                }
              }).catch(err => {
                console.error('Mermaid render error:', err);
                this.el.innerHTML = `<pre class="text-error text-xs">${err.message}</pre>`;
              });
            }
          }
        </script>

        <%!-- Legend --%>
        <div class="flex flex-wrap items-center justify-center gap-4 mt-4 text-sm text-base-content/60">
          <div class="flex items-center gap-2">
            <div class="w-4 h-4 rounded-full bg-violet-500 animate-pulse"></div>
            <span>Process Manager</span>
          </div>
          <div class="flex items-center gap-2">
            <div class="w-3 h-3 rounded bg-emerald-500"></div>
            <span>Completed</span>
          </div>
          <div class="flex items-center gap-2">
            <div class="w-3 h-3 rounded bg-amber-500 animate-pulse"></div>
            <span>In Progress</span>
          </div>
          <div class="flex items-center gap-2">
            <div class="w-3 h-3 rounded bg-slate-500"></div>
            <span>Pending</span>
          </div>
          <div class="flex items-center gap-2">
            <div class="w-3 h-3 rounded bg-cyan-500"></div>
            <span>Parallel Tasks</span>
          </div>
          <div class="flex items-center gap-2">
            <div class="w-6 border-t-2 border-dashed border-base-content/50"></div>
            <span>Events</span>
          </div>
          <div class="flex items-center gap-2">
            <div class="w-6 border-t-2 border-amber-500"></div>
            <span>Commands</span>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # Extract nested task results from intermediate_results
  # The gather/purge steps store their results under "gathering"/"purging" -> :data -> "gather:xxx"
  defp get_nested_task_results(intermediate_results, step_key) do
    case Map.get(intermediate_results, step_key) do
      %{data: data} when is_map(data) -> data
      _ -> %{}
    end
  end

  # Generate Mermaid diagram definition based on process state
  # Shows Process Manager as central coordinator with message flows
  defp generate_mermaid_diagram(current_step, intermediate_results, data_sources, gather_results, purge_results, has_shared_assets) do
    # Define step statuses
    steps = [:init, :gathering, :transferring, :packaging, :uploading, :notifying, :purging, :completed]

    step_classes =
      steps
      |> Enum.map(fn step ->
        status = get_step_status(step, current_step, intermediate_results)
        class_name = case status do
          :completed -> "completed"
          :in_progress -> "active"
          _ -> "pending"
        end
        {step, class_name}
      end)
      |> Map.new()

    # Build gather tasks from data_sources
    gather_tasks =
      data_sources
      |> Enum.map(fn source ->
        source_str = Atom.to_string(source)
        task_key = "gather:#{source_str}"
        task_result = Map.get(gather_results, task_key, %{})
        task_status = Map.get(task_result, :status, :pending)

        class = cond do
          task_status == :completed -> "taskComplete"
          current_step == :gathering -> "taskActive"
          step_classes[:gathering] == "completed" -> "taskComplete"
          true -> "taskPending"
        end

        {source_str |> String.replace("_", " ") |> String.split() |> Enum.map(&String.capitalize/1) |> Enum.join(" "), class, source_str}
      end)

    # Build purge tasks
    purge_tasks =
      data_sources
      |> Enum.map(fn source ->
        source_str = Atom.to_string(source)
        task_key = "purge:#{source_str}"
        task_result = Map.get(purge_results, task_key, %{})
        task_status = Map.get(task_result, :status, :pending)

        class = cond do
          task_status == :completed -> "taskComplete"
          current_step == :purging -> "taskActive"
          step_classes[:purging] == "completed" -> "taskComplete"
          true -> "taskPending"
        end

        {source_str |> String.replace("_", " ") |> String.split() |> Enum.map(&String.capitalize/1) |> Enum.join(" "), class, source_str}
      end)

    # Determine Process Manager class based on current activity
    pm_class = if current_step in [:init, nil, :completed], do: "processManager", else: "processManagerActive"

    # Track link indexes for styling active connections
    # We'll number each link and style them based on current step
    gather_task_count = length(gather_tasks)
    purge_task_count = length(purge_tasks)

    # Build the Mermaid diagram with Process Manager as central coordinator
    """
    flowchart LR
      classDef completed fill:#10b981,stroke:#059669,color:#fff,stroke-width:2px
      classDef active fill:#f59e0b,stroke:#d97706,color:#fff,stroke-width:3px
      classDef pending fill:#475569,stroke:#64748b,color:#94a3b8,stroke-width:1px
      classDef taskComplete fill:#2dd4bf,stroke:#14b8a6,color:#0d3d3d,stroke-width:2px
      classDef taskActive fill:#fbbf24,stroke:#f59e0b,color:#78350f,stroke-width:2px
      classDef taskPending fill:#64748b,stroke:#475569,color:#e2e8f0,stroke-width:1px
      classDef processManager fill:#8b5cf6,stroke:#7c3aed,color:#fff,stroke-width:3px
      classDef processManagerActive fill:#a855f7,stroke:#9333ea,color:#fff,stroke-width:4px

      %% Process Manager - The Central Coordinator
      PM((("🎯 Process<br/>Manager"))):::#{pm_class}

      subgraph workflow[" "]
        direction TB

        %% Initialize
        INIT[["🚀 Init"]]:::#{step_classes[:init]}

        %% Gathering Phase
        subgraph gather["📥 Gather Data"]
          direction LR
          #{Enum.map_join(gather_tasks, "\n        ", fn {name, class, id} -> "G_#{String.upcase(id)}[\"#{name}\"]:::#{class}" end)}
        end

    #{if has_shared_assets do
      "    TRANSFER[\"🔄 Transfer\"]:::#{step_classes[:transferring]}"
    else
      ""
    end}

        %% Sequential Steps
        PACKAGE[\"📦 Package\"]:::#{step_classes[:packaging]}
        UPLOAD[\"☁️ Upload\"]:::#{step_classes[:uploading]}
        NOTIFY[\"📧 Notify\"]:::#{step_classes[:notifying]}

        %% Purging Phase
        subgraph purge["🗑️ Purge Data"]
          direction LR
          #{Enum.map_join(purge_tasks, "\n        ", fn {name, class, id} -> "P_#{String.upcase(id)}[\"#{name}\"]:::#{class}" end)}
        end

        DONE[["✅ Done"]]:::#{step_classes[:completed]}
      end

      %% Message flows TO Process Manager (results/events)
      INIT -.->|"started"| PM
      #{Enum.map_join(gather_tasks, "\n    ", fn {_name, _class, id} -> "G_#{String.upcase(id)} -.->|\"data\"| PM" end)}
    #{if has_shared_assets do
      "  TRANSFER -.->|\"transferred\"| PM"
    else
      ""
    end}
      PACKAGE -.->|\"packaged\"| PM
      UPLOAD -.->|\"uploaded\"| PM
      NOTIFY -.->|\"notified\"| PM
      #{Enum.map_join(purge_tasks, "\n    ", fn {_name, _class, id} -> "P_#{String.upcase(id)} -.->|\"purged\"| PM" end)}

      %% Commands FROM Process Manager (orchestration)
      PM ==>|"#{if current_step == :init, do: "▶ execute", else: "execute"}"| INIT
      PM ==>|"#{if current_step == :gathering, do: "▶ scatter", else: "scatter"}"| gather
    #{if has_shared_assets do
      "  PM ==>|\"#{if current_step == :transferring, do: "▶ transfer", else: "transfer"}\"| TRANSFER"
    else
      ""
    end}
      PM ==>|"#{if current_step == :packaging, do: "▶ package", else: "package"}"| PACKAGE
      PM ==>|"#{if current_step == :uploading, do: "▶ upload", else: "upload"}"| UPLOAD
      PM ==>|"#{if current_step == :notifying, do: "▶ notify", else: "notify"}"| NOTIFY
      PM ==>|"#{if current_step == :purging, do: "▶ scatter", else: "scatter"}"| purge
      PM ==>|"#{if current_step == :completed, do: "▶ complete", else: "complete"}"| DONE

      %% Workflow sequence
      INIT --> gather
    #{if has_shared_assets do
      """
        gather --> TRANSFER
        TRANSFER --> PACKAGE
      """
    else
      "  gather --> PACKAGE"
    end}
      PACKAGE --> UPLOAD
      UPLOAD --> NOTIFY
      NOTIFY --> purge
      purge --> DONE

      %% Link styling for active connections
    #{generate_link_styles(current_step, gather_task_count, purge_task_count, has_shared_assets)}
    """
  end

  # Generate link styles to highlight active message flows
  defp generate_link_styles(current_step, _gather_count, _purge_count, _has_shared_assets) do
    case current_step do
      :init -> "linkStyle 0 stroke:#f59e0b,stroke-width:3px"
      :gathering -> "linkStyle 1 stroke:#f59e0b,stroke-width:3px"
      :transferring -> "linkStyle 2 stroke:#f59e0b,stroke-width:3px"
      :packaging -> "linkStyle 3 stroke:#f59e0b,stroke-width:3px"
      :uploading -> "linkStyle 4 stroke:#f59e0b,stroke-width:3px"
      :notifying -> "linkStyle 5 stroke:#f59e0b,stroke-width:3px"
      :purging -> "linkStyle 6 stroke:#f59e0b,stroke-width:3px"
      :completed -> "linkStyle 7 stroke:#10b981,stroke-width:3px"
      _ -> ""
    end
  end

  attr :process, :any, required: true
  attr :scenarios, :list, required: true
  attr :form, :any, required: true
  attr :selected, :string, required: true

  defp control_panel(assigns) do
    ~H"""
    <div class="card bg-base-200 shadow-xl">
      <div class="card-body">
        <h2 class="card-title text-lg">
          <.icon name="hero-play-circle" class="size-5" /> Control Panel
        </h2>

        <.form for={@form} id="scenario-form" phx-submit="start_process" phx-change="select_scenario" class="space-y-4">
          <div class="form-control">
            <label class="label">
              <span class="label-text font-medium">Select Test Scenario</span>
            </label>
            <select name="scenario_id" class="select select-bordered w-full">
              <%= for scenario <- @scenarios do %>
                <option value={scenario.id} selected={scenario.id == @selected}>
                  {scenario.name}
                </option>
              <% end %>
            </select>
          </div>

          <%!-- Scenario description --%>
          <%= if selected_scenario = Enum.find(@scenarios, & &1.id == @selected) do %>
            <div class="p-3 bg-base-300 rounded-lg text-sm">
              <p class="text-base-content/70">{selected_scenario.description}</p>
              <div class="flex flex-wrap gap-2 mt-2">
                <span class="badge badge-ghost badge-sm">
                  {length(selected_scenario.expected_path)} steps
                </span>
                <%= if :transferring in selected_scenario.expected_path do %>
                  <span class="badge badge-warning badge-sm">Has Shared Assets</span>
                <% end %>
              </div>
            </div>
          <% end %>

          <.button
            type="submit"
            class="btn btn-primary w-full"
            disabled={@process != nil && Instance.active?(@process)}
          >
            <%= if @process && Instance.active?(@process) do %>
              <span class="loading loading-spinner loading-sm"></span>
              Process Running...
            <% else %>
              <.icon name="hero-play" class="size-4" />
              Start Offboarding
            <% end %>
          </.button>
        </.form>

        <%!-- Current process info --%>
        <%= if @process do %>
          <div class="divider text-xs">Current Process</div>
          <div class="text-sm font-mono space-y-1">
            <div class="flex justify-between">
              <span class="text-base-content/60">ID:</span>
              <span class="text-xs">{@process.correlation_id}</span>
            </div>
            <div class="flex justify-between">
              <span class="text-base-content/60">Step:</span>
              <span class="badge badge-sm">{@process.current_step}</span>
            </div>
            <div class="flex justify-between">
              <span class="text-base-content/60">Started:</span>
              <span>{format_time(@process.started_at)}</span>
            </div>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  attr :url, :string, required: true
  attr :uploaded_at, :any, required: true
  attr :download_info, :map, default: nil

  defp download_panel(assigns) do
    ~H"""
    <div class="card bg-gradient-to-r from-success/20 to-emerald-500/20 shadow-xl border-2 border-success">
      <div class="card-body">
        <div class="flex flex-row items-center justify-between gap-4">
          <div>
            <h2 class="card-title text-lg text-success">
              <.icon name="hero-arrow-down-tray" class="size-5" /> Download Ready!
            </h2>
            <p class="text-sm text-base-content/70">
              Your data export is ready for download.
            </p>
            <p class="text-xs text-base-content/50 mt-1">
              Uploaded: {format_datetime(@uploaded_at)}
            </p>
          </div>
          <a
            href={@url}
            class="btn btn-success gap-2 shrink-0"
          >
            <.icon name="hero-arrow-down-tray" class="size-5" />
            Download Export
          </a>
        </div>

        <%!-- Download tracking info --%>
        <%= if @download_info do %>
          <div class="mt-3 pt-3 border-t border-success/30">
            <div class="flex items-center gap-2 text-sm text-success">
              <.icon name="hero-check-badge" class="size-4" />
              <span>Downloaded at {format_datetime(@download_info.downloaded_at)}</span>
            </div>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  attr :results, :map, required: true

  defp intermediate_results_panel(assigns) do
    ~H"""
    <div class="card bg-base-200 shadow-xl">
      <div class="card-body">
        <h2 class="card-title text-lg">
          <.icon name="hero-document-text" class="size-5" /> Intermediate Results
        </h2>

        <%= if map_size(@results) == 0 do %>
          <div class="text-center py-4 text-base-content/50">
            <.icon name="hero-inbox" class="size-8 mx-auto mb-2 opacity-50" />
            <p class="text-sm">No results yet</p>
          </div>
        <% else %>
          <div class="space-y-2 max-h-64 overflow-y-auto">
            <%= for {key, value} <- @results do %>
              <.result_item key={key} value={value} />
            <% end %>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  attr :key, :string, required: true
  attr :value, :map, required: true

  defp result_item(assigns) do
    status = Map.get(assigns.value, :status, :unknown)
    assigns = assign(assigns, :status, status)

    ~H"""
    <details class="group bg-base-300 rounded-lg">
      <summary class="flex items-center justify-between cursor-pointer p-3 text-sm font-medium">
        <div class="flex items-center gap-2">
          <%= if @status == :completed do %>
            <.icon name="hero-check-circle" class="size-4 text-success" />
          <% else %>
            <.icon name="hero-clock" class="size-4 text-warning" />
          <% end %>
          <span>{@key}</span>
        </div>
        <.icon name="hero-chevron-down" class="size-4 transition-transform group-open:rotate-180" />
      </summary>
      <div class="px-3 pb-3">
        <pre class="text-xs bg-base-100 p-2 rounded overflow-x-auto"><code>{inspect(@value, pretty: true, limit: 5)}</code></pre>
      </div>
    </details>
    """
  end

  attr :streams, :any, required: true

  defp message_history_panel(assigns) do
    ~H"""
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
            <p class="text-sm">No messages yet</p>
          </div>
          <div
            :for={{id, msg} <- @streams.message_history}
            id={id}
            class="text-sm font-mono p-2 bg-base-300 rounded flex items-start gap-2"
          >
            <span class="text-base-content/60 shrink-0">{format_time(msg.timestamp)}</span>
            <span class={[
              message_type_class(msg.type)
            ]}>{msg.description}</span>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # ============================================================================
  # Event Handlers
  # ============================================================================

  @impl true
  def handle_event("select_scenario", %{"scenario_id" => scenario_id}, socket) do
    scenario_data = TestScenarios.get_scenario(scenario_id)

    # Generate new diagram for this scenario
    context = scenario_data.user
    data_sources = Map.get(context, :data_sources, [:profile, :documents, :preferences])
    has_shared_assets = Map.get(context, :has_shared_assets, false)
    mermaid_def = generate_mermaid_diagram(nil, %{}, data_sources, %{}, %{}, has_shared_assets)

    {:noreply,
     socket
     |> assign(:selected_scenario, scenario_id)
     |> assign(:selected_scenario_data, scenario_data)
     |> push_event("update_diagram", %{diagram: mermaid_def})}
  end

  def handle_event("start_process", %{"scenario_id" => scenario_id}, socket) do
    case ProcessManager.start_offboarding(scenario_id) do
      {:ok, instance} ->
        socket =
          socket
          |> assign(:current_process, instance)
          |> stream(:message_history, [], reset: true)
          |> add_message(:started, "Process started")
          |> put_flash(:info, "Offboarding started!")

        {:noreply, socket}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to start: #{inspect(reason)}")}
    end
  end

  # ============================================================================
  # PubSub Handlers
  # ============================================================================

  @impl true
  def handle_info({:process_started, instance}, socket) do
    socket =
      socket
      |> assign(:current_process, instance)
      |> add_message(:started, "Process initialized")
      |> push_diagram_update(instance)

    {:noreply, socket}
  end

  def handle_info({:step_started, correlation_id, step}, socket) do
    socket = maybe_update_process(socket, correlation_id, fn socket ->
      socket
      |> add_message(:info, "Step #{step} started")
      |> push_diagram_update()
    end)

    {:noreply, socket}
  end

  def handle_info({:step_completed, correlation_id, step, _result}, socket) do
    socket = maybe_update_process(socket, correlation_id, fn socket ->
      socket
      |> update(:current_process, &ProcessManager.refresh_instance/1)
      |> add_message(:success, "Step #{step} completed ✓")
      |> push_diagram_update()
    end)

    {:noreply, socket}
  end

  def handle_info({:task_started, correlation_id, task_id}, socket) do
    socket = maybe_update_process(socket, correlation_id, fn socket ->
      socket
      |> update(:current_process, &ProcessManager.refresh_instance/1)
      |> add_message(:info, "Task #{format_task_name(task_id)} started")
    end)

    {:noreply, socket}
  end

  def handle_info({:task_completed, correlation_id, task_id, _result}, socket) do
    socket = maybe_update_process(socket, correlation_id, fn socket ->
      socket
      |> update(:current_process, &ProcessManager.refresh_instance/1)
      |> add_message(:success, "Task #{format_task_name(task_id)} done ✓")
    end)

    {:noreply, socket}
  end

  def handle_info({:process_completed, instance}, socket) do
    socket =
      socket
      |> assign(:current_process, instance)
      |> add_message(:success, "🎉 Process completed!")
      |> put_flash(:info, "Offboarding completed successfully!")
      |> push_diagram_update(instance)

    {:noreply, socket}
  end

  def handle_info({:process_failed, correlation_id, error}, socket) do
    socket = maybe_update_process(socket, correlation_id, fn socket ->
      socket
      |> update(:current_process, &ProcessManager.refresh_instance/1)
      |> add_message(:error, "Process failed: #{inspect(error)}")
      |> put_flash(:error, "Process failed!")
    end)

    {:noreply, socket}
  end

  def handle_info({:export_downloaded, correlation_id, download_event}, socket) do
    socket = maybe_update_process(socket, correlation_id, fn socket ->
      socket
      |> update(:current_process, &ProcessManager.refresh_instance/1)
      |> add_message(:success, "📥 Export downloaded at #{format_time(download_event.downloaded_at)}")
    end)

    {:noreply, socket}
  end

  def handle_info(_msg, socket) do
    {:noreply, socket}
  end

  # ============================================================================
  # Helper Functions
  # ============================================================================

  defp maybe_update_process(socket, correlation_id, update_fn) do
    current = socket.assigns.current_process

    if current && current.correlation_id == correlation_id do
      update_fn.(socket)
    else
      socket
    end
  end

  defp add_message(socket, type, description) do
    msg = %{
      id: "msg_#{System.unique_integer([:positive])}",
      timestamp: DateTime.utc_now(),
      type: type,
      description: description
    }

    stream_insert(socket, :message_history, msg, at: 0)
  end

  # Push diagram update to client - uses current_process from socket
  defp push_diagram_update(socket) do
    case socket.assigns.current_process do
      nil -> socket
      instance -> push_diagram_update(socket, instance)
    end
  end

  # Push diagram update with explicit instance
  defp push_diagram_update(socket, instance) do
    context = instance.context
    current_step = instance.current_step
    intermediate_results = instance.intermediate_results

    data_sources = Map.get(context, :data_sources, [:profile, :documents, :preferences])
    has_shared_assets = Map.get(context, :has_shared_assets, false)

    gather_results = get_nested_task_results(intermediate_results, "gathering")
    purge_results = get_nested_task_results(intermediate_results, "purging")

    mermaid_def = generate_mermaid_diagram(current_step, intermediate_results, data_sources, gather_results, purge_results, has_shared_assets)

    push_event(socket, "update_diagram", %{diagram: mermaid_def})
  end

  defp get_step_status(step_id, current_step, intermediate_results) do
    cond do
      # If current step is :completed, the completed step should show as completed, not in_progress
      step_id == :completed and current_step == :completed -> :completed
      step_id == current_step -> :in_progress
      step_completed?(step_id, intermediate_results) -> :completed
      # If we've reached completed, all previous steps are done
      current_step == :completed -> :completed
      true -> :pending
    end
  end

  defp step_completed?(step_id, intermediate_results) do
    key = Atom.to_string(step_id)
    case Map.get(intermediate_results, key) do
      %{status: :completed} -> true
      _ -> false
    end
  end

  defp message_type_class(:success), do: "text-success"
  defp message_type_class(:error), do: "text-error"
  defp message_type_class(:info), do: "text-info"
  defp message_type_class(:started), do: "text-primary"
  defp message_type_class(_), do: ""

  defp format_task_name(task_id) when is_binary(task_id) do
    task_id
    |> String.split(":")
    |> List.last()
    |> String.capitalize()
  end

  defp format_time(nil), do: "--:--:--"
  defp format_time(datetime) do
    Calendar.strftime(datetime, "%H:%M:%S")
  end

  defp format_datetime(nil), do: "N/A"
  defp format_datetime(datetime) do
    Calendar.strftime(datetime, "%Y-%m-%d %H:%M")
  end

  defp get_download_url(%Instance{intermediate_results: results, correlation_id: correlation_id}) do
    case Map.get(results, "uploading") do
      %{data: %{download_path: _path}} ->
        # Use our API endpoint for tracked downloads
        "/api/exports/#{correlation_id}/download"
      %{data: %{signed_url: url}} ->
        # Fallback to direct S3 URL if that's what we have
        url
      _ ->
        nil
    end
  end
  defp get_download_url(_), do: nil

  defp get_download_expiry(%Instance{intermediate_results: results}) do
    case Map.get(results, "uploading") do
      %{data: %{uploaded_at: uploaded_at}} ->
        # Downloads via API don't expire, but show when it was uploaded
        uploaded_at
      %{data: %{expires_at: expires_at}} ->
        expires_at
      _ ->
        nil
    end
  end
  defp get_download_expiry(_), do: nil

  defp get_download_info(%Instance{intermediate_results: results}) do
    case Map.get(results, "uploading") do
      %{download_info: info} -> info
      _ -> nil
    end
  end
  defp get_download_info(_), do: nil
end
