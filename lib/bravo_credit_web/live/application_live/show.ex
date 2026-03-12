defmodule BravoCreditWeb.ApplicationLive.Show do
  @moduledoc """
  Operations detail view for observing a single application through workers, events, webhooks, and outbox updates.
  """

  use BravoCreditWeb, :live_view

  alias BravoCredit.Applications
  alias BravoCredit.Error
  alias BravoCredit.Monitoring
  alias BravoCredit.Monitoring.Broadcaster
  alias BravoCredit.Webhooks

  @impl true
  def mount(%{"id" => application_id}, _session, socket) do
    if connected?(socket) do
      :ok = Broadcaster.subscribe_application(application_id)
    end

    {:ok,
     socket
     |> assign(:page_title, "Detalle de Solicitud")
     |> assign(:application_id, application_id)
     |> load_detail(application_id)}
  end

  @impl true
  def handle_event("simulate_webhook", %{"type" => event_type}, socket) do
    params = %{
      "application_id" => socket.assigns.application_id,
      "event_type" => event_type,
      "idempotency_key" => "ops-" <> Integer.to_string(System.unique_integer([:positive])),
      "reason" => webhook_reason(event_type)
    }

    case Webhooks.receive_provider(params) do
      {:ok, _webhook_event} ->
        {:noreply,
         socket
         |> put_flash(:info, "Webhook recibido y encolado para su procesamiento.")
         |> load_detail(socket.assigns.application_id)}

      {:error, %Error{} = error} ->
        {:noreply, put_flash(socket, :error, user_error_message(error))}
    end
  end

  @impl true
  def handle_event("transition", %{"state" => state}, socket) do
    case Applications.update_state(
           socket.assigns.application_id,
           %{"state" => state},
           Monitoring.console_actor()
         ) do
      {:ok, _application} ->
        {:noreply,
         socket
         |> put_flash(:info, "Cambio de estado manual guardado.")
         |> load_detail(socket.assigns.application_id)}

      {:error, %Error{} = error} ->
        {:noreply, put_flash(socket, :error, user_error_message(error))}
    end
  end

  @impl true
  def handle_info({:monitoring_event, _payload}, socket) do
    {:noreply, load_detail(socket, socket.assigns.application_id)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="bravo-shell space-y-6">
      <section class="bravo-surface bravo-hero p-6 sm:p-8">
        <div class="flex flex-col gap-4 lg:flex-row lg:items-center lg:justify-between">
          <div>
            <p class="text-xs font-semibold uppercase tracking-[0.14em] text-white/70">
              Detalle de Solicitud
            </p>
            <h1 class="mt-2 text-2xl font-semibold sm:text-3xl">Detalle de Solicitud</h1>
            <p class="mt-2 max-w-2xl text-sm text-white/85 sm:text-base">
              Revisa la información del cliente, las validaciones automáticas y la decisión de
              riesgo.
            </p>
          </div>
          <div class="flex gap-2">
            <.button
              navigate={~p"/operations"}
              class="btn btn-outline border-white/40 text-white hover:bg-white/10"
            >
              Volver
            </.button>
            <.button navigate={~p"/applications/new"} class="btn btn-accent">Nueva Solicitud</.button>
          </div>
        </div>
      </section>

      <%= if @detail do %>
        <div class="grid gap-6 xl:grid-cols-[1.4fr_1fr]">
          <div class="space-y-6">
            <section class="bravo-grid-card">
              <div class="flex flex-wrap items-start justify-between gap-4">
                <div>
                  <div class="text-sm text-base-content/60">{@detail.application.id}</div>
                  <div class="mt-2 flex flex-wrap gap-2">
                    <span class={["badge", @detail.stage.tone]}>
                      {stage_translation(@detail.stage.label)}
                    </span>
                    <span class={["badge badge-outline", status_badge(@detail.application.status)]}>
                      {status_translation(@detail.application.status)}
                    </span>
                    <span class="badge badge-outline">
                      Riesgo: {status_translation(@detail.application.risk_status)}
                    </span>
                  </div>
                  <p class="mt-3 text-sm text-base-content/70">
                    {stage_detail_translation(@detail.stage.detail)}
                  </p>
                </div>

                <div class="flex flex-wrap gap-2">
                  <%= for event_type <- webhook_buttons() do %>
                    <button
                      type="button"
                      class="btn btn-sm btn-outline"
                      phx-click="simulate_webhook"
                      phx-value-type={event_type}
                    >
                      {webhook_button_label(event_type)}
                    </button>
                  <% end %>

                  <%= for target_state <- @detail.available_transitions do %>
                    <button
                      type="button"
                      class="btn btn-sm btn-secondary text-white"
                      data-state-target={target_state}
                      phx-click="transition"
                      phx-value-state={target_state}
                    >
                      Pasar a {status_translation(target_state)}
                    </button>
                  <% end %>
                </div>
              </div>

              <div class="mt-6 grid gap-6 lg:grid-cols-2">
                <div class="rounded-xl border border-base-300/80 bg-base-200/25 p-2">
                  <.list>
                    <:item title="País">{@detail.application.country_code}</:item>
                    <:item title="Monto Solicitado">{@detail.application.amount}</:item>
                    <:item title="Ingreso Mensual">{@detail.application.monthly_income}</:item>
                    <:item title="Score Calculado">
                      {@detail.application.risk_score || "Pendiente"}
                    </:item>
                    <:item title="Fecha Ingreso">
                      {format_datetime(@detail.application.requested_at)}
                    </:item>
                  </.list>
                </div>

                <div class="space-y-4">
                  <div>
                    <div class="mb-2 text-sm font-semibold">Metadatos Originales</div>
                    <pre class="overflow-x-auto rounded-xl bg-base-200 p-3 text-xs">{pretty_json(@detail.application.metadata)}</pre>
                  </div>
                  <div>
                    <div class="mb-2 text-sm font-semibold">Datos Bancarios (Enriquecidos)</div>
                    <pre class="overflow-x-auto rounded-xl bg-base-200 p-3 text-xs">{pretty_json(@detail.application.banking_info)}</pre>
                  </div>
                </div>
              </div>
            </section>

            <section class="bravo-grid-card">
              <.header>
                Historia de la Solicitud
                <:subtitle>
                  Flujo inmutable de validaciones y decisiones ejecutadas sobre el expediente.
                </:subtitle>
              </.header>

              <.table id="timeline" rows={@detail.timeline}>
                <:col :let={event} label="Evento">{event.event_type}</:col>
                <:col :let={event} label="Actor">{event.actor}</:col>
                <:col :let={event} label="Fecha">{format_datetime(event.inserted_at)}</:col>
              </.table>
            </section>
          </div>

          <div class="space-y-6">
            <details class="group bravo-grid-card open:border-secondary">
              <summary class="flex cursor-pointer items-center justify-between text-lg font-semibold">
                <span>Diagnósticos Técnicos (Depuración)</span>
                <span class="transition-transform group-open:rotate-180">▼</span>
              </summary>
              <div class="mt-4 space-y-6">
                <section>
                  <.header>
                    Webhooks Recibidos
                    <:subtitle>
                      Llamadas externas guardadas asíncronamente con idempotencia.
                    </:subtitle>
                  </.header>
                  <.table id="webhooks" rows={@detail.webhooks}>
                    <:col :let={webhook} label="Evento">{webhook.event_type}</:col>
                    <:col :let={webhook} label="Estatus">{status_translation(webhook.status)}</:col>
                  </.table>
                </section>

                <section>
                  <.header>
                    Bandeja de Salida de Eventos
                    <:subtitle>
                      Patrón de bandeja de salida transaccional para evitar fallos de conectividad.
                    </:subtitle>
                  </.header>
                  <.table id="outbox-events" rows={@detail.outbox_events}>
                    <:col :let={event} label="Evento">{event.event_type}</:col>
                    <:col :let={event} label="Estatus">{status_translation(event.status)}</:col>
                  </.table>
                </section>

                <section>
                  <.header>Cola de Trabajo (Oban)</.header>
                  <.table id="jobs" rows={@detail.jobs}>
                    <:col :let={job} label="Proceso">{short_worker(job.worker)}</:col>
                    <:col :let={job} label="Estado">{job_state_translation(job.state)}</:col>
                  </.table>
                </section>
              </div>
            </details>
          </div>
        </div>
      <% else %>
        <div class="bravo-grid-card">
          <p>La solicitud no fue encontrada.</p>
        </div>
      <% end %>
    </div>
    """
  end

  defp load_detail(socket, application_id) do
    case Monitoring.application_detail(application_id) do
      {:ok, detail} -> assign(socket, :detail, detail)
      {:error, _error} -> assign(socket, :detail, nil)
    end
  end

  defp webhook_buttons do
    [
      "provider.manual_review_requested",
      "provider.application_approved",
      "provider.application_rejected"
    ]
  end

  defp webhook_button_label("provider.manual_review_requested"), do: "Reporte de Buró: Dudoso"
  defp webhook_button_label("provider.application_approved"), do: "Resolución Externa: Aprobó"
  defp webhook_button_label("provider.application_rejected"), do: "Resolución Externa: Declinó"

  defp webhook_reason("provider.manual_review_requested"),
    do: "el proveedor solicitó validaciones adicionales"

  defp webhook_reason("provider.application_approved"),
    do: "el proveedor marcó la solicitud como aprobada"

  defp webhook_reason("provider.application_rejected"),
    do: "el proveedor marcó la solicitud como rechazada"

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
  defp status_translation(:not_started), do: "No iniciado"
  defp status_translation(:provider_data_ready), do: "Datos del proveedor listos"
  defp status_translation(:processing), do: "Procesando"
  defp status_translation(:manual_review), do: "Revisión manual"
  defp status_translation(:received), do: "Recibido"
  defp status_translation(:processed), do: "Procesado"
  defp status_translation(:failed), do: "Fallido"
  defp status_translation(:duplicate), do: "Duplicado"

  defp status_translation(:low), do: "Bajo"
  defp status_translation(:medium), do: "Medio"
  defp status_translation(:high), do: "Alto"
  defp status_translation(nil), do: "Desconocido"

  defp status_translation(value) when is_atom(value) do
    value |> Atom.to_string() |> String.replace("_", " ") |> String.capitalize()
  end

  defp status_translation(other), do: other

  defp stage_translation("Pending Data"), do: "Esperando Datos"
  defp stage_translation("Fetching Data"), do: "Consultando Proveedor"
  defp stage_translation("Evaluating Risk"), do: "Calculando Riesgo"
  defp stage_translation("In Review"), do: "Revisión Manual"
  defp stage_translation("Finalized"), do: "Finalizada"
  defp stage_translation(other), do: other

  defp stage_detail_translation("Application stored and waiting for provider fetch"),
    do: "Solicitud registrada y en espera de consulta al proveedor."

  defp stage_detail_translation("Provider job is running"),
    do: "La tarea del proveedor está en ejecución."

  defp stage_detail_translation("Provider data is available and risk evaluation is in progress"),
    do: "Los datos del proveedor ya están disponibles y el riesgo se está evaluando."

  defp stage_detail_translation("Application completed successfully"),
    do: "Solicitud finalizada correctamente."

  defp stage_detail_translation("Application was rejected by risk or manual review"),
    do: "La solicitud fue rechazada por riesgo o por revisión manual."

  defp stage_detail_translation("Waiting for analyst decision or provider callback"),
    do: "En espera de decisión del analista o de respuesta del proveedor."

  defp stage_detail_translation("Application was cancelled"),
    do: "La solicitud fue cancelada."

  defp stage_detail_translation("Current status is tracked from the aggregate snapshot"),
    do: "El estado actual se obtiene desde el agregado persistido."

  defp stage_detail_translation(detail), do: detail

  defp format_datetime(nil), do: "N/D"

  defp format_datetime(%DateTime{} = datetime),
    do: Calendar.strftime(datetime, "%Y-%m-%d %H:%M:%S UTC")

  defp pretty_json(map) when map in [%{}, nil], do: "{}"
  defp pretty_json(map), do: Jason.encode!(map, pretty: true)

  defp short_worker(worker) do
    worker
    |> String.split(".")
    |> List.last()
  end

  defp job_state_translation("available"), do: "Disponible"
  defp job_state_translation("scheduled"), do: "Programado"
  defp job_state_translation("executing"), do: "Ejecutando"
  defp job_state_translation("retryable"), do: "Reintentable"
  defp job_state_translation("completed"), do: "Completado"
  defp job_state_translation("discarded"), do: "Descartado"
  defp job_state_translation("cancelled"), do: "Cancelado"
  defp job_state_translation(other), do: other

  defp user_error_message(%Error{code: "document.invalid_format"}) do
    "El documento no coincide con el formato esperado para el país seleccionado."
  end

  defp user_error_message(%Error{code: "application.duplicate_document"}) do
    "Este documento ya tiene una solicitud registrada."
  end

  defp user_error_message(%Error{code: "state.invalid_transition"}) do
    "No se puede realizar ese cambio de estado desde el estado actual."
  end

  defp user_error_message(%Error{}) do
    "Ocurrió un problema al procesar la acción. Inténtalo nuevamente."
  end
end
