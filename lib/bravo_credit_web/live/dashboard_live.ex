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
     |> assign(:page_title, "Consola de Operaciones BravoCredit")
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
    <div class="bravo-shell space-y-6">
      <section class="bravo-surface bravo-hero p-6 sm:p-8">
        <div class="flex flex-col gap-6 lg:flex-row lg:items-start lg:justify-between">
          <div class="space-y-3">
            <p class="text-xs font-semibold uppercase tracking-[0.14em] text-white/70">
              Operaciones Go Bravo
            </p>
            <h1 class="bravo-heading">Control de Solicitudes</h1>
            <p class="max-w-2xl text-sm text-white/85 sm:text-base">
              Monitorea y evalúa las solicitudes de crédito ingresadas en la plataforma en tiempo
              real.
            </p>
          </div>

          <.button
            navigate={~p"/applications/new"}
            class="btn btn-accent btn-lg shadow-lg shadow-black/20"
          >
            Crear Nueva Solicitud
          </.button>
        </div>

        <div class="mt-6 flex flex-wrap gap-2">
          <span class="bravo-chip">
            Actualización <strong>{format_datetime(@snapshot.generated_at)}</strong>
          </span>
          <span class="bravo-chip">
            Pendientes <strong>{status_count(@snapshot.status_counts, :pending)}</strong>
          </span>
          <span class="bravo-chip">
            Evaluando <strong>{status_count(@snapshot.status_counts, :evaluating)}</strong>
          </span>
          <span class="bravo-chip">
            Aprobadas <strong>{status_count(@snapshot.status_counts, :approved)}</strong>
          </span>
          <span class="bravo-chip">
            En revisión <strong>{status_count(@snapshot.status_counts, :in_review)}</strong>
          </span>
          <span class="bravo-chip">
            Rechazadas <strong>{status_count(@snapshot.status_counts, :rejected)}</strong>
          </span>
        </div>
      </section>

      <section class="bravo-grid-card">
        <.form for={@filters_form} phx-change="filter">
          <div class="grid gap-4 md:grid-cols-3">
            <.input
              field={@filters_form[:country]}
              type="select"
              label="Filtrar por País"
              options={country_options()}
            />
            <.input
              field={@filters_form[:status]}
              type="select"
              label="Filtrar por Estado"
              options={status_options()}
            />
            <div class="fieldset mb-2">
              <span class="label mb-1 font-semibold">Última actualización (en vivo)</span>
              <div class="input flex items-center bg-base-200">
                {format_datetime(@snapshot.generated_at)}
              </div>
            </div>
          </div>
        </.form>
      </section>

      <div class="grid gap-6 xl:grid-cols-[1.5fr_1fr]">
        <section class="bravo-grid-card">
          <.header>
            Listado de Solicitudes
            <:subtitle>
              Solicitudes recientes con su estado de riesgo actual y decisión comercial.
            </:subtitle>
          </.header>

          <.table id="applications" rows={@snapshot.applications}>
            <:col :let={application} label="Solicitud">
              <div class="font-mono text-xs font-semibold sm:text-sm" title={application.id}>
                {short_application_id(application.id)}
              </div>
              <div class="mt-1 flex items-center gap-2 text-xs text-base-content/60">
                <span>{application.country_code}</span>
                <button
                  id={"copy-id-" <> application.id}
                  type="button"
                  phx-hook="CopyButton"
                  data-copy-value={application.id}
                  data-copy-label="Copiar ID"
                  class="btn btn-xs btn-ghost normal-case"
                >
                  Copiar ID
                </button>
              </div>
            </:col>
            <:col :let={application} label="Etapa">
              <% stage = Monitoring.current_stage(application) %>
              <span class={["badge badge-sm", stage.tone]}>{stage_translation(stage.label)}</span>
            </:col>
            <:col :let={application} label="Estado">
              <span class={["badge badge-sm text-white", status_badge(application.status)]}>
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

        <section class="bravo-grid-card">
          <.header>
            Actividad Reciente
            <:subtitle>
              Eventos de aplicación y webhooks entrantes en la consola.
            </:subtitle>
          </.header>

          <div class="space-y-3">
            <article
              :for={event <- @snapshot.recent_activity}
              class="rounded-xl border border-base-300/80 bg-base-200/30 p-3"
            >
              <div class="mb-2 flex items-center justify-between gap-2">
                <span class={["badge badge-sm", activity_badge(event.kind)]}>
                  {activity_label(event.kind)}
                </span>
                <span class="text-xs text-base-content/65">{format_datetime(event.inserted_at)}</span>
              </div>
              <div class="text-sm font-semibold">{event.event_type}</div>
              <div class="mt-1 text-xs text-base-content/70">
                {event.country_code || "N/D"} · {event.application_id || "sin solicitud"} · {event_status(
                  event
                )}
              </div>
            </article>

            <p :if={@snapshot.recent_activity == []} class="text-sm text-base-content/65">
              No hay actividad reciente en este filtro.
            </p>
          </div>
        </section>
      </div>
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
      {"Todos los países", "ALL"},
      {"Brasil", "BR"},
      {"Colombia", "CO"},
      {"España", "ES"},
      {"Italia", "IT"},
      {"México", "MX"},
      {"Portugal", "PT"}
    ]
  end

  defp status_options do
    [
      {"Todos los estados", "ALL"},
      {"Pendiente", "pending"},
      {"Procesando proveedor", "provider_processing"},
      {"Evaluando", "evaluating"},
      {"Aprobada", "approved"},
      {"Rechazada", "rejected"},
      {"En revisión", "in_review"},
      {"Cancelada", "cancelled"}
    ]
  end

  defp status_badge(:approved), do: "bg-success border-success"
  defp status_badge(:rejected), do: "bg-error border-error"
  defp status_badge(:in_review), do: "bg-secondary border-secondary"
  defp status_badge(:evaluating), do: "bg-warning border-warning text-black"
  defp status_badge(:provider_processing), do: "bg-warning border-warning text-black"
  defp status_badge(_status), do: "bg-info border-info"

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

  defp stage_translation("Created"), do: "Registrada"
  defp stage_translation("Provider Processing"), do: "Procesando Proveedor"
  defp stage_translation("Evaluating Risk"), do: "Evaluando Riesgo"
  defp stage_translation("Manual Review"), do: "Revisión Manual"
  defp stage_translation("Approved"), do: "Aprobada"
  defp stage_translation("Rejected"), do: "Rechazada"
  defp stage_translation("Cancelled"), do: "Cancelada"
  defp stage_translation(other), do: other

  defp activity_label(:application_event), do: "Aplicación"
  defp activity_label(:webhook_event), do: "Webhook"
  defp activity_label(_kind), do: "Evento"

  defp activity_badge(:application_event), do: "badge-primary"
  defp activity_badge(:webhook_event), do: "badge-accent"
  defp activity_badge(_kind), do: "badge-neutral"

  defp event_status(%{status: status}) when not is_nil(status), do: status_translation(status)
  defp event_status(%{actor: actor}) when is_binary(actor), do: actor
  defp event_status(_event), do: "N/D"

  defp short_application_id(id) when is_binary(id) do
    if String.length(id) > 12 do
      "#{String.slice(id, 0, 8)}...#{String.slice(id, -4, 4)}"
    else
      id
    end
  end

  defp short_application_id(_id), do: "N/D"

  defp format_datetime(nil), do: "N/D"

  defp format_datetime(%DateTime{} = datetime),
    do: Calendar.strftime(datetime, "%Y-%m-%d %H:%M:%S UTC")
end
