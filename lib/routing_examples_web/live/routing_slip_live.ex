defmodule RoutingExamplesWeb.RoutingSlipLive do
  @moduledoc """
  LiveView for the Routing Slip pattern demonstration.

  Features:
  - Register new GenServer nodes with custom names
  - Create messages with a routing slip (list of destinations)
  - Real-time visualization of message flow through nodes
  """
  use RoutingExamplesWeb, :live_view

  alias RoutingExamples.RoutingSlip

  @pubsub_topic "routing_slip:updates"

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(RoutingExamples.PubSub, @pubsub_topic)
    end

    nodes = RoutingSlip.list_nodes()

    socket =
      socket
      |> assign(:nodes, nodes)
      |> assign(:node_form, to_form(%{"name" => ""}))
      |> assign(:message_form, to_form(%{"payload" => "", "destinations" => ""}))
      |> assign(:selected_destinations, [])
      |> assign(:active_messages, %{})
      |> assign(:completed_messages, [])
      |> assign(:node_visit_counts, %{})
      |> assign(:selected_message, nil)

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="min-h-screen">
        <%!-- Header --%>
        <div class="text-center mb-8">
          <h1 class="text-3xl font-bold bg-gradient-to-r from-primary to-accent bg-clip-text text-transparent">
            Routing Slip Pattern
          </h1>
          <p class="text-base-content/60 mt-2">
            Enterprise Integration Pattern: Messages carry their own itinerary
          </p>
        </div>

        <div class="grid grid-cols-1 lg:grid-cols-2 gap-6">
          <%!-- Left Column: Node Management --%>
          <div class="space-y-6">
            <%!-- Create Node Form --%>
            <div class="card bg-base-200 shadow-xl">
              <div class="card-body">
                <h2 class="card-title text-lg">
                  <.icon name="hero-server" class="size-5" /> Register Node
                </h2>
                <.form
                  for={@node_form}
                  id="node-form"
                  phx-submit="create_node"
                  class="flex gap-3 items-end"
                >
                  <div class="flex-1">
                    <.input
                      field={@node_form[:name]}
                      placeholder="Node name (e.g., validator, enricher, router)"
                      label="Node Name"
                    />
                  </div>
                  <.button type="submit" class="btn btn-primary">
                    <.icon name="hero-plus" class="size-4" /> Add
                  </.button>
                </.form>
              </div>
            </div>

            <%!-- Registered Nodes --%>
            <div class="card bg-base-200 shadow-xl">
              <div class="card-body">
                <h2 class="card-title text-lg">
                  <.icon name="hero-cube-transparent" class="size-5" /> Registered Nodes
                  <span class="badge badge-primary badge-sm">{length(@nodes)}</span>
                </h2>

                <%= if @nodes == [] do %>
                  <div class="text-center py-8 text-base-content/50">
                    <.icon name="hero-inbox" class="size-12 mx-auto mb-2 opacity-50" />
                    <p>No nodes registered yet</p>
                    <p class="text-sm">Create some nodes to get started</p>
                  </div>
                <% else %>
                  <div class="grid grid-cols-2 sm:grid-cols-3 gap-3">
                    <%= for node <- @nodes do %>
                      <.node_card
                        name={node}
                        visit_count={Map.get(@node_visit_counts, node, 0)}
                        active?={node_active?(@active_messages, node)}
                      />
                    <% end %>
                  </div>
                <% end %>
              </div>
            </div>
          </div>

          <%!-- Right Column: Message Creation & Visualization --%>
          <div class="space-y-6">
            <%!-- Create Message Form --%>
            <div class="card bg-base-200 shadow-xl">
              <div class="card-body">
                <h2 class="card-title text-lg">
                  <.icon name="hero-paper-airplane" class="size-5" /> Send Message
                </h2>

                <.form
                  for={@message_form}
                  id="message-form"
                  phx-submit="send_message"
                  class="space-y-4"
                >
                  <.input
                    field={@message_form[:payload]}
                    placeholder="Message content..."
                    label="Payload"
                  />

                  <%!-- Destination Selection --%>
                  <div class="space-y-2">
                    <label class="label">
                      <span class="label-text font-medium">
                        Routing Slip (click to add destinations)
                      </span>
                    </label>

                    <%= if @nodes == [] do %>
                      <div class="alert alert-warning">
                        <.icon name="hero-exclamation-triangle" class="size-5" />
                        <span>Register some nodes first to create a routing slip</span>
                      </div>
                    <% else %>
                      <div class="flex flex-wrap gap-2">
                        <%= for node <- @nodes do %>
                          <button
                            type="button"
                            phx-click="toggle_destination"
                            phx-value-node={node}
                            class={[
                              "btn btn-sm transition-all duration-200",
                              if(node in @selected_destinations,
                                do: "btn-primary",
                                else: "btn-outline btn-ghost"
                              )
                            ]}
                          >
                            {node}
                            <%= if node in @selected_destinations do %>
                              <span class="badge badge-xs badge-accent">
                                {Enum.find_index(@selected_destinations, &(&1 == node)) + 1}
                              </span>
                            <% end %>
                          </button>
                        <% end %>
                      </div>
                    <% end %>

                    <%!-- Selected Route Preview --%>
                    <%= if @selected_destinations != [] do %>
                      <div class="mt-3 p-3 bg-base-300 rounded-lg">
                        <span class="text-xs text-base-content/60 block mb-2">Route Preview:</span>
                        <div class="flex items-center flex-wrap gap-1">
                          <%= for {dest, idx} <- Enum.with_index(@selected_destinations) do %>
                            <span class="badge badge-primary">{dest}</span>
                            <%= if idx < length(@selected_destinations) - 1 do %>
                              <.icon name="hero-arrow-right" class="size-4 text-base-content/40" />
                            <% end %>
                          <% end %>
                        </div>
                      </div>
                    <% end %>
                  </div>

                  <.button
                    type="submit"
                    class="btn btn-primary w-full"
                    disabled={@selected_destinations == []}
                  >
                    <.icon name="hero-paper-airplane" class="size-4" /> Send Message
                  </.button>
                </.form>
              </div>
            </div>

            <%!-- Active Messages --%>
            <%= if map_size(@active_messages) > 0 do %>
              <div class="card bg-base-200 shadow-xl border-2 border-primary/30">
                <div class="card-body">
                  <h2 class="card-title text-lg">
                    <.icon name="hero-bolt" class="size-5 text-warning animate-pulse" />
                    Active Messages
                  </h2>
                  <div class="space-y-4">
                    <%= for {_id, message} <- @active_messages do %>
                      <.message_journey message={message} />
                    <% end %>
                  </div>
                </div>
              </div>
            <% end %>

            <%!-- Completed Messages --%>
            <%= if @completed_messages != [] do %>
              <div class="card bg-base-200 shadow-xl">
                <div class="card-body">
                  <h2 class="card-title text-lg">
                    <.icon name="hero-check-circle" class="size-5 text-success" /> Completed Journeys
                    <span class="badge badge-success badge-sm">{length(@completed_messages)}</span>
                  </h2>
                  <p class="text-xs text-base-content/50 -mt-2">Click to view raw message</p>
                  <div class="space-y-3 max-h-64 overflow-y-auto">
                    <%= for message <- Enum.take(@completed_messages, 5) do %>
                      <.completed_message message={message} />
                    <% end %>
                  </div>
                </div>
              </div>
            <% end %>
          </div>
        </div>

        <%!-- Message Detail Modal --%>
        <%= if @selected_message do %>
          <.message_detail_modal message={@selected_message} />
        <% end %>
      </div>
    </Layouts.app>
    """
  end

  # Components

  attr :name, :string, required: true
  attr :visit_count, :integer, required: true
  attr :active?, :boolean, required: true

  defp node_card(assigns) do
    ~H"""
    <div class={[
      "card bg-base-300 transition-all duration-300",
      @active? && "ring-2 ring-primary ring-offset-2 ring-offset-base-200 scale-105"
    ]}>
      <div class="card-body p-4">
        <div class="flex items-center justify-between">
          <div class="flex items-center gap-2">
            <div class={[
              "w-2 h-2 rounded-full",
              if(@active?, do: "bg-success animate-pulse", else: "bg-base-content/30")
            ]} />
            <span class="font-mono text-sm font-medium">{@name}</span>
          </div>
          <%= if @visit_count > 0 do %>
            <span class="badge badge-accent badge-sm font-mono">{@visit_count}</span>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  attr :message, :map, required: true

  defp message_journey(assigns) do
    ~H"""
    <div class="p-4 bg-base-300 rounded-lg">
      <div class="flex items-center justify-between mb-3">
        <span class="font-mono text-xs text-base-content/60">{@message.id}</span>
        <span class="badge badge-warning badge-sm">In Progress</span>
      </div>

      <div class="text-sm mb-3 p-2 bg-base-100 rounded font-mono">
        "{@message.payload}"
      </div>

      <%!-- Journey visualization --%>
      <div class="flex items-center flex-wrap gap-1">
        <%= for {node_name, step, _time} <- @message.visited do %>
          <div class="flex items-center gap-1">
            <span class="badge badge-success">
              <span class="font-mono mr-1">{step}.</span>
              {node_name}
            </span>
            <.icon name="hero-check" class="size-3 text-success" />
          </div>
          <.icon name="hero-arrow-right" class="size-4 text-base-content/40" />
        <% end %>
        <%= for {dest, idx} <- Enum.with_index(@message.routing_slip) do %>
          <span class={[
            "badge",
            if(idx == 0, do: "badge-warning animate-pulse", else: "badge-ghost")
          ]}>
            {dest}
          </span>
          <%= if idx < length(@message.routing_slip) - 1 do %>
            <.icon name="hero-arrow-right" class="size-4 text-base-content/40" />
          <% end %>
        <% end %>
      </div>
    </div>
    """
  end

  attr :message, :map, required: true

  defp completed_message(assigns) do
    ~H"""
    <div
      class="p-3 bg-base-300 rounded-lg opacity-80 hover:opacity-100 transition-all cursor-pointer hover:ring-2 hover:ring-primary/50 hover:scale-[1.02]"
      phx-click="select_message"
      phx-value-id={@message.id}
    >
      <div class="flex items-center justify-between mb-2">
        <span class="font-mono text-xs text-base-content/60">{@message.id}</span>
        <div class="flex items-center gap-2">
          <.icon name="hero-code-bracket" class="size-3 text-base-content/40" />
          <span class="badge badge-success badge-xs">Complete</span>
        </div>
      </div>

      <div class="flex items-center flex-wrap gap-1">
        <%= for {node_name, step, _time} <- @message.visited do %>
          <span class="badge badge-success badge-sm">
            <span class="font-mono mr-1 text-xs">{step}.</span>
            {node_name}
          </span>
          <%= if step < length(@message.visited) do %>
            <.icon name="hero-arrow-right" class="size-3 text-base-content/40" />
          <% end %>
        <% end %>
      </div>
    </div>
    """
  end

  attr :message, :map, required: true

  defp message_detail_modal(assigns) do
    # Format the message for JSON display
    formatted_message = %{
      id: assigns.message.id,
      payload: assigns.message.payload,
      routing_slip: assigns.message.routing_slip,
      visited:
        Enum.map(assigns.message.visited, fn {node, step, time} ->
          %{node: node, step: step, timestamp: DateTime.to_iso8601(time)}
        end)
    }

    assigns = assign(assigns, :json, Jason.encode!(formatted_message, pretty: true))

    ~H"""
    <div class="fixed inset-0 z-50 flex items-center justify-center p-4">
      <%!-- Backdrop --%>
      <div
        class="absolute inset-0 bg-black/60 backdrop-blur-sm"
        phx-click="close_message_detail"
      />

      <%!-- Modal --%>
      <div class="relative bg-base-200 rounded-xl shadow-2xl w-full max-w-2xl max-h-[80vh] flex flex-col animate-in fade-in zoom-in-95 duration-200">
        <%!-- Header --%>
        <div class="flex items-center justify-between p-4 border-b border-base-300">
          <div class="flex items-center gap-3">
            <div class="p-2 bg-success/20 rounded-lg">
              <.icon name="hero-document-text" class="size-5 text-success" />
            </div>
            <div>
              <h3 class="font-semibold">Message Detail</h3>
              <p class="text-xs text-base-content/60 font-mono">{@message.id}</p>
            </div>
          </div>
          <button
            type="button"
            phx-click="close_message_detail"
            class="btn btn-sm btn-ghost btn-circle"
          >
            <.icon name="hero-x-mark" class="size-5" />
          </button>
        </div>

        <%!-- Journey Summary --%>
        <div class="p-4 border-b border-base-300 bg-base-300/50">
          <span class="text-xs text-base-content/60 block mb-2">Journey Path</span>
          <div class="flex items-center flex-wrap gap-1">
            <%= for {node_name, step, _time} <- @message.visited do %>
              <span class="badge badge-success">
                <span class="font-mono mr-1 text-xs">{step}.</span>
                {node_name}
              </span>
              <%= if step < length(@message.visited) do %>
                <.icon name="hero-arrow-right" class="size-4 text-base-content/40" />
              <% end %>
            <% end %>
          </div>
        </div>

        <%!-- Code View --%>
        <div class="flex-1 overflow-auto p-4">
          <div class="flex items-center justify-between mb-2">
            <span class="text-xs text-base-content/60 font-medium">Raw Message (JSON)</span>
            <span class="badge badge-ghost badge-sm font-mono">application/json</span>
          </div>
          <pre class="bg-base-300 rounded-lg p-4 overflow-x-auto text-sm font-mono text-base-content/90 leading-relaxed"><code>{@json}</code></pre>
        </div>

        <%!-- Footer --%>
        <div class="p-4 border-t border-base-300 flex justify-end">
          <button type="button" phx-click="close_message_detail" class="btn btn-primary btn-sm">
            Close
          </button>
        </div>
      </div>
    </div>
    """
  end

  # Helper functions

  defp node_active?(active_messages, node_name) do
    Enum.any?(active_messages, fn {_id, msg} ->
      case msg.routing_slip do
        [current | _] -> current == node_name
        [] -> false
      end
    end)
  end

  # Event handlers

  @impl true
  def handle_event("create_node", %{"name" => name}, socket) do
    name = String.trim(name)

    socket =
      case RoutingSlip.create_node(name) do
        {:ok, _pid} ->
          socket
          |> assign(:nodes, RoutingSlip.list_nodes())
          |> assign(:node_form, to_form(%{"name" => ""}))
          |> put_flash(:info, "Node '#{name}' created successfully!")

        {:error, {:already_exists, _pid}} ->
          put_flash(socket, :error, "Node '#{name}' already exists")

        {:error, reason} ->
          put_flash(socket, :error, "Failed to create node: #{inspect(reason)}")
      end

    {:noreply, socket}
  end

  def handle_event("toggle_destination", %{"node" => node}, socket) do
    selected = socket.assigns.selected_destinations

    new_selected =
      if node in selected do
        List.delete(selected, node)
      else
        selected ++ [node]
      end

    {:noreply, assign(socket, :selected_destinations, new_selected)}
  end

  def handle_event("send_message", %{"payload" => payload}, socket) do
    destinations = socket.assigns.selected_destinations

    socket =
      case RoutingSlip.send_message(payload, destinations) do
        {:ok, _message_id} ->
          socket
          |> assign(:selected_destinations, [])
          |> assign(:message_form, to_form(%{"payload" => "", "destinations" => ""}))

        {:error, {:node_not_found, node}} ->
          put_flash(socket, :error, "Node '#{node}' not found")

        {:error, reason} ->
          put_flash(socket, :error, "Failed to send message: #{inspect(reason)}")
      end

    {:noreply, socket}
  end

  def handle_event("select_message", %{"id" => message_id}, socket) do
    message = Enum.find(socket.assigns.completed_messages, &(&1.id == message_id))
    {:noreply, assign(socket, :selected_message, message)}
  end

  def handle_event("close_message_detail", _params, socket) do
    {:noreply, assign(socket, :selected_message, nil)}
  end

  # PubSub handlers

  @impl true
  def handle_info({:node_created, _name}, socket) do
    {:noreply, assign(socket, :nodes, RoutingSlip.list_nodes())}
  end

  def handle_info({:message_started, message}, socket) do
    active_messages = Map.put(socket.assigns.active_messages, message.id, message)
    {:noreply, assign(socket, :active_messages, active_messages)}
  end

  def handle_info({:message_processed, node_name, message}, socket) do
    # Update active messages
    active_messages = Map.put(socket.assigns.active_messages, message.id, message)

    # Update visit counts
    visit_counts = socket.assigns.node_visit_counts
    current_count = Map.get(visit_counts, node_name, 0)
    visit_counts = Map.put(visit_counts, node_name, current_count + 1)

    socket =
      socket
      |> assign(:active_messages, active_messages)
      |> assign(:node_visit_counts, visit_counts)

    {:noreply, socket}
  end

  def handle_info({:message_completed, message}, socket) do
    # Remove from active, add to completed
    active_messages = Map.delete(socket.assigns.active_messages, message.id)
    completed_messages = [message | socket.assigns.completed_messages]

    socket =
      socket
      |> assign(:active_messages, active_messages)
      |> assign(:completed_messages, completed_messages)

    {:noreply, socket}
  end
end
