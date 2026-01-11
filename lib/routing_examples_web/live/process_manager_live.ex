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
      |> assign(:completed_tasks, MapSet.new())
      |> stream(:message_history, [])

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} full_width>
      <div class="min-h-screen" phx-window-keydown="keydown">
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
            live_completed_tasks={@completed_tasks}
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
  attr :live_completed_tasks, :any, default: nil

  defp process_flow_diagram(assigns) do
    # Get workflow context
    context =
      cond do
        assigns.instance -> assigns.instance.context
        assigns.selected_scenario -> assigns.selected_scenario.user
        true -> %{}
      end

    current_step = if assigns.instance, do: assigns.instance.current_step, else: nil
    intermediate_results = if assigns.instance, do: assigns.instance.intermediate_results, else: %{}

    data_sources = Map.get(context, :data_sources, [:profile, :documents, :preferences])
    has_shared_assets = Map.get(context, :has_shared_assets, false)

    # Get completed tasks from intermediate results (for already completed steps)
    gather_results = get_nested_task_results(intermediate_results, "gathering")
    purge_results = get_nested_task_results(intermediate_results, "purging")

    stored_completed_tasks =
      MapSet.new(
        Enum.flat_map([gather_results, purge_results], fn results ->
          results
          |> Enum.filter(fn {_k, v} -> is_map(v) and Map.get(v, :status) == :completed end)
          |> Enum.map(fn {k, _v} -> k end)
        end)
      )

    # Merge with live completed tasks for real-time updates during execution
    live_tasks = assigns.live_completed_tasks || MapSet.new()
    completed_tasks = MapSet.union(stored_completed_tasks, live_tasks)

    # Build steps list
    base_steps = [:init, :gathering]
    transfer_steps = if has_shared_assets, do: [:transferring], else: []
    final_steps = [:packaging, :uploading, :notifying, :purging, :completed]
    all_steps = base_steps ++ transfer_steps ++ final_steps

    # Calculate task grid layout (max 4 per row)
    max_per_row = 4
    task_rows = Enum.chunk_every(data_sources, max_per_row)
    num_task_rows = length(task_rows)

    assigns =
      assigns
      |> assign(:current_step, current_step)
      |> assign(:data_sources, data_sources)
      |> assign(:has_shared_assets, has_shared_assets)
      |> assign(:completed_tasks, completed_tasks)
      |> assign(:all_steps, all_steps)
      |> assign(:task_rows, task_rows)
      |> assign(:num_task_rows, num_task_rows)

    ~H"""
    <div class="card bg-base-200 shadow-xl">
      <div class="card-body p-4">
        <h2 class="card-title text-lg mb-2">
          <.icon name="hero-map" class="size-5" /> Process Flow
        </h2>

        <%!-- Flowchart-style SVG Diagram --%>
        <div class="flex justify-center overflow-x-auto py-4">
          <svg viewBox="0 0 800 600" class="w-full max-w-4xl" style="max-height: 580px;">
            <%!-- Definitions: gradients and arrow markers --%>
            <defs>
              <linearGradient id="pm-gradient" x1="0%" y1="0%" x2="100%" y2="100%">
                <stop offset="0%" stop-color="#8b5cf6"/>
                <stop offset="100%" stop-color="#6d28d9"/>
              </linearGradient>
              <linearGradient id="active-gradient" x1="0%" y1="0%" x2="100%" y2="100%">
                <stop offset="0%" stop-color="#f59e0b"/>
                <stop offset="100%" stop-color="#d97706"/>
              </linearGradient>
              <linearGradient id="done-gradient" x1="0%" y1="0%" x2="100%" y2="100%">
                <stop offset="0%" stop-color="#22c55e"/>
                <stop offset="100%" stop-color="#16a34a"/>
              </linearGradient>
              <%!-- Arrow markers --%>
              <marker id="arrow-gray" markerWidth="3" markerHeight="2.5" refX="2.5" refY="1.25" orient="auto">
                <polygon points="0 0, 3 1.25, 0 2.5" fill="#64748b"/>
              </marker>
              <marker id="arrow-active" markerWidth="3" markerHeight="2.5" refX="2.5" refY="1.25" orient="auto">
                <polygon points="0 0, 3 1.25, 0 2.5" fill="#f59e0b"/>
              </marker>
              <marker id="arrow-done" markerWidth="3" markerHeight="2.5" refX="2.5" refY="1.25" orient="auto">
                <polygon points="0 0, 3 1.25, 0 2.5" fill="#22c55e"/>
              </marker>
              <%!-- Fork/join diamond markers --%>
              <marker id="diamond" markerWidth="12" markerHeight="12" refX="6" refY="6" orient="auto">
                <polygon points="6 0, 12 6, 6 12, 0 6" fill="#475569"/>
              </marker>
            </defs>

            <%!-- Background --%>
            <rect width="800" height="600" fill="#0f172a" rx="12"/>

            <%!-- Center X position --%>
            <% cx = 400 %>

            <%!-- ═══════════════════════════════════════════════════════════════ --%>
            <%!-- PROCESS MANAGER - Central Orchestrator (Top Center) --%>
            <%!-- ═══════════════════════════════════════════════════════════════ --%>
            <g transform={"translate(#{cx}, 50)"}>
              <circle r="38" fill="url(#pm-gradient)" stroke="#a78bfa" stroke-width="3" filter="drop-shadow(0 4px 6px rgba(139, 92, 246, 0.3))"/>
              <text x="0" y="-6" text-anchor="middle" fill="white" font-size="10" font-weight="700">Process</text>
              <text x="0" y="6" text-anchor="middle" fill="white" font-size="10" font-weight="700">Manager</text>
              <text x="0" y="18" text-anchor="middle" fill="#c4b5fd" font-size="7">ORCHESTRATOR</text>
            </g>

            <%!-- Orchestration line from PM to Init --%>
            <line x1={cx} y1="88" x2={cx} y2="105" stroke="#a78bfa" stroke-width="2" stroke-dasharray="4 2" opacity="0.6"/>

            <%!-- ═══════════════════════════════════════════════════════════════ --%>
            <%!-- MAIN FLOW - Sequential Steps --%>
            <%!-- ═══════════════════════════════════════════════════════════════ --%>

            <%!-- Init Step --%>
            <.flow_step step={:init} x={cx} y={125} status={step_status(:init, @current_step, @all_steps)} label="Initialize" />
            <.flow_arrow x1={cx} y1={145} x2={cx} y2={165} status={arrow_status(:init, :gathering, @current_step, @all_steps)} />

            <%!-- ═══════════════════════════════════════════════════════════════ --%>
            <%!-- GATHER PHASE - Fork/Join with Parallel Tasks --%>
            <%!-- ═══════════════════════════════════════════════════════════════ --%>
            <g>
              <%!-- Fork diamond --%>
              <polygon points={"#{cx},180 #{cx+10},190 #{cx},200 #{cx-10},190"} fill={fork_color(:gathering, @current_step, @all_steps)} stroke="#1e293b" stroke-width="1"/>
              <text x={cx} y="215" text-anchor="middle" fill="#60a5fa" font-size="9" font-weight="600">GATHER</text>

              <%!-- Task layout --%>
              <% task_count = length(@data_sources) %>
              <% task_width = 68 %>
              <% total_width = task_count * task_width %>
              <% start_x = cx - div(total_width, 2) + div(task_width, 2) %>

              <%= for {source, idx} <- Enum.with_index(@data_sources) do %>
                <% task_x = start_x + idx * task_width %>
                <%!-- Fork line --%>
                <line x1={cx} y1="200" x2={task_x} y2="225" stroke={task_line_color("gather:#{source}", @current_step, :gathering, @completed_tasks)} stroke-width="1.5"/>
                <%!-- Task --%>
                <.parallel_task label={format_source_full(source)} x={task_x} y={245} status={task_status("gather:#{source}", @current_step, :gathering, @completed_tasks)} />
                <%!-- Join line --%>
                <line x1={task_x} y1="265" x2={cx} y2="290" stroke={task_line_color("gather:#{source}", @current_step, :gathering, @completed_tasks)} stroke-width="1.5"/>
              <% end %>

              <%!-- Join diamond --%>
              <polygon points={"#{cx},290 #{cx+10},300 #{cx},310 #{cx-10},300"} fill={fork_color(:gathering, @current_step, @all_steps)} stroke="#1e293b" stroke-width="1"/>
              <%= if step_status(:gathering, @current_step, @all_steps) == :completed do %>
                <circle cx={cx+15} cy="300" r="6" fill="#22c55e"/>
                <text x={cx+15} y="303" text-anchor="middle" fill="white" font-size="8">✓</text>
              <% end %>
            </g>

            <%!-- Gather → (Transfer?) → Package --%>
            <%= if @has_shared_assets do %>
              <.flow_arrow x1={cx} y1={310} x2={cx} y2={325} status={arrow_status(:gathering, :transferring, @current_step, @all_steps)} />
              <.flow_step step={:transferring} x={cx} y={345} status={step_status(:transferring, @current_step, @all_steps)} label="Transfer" />
              <.flow_arrow x1={cx} y1={365} x2={cx} y2={380} status={arrow_status(:transferring, :packaging, @current_step, @all_steps)} />
            <% else %>
              <.flow_arrow x1={cx} y1={310} x2={cx} y2={380} status={arrow_status(:gathering, :packaging, @current_step, @all_steps)} />
            <% end %>

            <%!-- Processing Row: Package → Upload → Notify --%>
            <.flow_step step={:packaging} x={cx - 80} y={400} status={step_status(:packaging, @current_step, @all_steps)} label="Package" />
            <.flow_arrow x1={cx - 52} y1={400} x2={cx - 28} y2={400} status={arrow_status(:packaging, :uploading, @current_step, @all_steps)} horizontal />
            <.flow_step step={:uploading} x={cx} y={400} status={step_status(:uploading, @current_step, @all_steps)} label="Upload" />
            <.flow_arrow x1={cx + 28} y1={400} x2={cx + 52} y2={400} status={arrow_status(:uploading, :notifying, @current_step, @all_steps)} horizontal />
            <.flow_step step={:notifying} x={cx + 80} y={400} status={step_status(:notifying, @current_step, @all_steps)} label="Notify" />

            <%!-- Arrow down to Package row and then to Purge --%>
            <line x1={cx} y1="380" x2={cx - 80} y2="380" stroke="#475569" stroke-width="1.5"/>
            <.flow_arrow x1={cx + 80} y1={420} x2={cx} y2={440} status={arrow_status(:notifying, :purging, @current_step, @all_steps)} />

            <%!-- ═══════════════════════════════════════════════════════════════ --%>
            <%!-- PURGE PHASE - Fork/Join with Parallel Tasks --%>
            <%!-- ═══════════════════════════════════════════════════════════════ --%>
            <g>
              <%!-- Fork diamond --%>
              <polygon points={"#{cx},455 #{cx+10},465 #{cx},475 #{cx-10},465"} fill={fork_color(:purging, @current_step, @all_steps)} stroke="#1e293b" stroke-width="1"/>
              <text x={cx} y="490" text-anchor="middle" fill="#f87171" font-size="9" font-weight="600">PURGE</text>

              <%!-- Purge tasks --%>
              <% purge_start = cx - div(total_width, 2) + div(task_width, 2) %>

              <%= for {source, idx} <- Enum.with_index(@data_sources) do %>
                <% task_x = purge_start + idx * task_width %>
                <%!-- Fork line --%>
                <line x1={cx} y1="475" x2={task_x} y2="500" stroke={task_line_color("purge:#{source}", @current_step, :purging, @completed_tasks)} stroke-width="1.5"/>
                <%!-- Task --%>
                <.parallel_task label={format_source_full(source)} x={task_x} y={520} status={task_status("purge:#{source}", @current_step, :purging, @completed_tasks)} variant="danger" />
                <%!-- Join line --%>
                <line x1={task_x} y1="540" x2={cx} y2="560" stroke={task_line_color("purge:#{source}", @current_step, :purging, @completed_tasks)} stroke-width="1.5"/>
              <% end %>

              <%!-- Join diamond --%>
              <polygon points={"#{cx},560 #{cx+10},570 #{cx},580 #{cx-10},570"} fill={fork_color(:purging, @current_step, @all_steps)} stroke="#1e293b" stroke-width="1"/>
              <%= if step_status(:purging, @current_step, @all_steps) == :completed do %>
                <circle cx={cx+15} cy="570" r="6" fill="#22c55e"/>
                <text x={cx+15} y="573" text-anchor="middle" fill="white" font-size="8">✓</text>
              <% end %>
            </g>

            <%!-- Final: Done indicator --%>
            <.flow_arrow x1={cx} y1={580} x2={cx + 60} y2={570} status={if @current_step == :completed, do: :completed, else: :pending} />
            <g transform={"translate(#{cx + 100}, 570)"}>
              <%= if @current_step == :completed do %>
                <circle r="25" fill="url(#done-gradient)" stroke="#86efac" stroke-width="2" filter="drop-shadow(0 4px 6px rgba(34, 197, 94, 0.4))"/>
                <text x="0" y="-2" text-anchor="middle" fill="white" font-size="12">✓</text>
                <text x="0" y="10" text-anchor="middle" fill="white" font-size="7" font-weight="600">DONE</text>
              <% else %>
                <circle r="25" fill="#1e293b" stroke="#475569" stroke-width="2"/>
                <text x="0" y="4" text-anchor="middle" fill="#64748b" font-size="7" font-weight="600">DONE</text>
              <% end %>
            </g>

            <%!-- Legend (top left) --%>
            <g transform="translate(25, 25)">
              <rect x="-5" y="-10" width="150" height="24" fill="#1e293b" rx="4" opacity="0.9"/>
              <circle cx="8" cy="0" r="4" fill="#8b5cf6"/>
              <text x="16" y="3" fill="#94a3b8" font-size="7">Manager</text>
              <circle cx="55" cy="0" r="4" fill="#22c55e"/>
              <text x="63" y="3" fill="#94a3b8" font-size="7">Done</text>
              <circle cx="95" cy="0" r="4" fill="#f59e0b"/>
              <text x="103" y="3" fill="#94a3b8" font-size="7">Active</text>
              <circle cx="135" cy="0" r="4" fill="#64748b"/>
              <text x="143" y="3" fill="#94a3b8" font-size="7">Pending</text>
            </g>
          </svg>
        </div>
      </div>
    </div>
    """
  end

  # Flow step component - rounded rectangle for main steps
  attr :step, :atom, required: true
  attr :x, :integer, required: true
  attr :y, :integer, required: true
  attr :status, :atom, required: true
  attr :label, :string, required: true

  defp flow_step(assigns) do
    {fill, stroke, text_fill, glow} = case assigns.status do
      :completed -> {"#166534", "#22c55e", "#fff", "drop-shadow(0 2px 4px rgba(34, 197, 94, 0.3))"}
      :active -> {"#92400e", "#f59e0b", "#fff", "drop-shadow(0 2px 8px rgba(245, 158, 11, 0.5))"}
      _ -> {"#1e293b", "#475569", "#94a3b8", "none"}
    end

    assigns = assigns
      |> assign(:fill, fill)
      |> assign(:stroke, stroke)
      |> assign(:text_fill, text_fill)
      |> assign(:glow, glow)

    ~H"""
    <g transform={"translate(#{@x}, #{@y})"} filter={@glow}>
      <rect x="-28" y="-20" width="56" height="40" rx="8" fill={@fill} stroke={@stroke} stroke-width="2"/>
      <text x="0" y="5" text-anchor="middle" fill={@text_fill} font-size="9" font-weight="600">{@label}</text>
      <%= if @status == :completed do %>
        <circle cx="22" cy="-14" r="7" fill="#22c55e" stroke="#166534" stroke-width="1"/>
        <text x="22" y="-11" text-anchor="middle" fill="white" font-size="8">✓</text>
      <% end %>
      <%= if @status == :active do %>
        <circle cx="22" cy="-14" r="5" fill="#fbbf24">
          <animate attributeName="opacity" values="1;0.4;1" dur="1s" repeatCount="indefinite"/>
        </circle>
      <% end %>
    </g>
    """
  end

  # Parallel task component - smaller boxes for sub-tasks
  attr :label, :string, required: true
  attr :x, :integer, required: true
  attr :y, :integer, required: true
  attr :status, :atom, required: true
  attr :variant, :string, default: "default"

  defp parallel_task(assigns) do
    {fill, stroke, text_fill} = case {assigns.status, assigns.variant} do
      {:completed, _} -> {"#166534", "#22c55e", "#fff"}
      {:active, "danger"} -> {"#7f1d1d", "#ef4444", "#fecaca"}
      {:active, _} -> {"#78350f", "#f59e0b", "#fef3c7"}
      {_, "danger"} -> {"#1e293b", "#475569", "#94a3b8"}
      _ -> {"#1e293b", "#475569", "#94a3b8"}
    end

    assigns = assigns |> assign(:fill, fill) |> assign(:stroke, stroke) |> assign(:text_fill, text_fill)

    ~H"""
    <g transform={"translate(#{@x}, #{@y})"}>
      <rect x="-30" y="-15" width="60" height="30" rx="5" fill={@fill} stroke={@stroke} stroke-width="1.5"/>
      <text x="0" y="4" text-anchor="middle" fill={@text_fill} font-size="8" font-weight="500">{@label}</text>
      <%= if @status == :completed do %>
        <circle cx="24" cy="-9" r="5" fill="#22c55e"/>
        <text x="24" y="-6" text-anchor="middle" fill="white" font-size="7">✓</text>
      <% end %>
      <%= if @status == :active do %>
        <circle cx="24" cy="-9" r="4" fill="#fbbf24">
          <animate attributeName="opacity" values="1;0.3;1" dur="0.8s" repeatCount="indefinite"/>
        </circle>
      <% end %>
    </g>
    """
  end

  # Flow arrow component
  attr :x1, :integer, required: true
  attr :y1, :integer, required: true
  attr :x2, :integer, required: true
  attr :y2, :integer, required: true
  attr :status, :atom, required: true
  attr :horizontal, :boolean, default: false

  defp flow_arrow(assigns) do
    {stroke, marker, dasharray, animate} = case assigns.status do
      :completed -> {"#22c55e", "url(#arrow-done)", "none", false}
      :active -> {"#f59e0b", "url(#arrow-active)", "6 3", true}
      _ -> {"#475569", "url(#arrow-gray)", "none", false}
    end

    assigns = assigns
      |> assign(:stroke, stroke)
      |> assign(:marker, marker)
      |> assign(:dasharray, dasharray)
      |> assign(:animate, animate)

    ~H"""
    <line
      x1={@x1}
      y1={@y1}
      x2={@x2}
      y2={@y2}
      stroke={@stroke}
      stroke-width="2"
      stroke-dasharray={@dasharray}
      marker-end={@marker}
    >
      <%= if @animate do %>
        <animate attributeName="stroke-dashoffset" from="0" to="-18" dur="0.6s" repeatCount="indefinite"/>
      <% end %>
    </line>
    """
  end

  # ============================================================================
  # Flow Diagram Helpers
  # ============================================================================

  # Helper to determine step status
  defp step_status(step, current_step, all_steps) do
    current_idx = Enum.find_index(all_steps, &(&1 == current_step))
    step_idx = Enum.find_index(all_steps, &(&1 == step))

    cond do
      # When process is complete, all steps are completed
      current_step == :completed -> :completed
      step == current_step -> :active
      current_idx && step_idx && step_idx < current_idx -> :completed
      true -> :pending
    end
  end

  # Helper to determine task status
  defp task_status(task_key, current_step, parent_step, completed_tasks) do
    cond do
      MapSet.member?(completed_tasks, task_key) -> :completed
      current_step == parent_step -> :active
      true -> :pending
    end
  end

  # Format source name for display
  defp format_source_full(source) when is_atom(source) do
    source |> Atom.to_string() |> String.capitalize()
  end

  # Determine arrow status between two steps
  defp arrow_status(from_step, to_step, current_step, all_steps) do
    from_idx = Enum.find_index(all_steps, &(&1 == from_step))
    to_idx = Enum.find_index(all_steps, &(&1 == to_step))
    current_idx = Enum.find_index(all_steps, &(&1 == current_step))

    cond do
      current_step == :completed -> :completed
      current_idx && to_idx && current_idx >= to_idx -> :completed
      current_idx && from_idx && current_idx == from_idx -> :active
      true -> :pending
    end
  end

  # Get color for fork/join diamonds
  defp fork_color(step, current_step, all_steps) do
    case step_status(step, current_step, all_steps) do
      :completed -> "#22c55e"
      :active -> "#f59e0b"
      _ -> "#475569"
    end
  end

  # Get line color for task connections
  defp task_line_color(task_key, current_step, parent_step, completed_tasks) do
    case task_status(task_key, current_step, parent_step, completed_tasks) do
      :completed -> "#22c55e"
      :active -> "#f59e0b"
      _ -> "#475569"
    end
  end

  # Extract nested task results from intermediate_results
  # The gather/purge steps store their results under "gathering"/"purging" -> :data -> "gather:xxx"
  defp get_nested_task_results(intermediate_results, step_key) do
    case Map.get(intermediate_results, step_key) do
      %{data: data} when is_map(data) -> data
      _ -> %{}
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
              <kbd class="kbd kbd-xs ml-2 opacity-70">Ctrl+↵</kbd>
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
    process_state = build_process_state(nil, scenario_data)

    {:noreply,
     socket
     |> assign(:selected_scenario, scenario_id)
     |> assign(:selected_scenario_data, scenario_data)
     |> push_event("update_process_flow", %{processState: process_state})}
  end

  # Keyboard shortcut: Ctrl+Enter to start workflow
  def handle_event("keydown", %{"key" => "Enter", "ctrlKey" => true}, socket) do
    if socket.assigns.current_process == nil || !Instance.active?(socket.assigns.current_process) do
      handle_event("start_process", %{"scenario_id" => socket.assigns.selected_scenario}, socket)
    else
      {:noreply, socket}
    end
  end

  def handle_event("keydown", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("start_process", %{"scenario_id" => scenario_id}, socket) do
    case ProcessManager.start_offboarding(scenario_id) do
      {:ok, instance} ->
        socket =
          socket
          |> assign(:current_process, instance)
          |> assign(:completed_tasks, MapSet.new())
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
      |> update(:completed_tasks, &MapSet.put(&1, task_id))
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
    process_state = build_process_state(instance, nil)
    push_event(socket, "update_process_flow", %{processState: process_state})
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

  # Build process state for diagram updates (sent to client via push_event)
  defp build_process_state(instance, scenario_data) do
    # Get context from instance or scenario
    context =
      cond do
        instance -> instance.context
        scenario_data -> scenario_data.user
        true -> %{}
      end

    current_step = if instance, do: instance.current_step, else: nil
    intermediate_results = if instance, do: instance.intermediate_results, else: %{}

    data_sources = Map.get(context, :data_sources, [:profile, :documents, :preferences])
    has_shared_assets = Map.get(context, :has_shared_assets, false)

    # Get completed tasks from gather/purge steps
    gather_results = get_nested_task_results(intermediate_results, "gathering")
    purge_results = get_nested_task_results(intermediate_results, "purging")

    completed_tasks =
      Enum.flat_map([gather_results, purge_results], fn results ->
        results
        |> Enum.filter(fn {_k, v} -> is_map(v) and Map.get(v, :status) == :completed end)
        |> Enum.map(fn {k, _v} -> k end)
      end)

    # Build the steps list based on context
    base_steps = [:init, :gathering]
    transfer_steps = if has_shared_assets, do: [:transferring], else: []
    final_steps = [:packaging, :uploading, :notifying, :purging, :completed]
    all_steps = base_steps ++ transfer_steps ++ final_steps

    %{
      current_step: current_step,
      data_sources: data_sources,
      has_shared_assets: has_shared_assets,
      completed_tasks: completed_tasks,
      all_steps: all_steps
    }
  end
end
