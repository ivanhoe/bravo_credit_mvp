defmodule BravoCreditWeb.DashboardLive do
  @moduledoc """
  Operations dashboard for observing application progress, recent events, and queue health.
  """

  use BravoCreditWeb, :live_view

  alias BravoCredit.Monitoring
  alias BravoCredit.Monitoring.Broadcaster

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      :ok = Broadcaster.subscribe_dashboard()
    end

    {:ok,
     socket
     |> assign(:page_title, "BravoCredit Operations Console")
     |> load_snapshot(%{})}
  end

  @impl true
  def handle_event("filter", %{"filters" => filters}, socket) do
    {:noreply, load_snapshot(socket, filters)}
  end

  @impl true
  def handle_info({:monitoring_event, _payload}, socket) do
    {:noreply, load_snapshot(socket, socket.assigns.filters)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-7xl px-4 py-8 sm:px-6 lg:px-8">
      <.header>
        Operations Console
        <:subtitle>
          Watch applications move through provider, risk, webhook, and outbox flows in near real time.
        </:subtitle>
        <:actions>
          <.button navigate={~p"/applications/new"}>Create Application</.button>
        </:actions>
      </.header>

      <div class="grid gap-4 md:grid-cols-2 xl:grid-cols-5">
        <.metric_card
          label="Pending"
          value={status_count(@snapshot.status_counts, :pending)}
          tone="border-info"
        />
        <.metric_card
          label="Evaluating"
          value={status_count(@snapshot.status_counts, :evaluating)}
          tone="border-warning"
        />
        <.metric_card
          label="Approved"
          value={status_count(@snapshot.status_counts, :approved)}
          tone="border-success"
        />
        <.metric_card
          label="In Review"
          value={status_count(@snapshot.status_counts, :in_review)}
          tone="border-accent"
        />
        <.metric_card
          label="Rejected"
          value={status_count(@snapshot.status_counts, :rejected)}
          tone="border-error"
        />
      </div>

      <div class="mt-6 rounded-box border border-base-300 bg-base-100 p-4 shadow-sm">
        <.form for={@filters_form} phx-change="filter">
          <div class="grid gap-4 md:grid-cols-3">
            <.input
              field={@filters_form[:country]}
              type="select"
              label="Country"
              options={country_options()}
            />
            <.input
              field={@filters_form[:status]}
              type="select"
              label="Status"
              options={status_options()}
            />
            <div class="fieldset mb-2">
              <span class="label mb-1">Last refresh</span>
              <div class="input flex items-center">
                {format_datetime(@snapshot.generated_at)}
              </div>
            </div>
          </div>
        </.form>
      </div>

      <div class="mt-6 grid gap-6 xl:grid-cols-[2fr_1fr]">
        <section class="rounded-box border border-base-300 bg-base-100 p-4 shadow-sm">
          <.header>
            Applications
            <:subtitle>Newest applications with their current aggregate snapshot.</:subtitle>
          </.header>

          <.table id="applications" rows={@snapshot.applications}>
            <:col :let={application} label="Application">
              <div class="font-semibold">{application.id}</div>
              <div class="text-xs text-base-content/60">{application.country_code}</div>
            </:col>
            <:col :let={application} label="Stage">
              <% stage = Monitoring.current_stage(application) %>
              <span class={["badge badge-sm", stage.tone]}>{stage.label}</span>
            </:col>
            <:col :let={application} label="Status">
              <span class={["badge badge-sm", status_badge(application.status)]}>
                {humanize_atom(application.status)}
              </span>
            </:col>
            <:col :let={application} label="Risk">
              <span class="badge badge-sm badge-outline">
                {humanize_atom(application.risk_status)}
              </span>
            </:col>
            <:col :let={application} label="Requested">
              {format_datetime(application.requested_at)}
            </:col>
            <:action :let={application}>
              <.link
                navigate={~p"/applications/#{application.id}"}
                class="link link-primary text-sm"
              >
                Open
              </.link>
            </:action>
          </.table>
        </section>

        <div class="space-y-6">
          <section class="rounded-box border border-base-300 bg-base-100 p-4 shadow-sm">
            <.header>
              Queue Snapshot
              <:subtitle>Counts by Oban queue and current state.</:subtitle>
            </.header>

            <%= for {queue, states} <- Enum.sort_by(@snapshot.queue_snapshot, fn {queue, _states} -> queue end) do %>
              <div class="mb-4 last:mb-0">
                <div class="font-semibold uppercase text-xs tracking-wide text-base-content/60">
                  {queue}
                </div>
                <div class="mt-2 flex flex-wrap gap-2">
                  <%= for {state, count} <- Enum.sort_by(states, fn {state, _count} -> state end) do %>
                    <span class="badge badge-outline badge-sm">{state}: {count}</span>
                  <% end %>
                </div>
              </div>
            <% end %>
          </section>

          <section class="rounded-box border border-base-300 bg-base-100 p-4 shadow-sm">
            <.header>
              Outbox
              <:subtitle>
                Current state of rows created by the PostgreSQL-triggered outbox flow.
              </:subtitle>
            </.header>

            <div class="flex flex-wrap gap-2">
              <%= for status <- [:pending, :processing, :processed, :failed] do %>
                <span class="badge badge-outline badge-sm">
                  {humanize_atom(status)}: {Map.get(@snapshot.outbox_counts, status, 0)}
                </span>
              <% end %>
            </div>
          </section>

          <section class="rounded-box border border-base-300 bg-base-100 p-4 shadow-sm">
            <.header>
              Recent Activity
              <:subtitle>Most recent application and webhook events.</:subtitle>
            </.header>

            <.list>
              <:item :for={activity <- @snapshot.recent_activity} title={activity.event_type}>
                <div class="text-sm">
                  <span class="font-medium">{activity.country_code || "N/A"}</span>
                  <span class="mx-2 text-base-content/50">•</span>
                  <span>{activity.application_id || "no-application"}</span>
                </div>
                <div class="text-xs text-base-content/60">
                  {activity.actor} • {format_datetime(activity.inserted_at)}
                </div>
              </:item>
            </.list>
          </section>
        </div>
      </div>
    </div>
    """
  end

  attr :label, :string, required: true
  attr :value, :integer, required: true
  attr :tone, :string, default: "border-base-300"

  defp metric_card(assigns) do
    ~H"""
    <div class={["rounded-box border bg-base-100 p-4 shadow-sm", @tone]}>
      <div class="text-xs font-semibold uppercase tracking-wide text-base-content/60">{@label}</div>
      <div class="mt-2 text-3xl font-semibold">{@value}</div>
    </div>
    """
  end

  defp load_snapshot(socket, filters) do
    snapshot = Monitoring.dashboard_snapshot(filters)

    filters_form =
      snapshot.filters
      |> Enum.into(%{}, fn {key, value} -> {Atom.to_string(key), value} end)
      |> to_form(as: :filters)

    socket
    |> assign(:filters, snapshot.filters)
    |> assign(:filters_form, filters_form)
    |> assign(:snapshot, snapshot)
  end

  defp status_count(counts, status), do: Map.get(counts, status, 0)

  defp country_options do
    [
      {"All countries", "ALL"},
      {"Mexico", "MX"},
      {"Colombia", "CO"}
    ]
  end

  defp status_options do
    [
      {"All statuses", "ALL"},
      {"Pending", "pending"},
      {"Provider Processing", "provider_processing"},
      {"Evaluating", "evaluating"},
      {"Approved", "approved"},
      {"Rejected", "rejected"},
      {"In Review", "in_review"},
      {"Cancelled", "cancelled"}
    ]
  end

  defp status_badge(:approved), do: "badge-success"
  defp status_badge(:rejected), do: "badge-error"
  defp status_badge(:in_review), do: "badge-accent"
  defp status_badge(:evaluating), do: "badge-warning"
  defp status_badge(:provider_processing), do: "badge-warning"
  defp status_badge(_status), do: "badge-info"

  defp humanize_atom(nil), do: "Unknown"

  defp humanize_atom(value) when is_atom(value) do
    value
    |> Atom.to_string()
    |> String.replace("_", " ")
    |> String.capitalize()
  end

  defp format_datetime(nil), do: "n/a"

  defp format_datetime(%DateTime{} = datetime),
    do: Calendar.strftime(datetime, "%Y-%m-%d %H:%M:%S UTC")
end
