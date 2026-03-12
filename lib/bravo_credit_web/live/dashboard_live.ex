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
        Control de Solicitudes (Backoffice)
        <:subtitle>
          Monitorea y evalúa las solicitudes de crédito ingresadas en la plataforma en tiempo real.
        </:subtitle>
        <:actions>
          <.button navigate={~p"/applications/new"} variant="primary">Crear Nueva Solicitud</.button>
        </:actions>
      </.header>

      <div class="grid gap-4 md:grid-cols-2 xl:grid-cols-5">
        <.metric_card
          label="Pendientes"
          value={status_count(@snapshot.status_counts, :pending)}
          tone="border-info"
        />
        <.metric_card
          label="Evaluando"
          value={status_count(@snapshot.status_counts, :evaluating)}
          tone="border-warning"
        />
        <.metric_card
          label="Aprobadas"
          value={status_count(@snapshot.status_counts, :approved)}
          tone="border-success"
        />
        <.metric_card
          label="En Revisión"
          value={status_count(@snapshot.status_counts, :in_review)}
          tone="border-accent"
        />
        <.metric_card
          label="Rechazadas"
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
              label="Filtro País"
              options={country_options()}
            />
            <.input
              field={@filters_form[:status]}
              type="select"
              label="Filtro Estado"
              options={status_options()}
            />
            <div class="fieldset mb-2">
              <span class="label mb-1">Última actualización (Live)</span>
              <div class="input flex items-center bg-base-200">
                {format_datetime(@snapshot.generated_at)}
              </div>
            </div>
          </div>
        </.form>
      </div>

      <div class="mt-6">
        <section class="rounded-box border border-base-300 bg-base-100 p-4 shadow-sm">
          <.header>
            Listado de Solicitudes
            <:subtitle>
              Solicitudes recientes con su estado de riesgo actual y decisión comercial.
            </:subtitle>
          </.header>

          <.table id="applications" rows={@snapshot.applications}>
            <:col :let={application} label="Solicitud">
              <div class="font-semibold">{application.id}</div>
              <div class="text-xs text-base-content/60">{application.country_code}</div>
            </:col>
            <:col :let={application} label="Etapa">
              <% stage = Monitoring.current_stage(application) %>
              <span class={["badge badge-sm", stage.tone]}>{stage_translation(stage.label)}</span>
            </:col>
            <:col :let={application} label="Estado">
              <span class={["badge badge-sm", status_badge(application.status)]}>
                {status_translation(application.status)}
              </span>
            </:col>
            <:col :let={application} label="Riesgo">
              <span class="badge badge-sm badge-outline">
                {status_translation(application.risk_status)}
              </span>
            </:col>
            <:col :let={application} label="Fecha Solicitud">
              {format_datetime(application.requested_at)}
            </:col>
            <:action :let={application}>
              <.link
                navigate={~p"/applications/#{application.id}"}
                class="link link-primary font-medium text-sm"
              >
                Ver Detalles
              </.link>
            </:action>
          </.table>
        </section>
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

  defp status_translation(:pending), do: "Pendiente"
  defp status_translation(:provider_processing), do: "Procesando Validador"
  defp status_translation(:evaluating), do: "Evaluando Riesgo"
  defp status_translation(:approved), do: "Aprobada"
  defp status_translation(:rejected), do: "Rechazada"
  defp status_translation(:in_review), do: "En Revisión Manual"
  defp status_translation(:cancelled), do: "Cancelada"

  defp status_translation(:low), do: "Bajo"
  defp status_translation(:medium), do: "Medio"
  defp status_translation(:high), do: "Alto"
  defp status_translation(nil), do: "Desconocido"

  defp status_translation(value) when is_atom(value) do
    value |> Atom.to_string() |> String.replace("_", " ") |> String.capitalize()
  end

  defp stage_translation("Pending Data"), do: "Esperando Datos"
  defp stage_translation("Fetching Data"), do: "Consultando Proveedor"
  defp stage_translation("Evaluating Risk"), do: "Calculando Riesgo"
  defp stage_translation("In Review"), do: "Revisión Manual"
  defp stage_translation("Finalized"), do: "Finalizada"
  defp stage_translation(other), do: other

  defp format_datetime(nil), do: "n/a"

  defp format_datetime(%DateTime{} = datetime),
    do: Calendar.strftime(datetime, "%Y-%m-%d %H:%M:%S UTC")
end
