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

    socket =
      socket
      |> assign(:current_process, nil)
      |> assign(:definition, Definition.get())
      |> assign(:test_scenarios, TestScenarios.list_scenarios())
      |> assign(:scenario_form, to_form(%{"scenario_id" => "scenario_1"}))
      |> assign(:selected_scenario, "scenario_1")
      |> stream(:message_history, [])

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="min-h-screen">
        <%!-- Header with EIP-style title --%>
        <div class="text-center mb-8">
          <h1 class="text-3xl font-bold bg-gradient-to-r from-emerald-400 to-cyan-400 bg-clip-text text-transparent">
            Process Manager Pattern
          </h1>
          <p class="text-base-content/60 mt-2">
            GDPR User Offboarding — Central orchestration with state tracking
          </p>
        </div>

        <div class="max-w-7xl mx-auto px-4 space-y-6">
          <%!-- Process Flow Diagram (full width) - includes inline scatter/gather visualization --%>
          <.process_flow_diagram
            definition={@definition}
            instance={@current_process}
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

  defp process_flow_diagram(assigns) do
    steps = assigns.definition.steps
    current_step = if assigns.instance, do: assigns.instance.current_step, else: nil
    intermediate_results = if assigns.instance, do: assigns.instance.intermediate_results, else: %{}
    parallel_tasks = if assigns.instance, do: get_parallel_tasks(assigns.instance), else: %{}

    # Check if we should show expanded scatter/gather for gathering or purging
    show_scatter_gather = current_step in [:gathering, :purging] and map_size(parallel_tasks) > 0

    assigns =
      assigns
      |> assign(:steps, steps)
      |> assign(:current_step, current_step)
      |> assign(:intermediate_results, intermediate_results)
      |> assign(:parallel_tasks, parallel_tasks)
      |> assign(:show_scatter_gather, show_scatter_gather)

    ~H"""
    <div class="card bg-base-200 shadow-xl">
      <div class="card-body">
        <h2 class="card-title text-lg mb-4">
          <.icon name="hero-map" class="size-5" /> Process Flow
        </h2>

        <%!-- Step Flow Visualization --%>
        <div class="flex flex-wrap items-center justify-center gap-2">
          <%= for {step, idx} <- Enum.with_index(@steps) do %>
            <%= if @show_scatter_gather && step.id == @current_step do %>
              <%!-- Expanded scatter/gather visualization --%>
              <.scatter_gather_flow_node
                step={step}
                tasks={@parallel_tasks}
                status={get_step_status(step.id, @current_step, @intermediate_results)}
              />
            <% else %>
              <.step_node
                step={step}
                status={get_step_status(step.id, @current_step, @intermediate_results)}
                is_current={step.id == @current_step}
              />
            <% end %>
            <%= if idx < length(@steps) - 1 do %>
              <.step_arrow
                from={step.id}
                to={Enum.at(@steps, idx + 1).id}
                active={step_completed?(step.id, @intermediate_results)}
              />
            <% end %>
          <% end %>
        </div>

        <%!-- Legend --%>
        <div class="flex items-center justify-center gap-6 mt-6 text-sm text-base-content/60">
          <div class="flex items-center gap-2">
            <div class="w-3 h-3 rounded-full bg-success"></div>
            <span>Completed</span>
          </div>
          <div class="flex items-center gap-2">
            <div class="w-3 h-3 rounded-full bg-warning animate-pulse"></div>
            <span>In Progress</span>
          </div>
          <div class="flex items-center gap-2">
            <div class="w-3 h-3 rounded-full bg-base-content/30"></div>
            <span>Pending</span>
          </div>
          <div class="flex items-center gap-2">
            <.icon name="hero-arrows-pointing-out" class="size-3 text-info" />
            <span>Scatter/Gather</span>
          </div>
        </div>
      </div>
    </div>
    """
  end

  attr :step, :map, required: true
  attr :tasks, :map, required: true
  attr :status, :atom, required: true

  defp scatter_gather_flow_node(assigns) do
    tasks_list = Enum.sort_by(assigns.tasks, fn {k, _v} -> k end)
    completed_count = Enum.count(tasks_list, fn {_k, v} -> Map.get(v, :status) == :completed end)
    total_count = length(tasks_list)

    assigns =
      assigns
      |> assign(:tasks_list, tasks_list)
      |> assign(:completed_count, completed_count)
      |> assign(:total_count, total_count)

    ~H"""
    <div class="flex flex-col items-center ring-2 ring-info/50 ring-offset-2 ring-offset-base-200 rounded-xl p-3 bg-info/5">
      <%!-- Header with scatter icon --%>
      <div class="flex items-center gap-2 mb-3">
        <.icon name="hero-arrows-pointing-out" class="size-4 text-info animate-pulse" />
        <span class="text-xs font-bold text-info">{@step.name} (Parallel)</span>
        <span class="badge badge-info badge-xs">{@completed_count}/{@total_count}</span>
      </div>

      <%!-- Fan-out visualization --%>
      <div class="relative w-full">
        <%!-- Scatter point --%>
        <div class="flex justify-center mb-2">
          <div class="w-8 h-8 rounded-full bg-info/30 flex items-center justify-center border-2 border-info">
            <.icon name="hero-bolt" class="size-4 text-info" />
          </div>
        </div>

        <%!-- Fan-out lines (SVG) --%>
        <svg class="w-full h-6 overflow-visible" preserveAspectRatio="none">
          <%= for {_task, idx} <- Enum.with_index(@tasks_list) do %>
            <%
              # Calculate x position for each task (distribute evenly)
              task_count = length(@tasks_list)
              spacing = 100 / (task_count + 1)
              x_pos = spacing * (idx + 1)
            %>
            <line
              x1="50%"
              y1="0"
              x2={"#{x_pos}%"}
              y2="100%"
              stroke="currentColor"
              stroke-width="2"
              class="text-info/50"
            />
          <% end %>
        </svg>

        <%!-- Parallel task nodes --%>
        <div class="flex flex-wrap justify-center gap-2 mt-1">
          <%= for {task_id, task_data} <- @tasks_list do %>
            <.mini_task_node task_id={task_id} data={task_data} />
          <% end %>
        </div>

        <%!-- Fan-in lines (SVG) --%>
        <svg class="w-full h-6 overflow-visible" preserveAspectRatio="none">
          <%= for {_task, idx} <- Enum.with_index(@tasks_list) do %>
            <%
              task_count = length(@tasks_list)
              spacing = 100 / (task_count + 1)
              x_pos = spacing * (idx + 1)
            %>
            <line
              x1={"#{x_pos}%"}
              y1="0"
              x2="50%"
              y2="100%"
              stroke="currentColor"
              stroke-width="2"
              class="text-info/50"
            />
          <% end %>
        </svg>

        <%!-- Gather point --%>
        <div class="flex justify-center mt-2">
          <div class={[
            "w-8 h-8 rounded-full flex items-center justify-center border-2",
            if(@completed_count == @total_count,
              do: "bg-success/30 border-success",
              else: "bg-warning/30 border-warning"
            )
          ]}>
            <%= if @completed_count == @total_count do %>
              <.icon name="hero-check" class="size-4 text-success" />
            <% else %>
              <div class="w-4 h-4 rounded-full border-2 border-warning border-t-transparent animate-spin"></div>
            <% end %>
          </div>
        </div>
      </div>

      <%!-- Progress indicator --%>
      <div class="w-full mt-3">
        <progress
          class={[
            "progress w-full h-2",
            if(@completed_count == @total_count, do: "progress-success", else: "progress-warning")
          ]}
          value={@completed_count}
          max={@total_count}
        />
      </div>
    </div>
    """
  end

  attr :task_id, :string, required: true
  attr :data, :map, required: true

  defp mini_task_node(assigns) do
    status = Map.get(assigns.data, :status, :pending)
    assigns = assign(assigns, :status, status)

    ~H"""
    <div class={[
      "flex flex-col items-center p-2 rounded-lg border min-w-[60px] transition-all duration-300",
      mini_task_border_class(@status)
    ]}>
      <div class={[
        "w-6 h-6 rounded-full flex items-center justify-center mb-1",
        mini_task_bg_class(@status)
      ]}>
        <%= case @status do %>
          <% :completed -> %>
            <.icon name="hero-check" class="size-3 text-success" />
          <% :in_progress -> %>
            <div class="w-3 h-3 rounded-full border-2 border-warning border-t-transparent animate-spin"></div>
          <% _ -> %>
            <.icon name="hero-clock" class="size-3 text-base-content/40" />
        <% end %>
      </div>
      <span class="text-[10px] font-medium text-center leading-tight truncate max-w-[50px]" title={@task_id}>
        {format_task_name(@task_id)}
      </span>
    </div>
    """
  end

  attr :step, :map, required: true
  attr :status, :atom, required: true
  attr :is_current, :boolean, required: true

  defp step_node(assigns) do
    ~H"""
    <div class={[
      "flex flex-col items-center p-3 rounded-lg border-2 min-w-[100px] transition-all duration-300",
      step_border_class(@status),
      @is_current && "ring-2 ring-offset-2 ring-offset-base-200 ring-warning scale-105"
    ]}>
      <div class={[
        "p-2 rounded-lg mb-2",
        step_bg_class(@status)
      ]}>
        <.icon name={@step.icon} class="size-5" />
      </div>
      <span class="text-xs font-medium text-center">{@step.name}</span>
      <.status_indicator status={@status} />
    </div>
    """
  end

  attr :status, :atom, required: true

  defp status_indicator(assigns) do
    ~H"""
    <div class="mt-1">
      <%= case @status do %>
        <% :completed -> %>
          <.icon name="hero-check-circle" class="size-4 text-success" />
        <% :in_progress -> %>
          <div class="w-4 h-4 rounded-full border-2 border-warning border-t-transparent animate-spin"></div>
        <% _ -> %>
          <div class="w-4 h-4 rounded-full border-2 border-base-content/30"></div>
      <% end %>
    </div>
    """
  end

  attr :from, :atom, required: true
  attr :to, :atom, required: true
  attr :active, :boolean, required: true

  defp step_arrow(assigns) do
    ~H"""
    <div class={[
      "hidden sm:block",
      if(@active, do: "text-success", else: "text-base-content/30")
    ]}>
      <.icon name="hero-arrow-right" class="size-5" />
    </div>
    """
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
    <details class="collapse collapse-arrow bg-base-300 rounded-lg">
      <summary class="collapse-title text-sm font-medium py-2 min-h-0">
        <div class="flex items-center gap-2">
          <%= if @status == :completed do %>
            <.icon name="hero-check-circle" class="size-4 text-success" />
          <% else %>
            <.icon name="hero-clock" class="size-4 text-warning" />
          <% end %>
          <span>{@key}</span>
        </div>
      </summary>
      <div class="collapse-content">
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
    {:noreply, assign(socket, :selected_scenario, scenario_id)}
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

    {:noreply, socket}
  end

  def handle_info({:step_started, correlation_id, step}, socket) do
    socket = maybe_update_process(socket, correlation_id, fn socket ->
      add_message(socket, :info, "Step #{step} started")
    end)

    {:noreply, socket}
  end

  def handle_info({:step_completed, correlation_id, step, _result}, socket) do
    socket = maybe_update_process(socket, correlation_id, fn socket ->
      socket
      |> update(:current_process, &ProcessManager.refresh_instance/1)
      |> add_message(:success, "Step #{step} completed ✓")
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

  defp get_parallel_tasks(%Instance{current_step: step, intermediate_results: results}) do
    prefix = "#{step_prefix(step)}:"

    results
    |> Enum.filter(fn {key, _value} -> String.starts_with?(key, prefix) end)
    |> Enum.into(%{})
  end

  defp step_prefix(:gathering), do: "gather"
  defp step_prefix(:purging), do: "purge"
  defp step_prefix(step), do: Atom.to_string(step)

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

  defp step_border_class(:completed), do: "border-success bg-success/10"
  defp step_border_class(:in_progress), do: "border-warning bg-warning/10"
  defp step_border_class(_), do: "border-base-content/20"

  defp step_bg_class(:completed), do: "bg-success/20 text-success"
  defp step_bg_class(:in_progress), do: "bg-warning/20 text-warning"
  defp step_bg_class(_), do: "bg-base-content/10 text-base-content/50"

  defp mini_task_border_class(:completed), do: "border-success bg-success/10"
  defp mini_task_border_class(:in_progress), do: "border-warning bg-warning/10 animate-pulse"
  defp mini_task_border_class(_), do: "border-base-content/20 bg-base-100"

  defp mini_task_bg_class(:completed), do: "bg-success/30"
  defp mini_task_bg_class(:in_progress), do: "bg-warning/30"
  defp mini_task_bg_class(_), do: "bg-base-content/10"

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
