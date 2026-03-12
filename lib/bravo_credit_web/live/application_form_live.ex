defmodule BravoCreditWeb.ApplicationFormLive do
  @moduledoc """
  Console form for creating a credit application and watching the async pipeline continue.
  """

  use BravoCreditWeb, :live_view

  alias BravoCredit.Applications
  alias BravoCredit.Applications.CreateInput
  alias BravoCredit.Error

  @defaults %{
    "country_code" => "MX",
    "full_name" => "María Solicitante",
    "document_id" => "GODE561231HDFRRN04",
    "amount" => "50000.00",
    "monthly_income" => "25000.00"
  }

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Crear Solicitud")
     |> assign(:submit_error, nil)
     |> assign(:form_params, @defaults)
     |> assign_form(@defaults)}
  end

  @impl true
  def handle_event("validate", %{"application" => params}, socket) do
    {:noreply,
     socket
     |> assign(:submit_error, nil)
     |> assign(:form_params, params)
     |> assign_form(params, :validate)}
  end

  @impl true
  def handle_event("save", %{"application" => params}, socket) do
    payload = build_payload(params)
    changeset = CreateInput.changeset(payload)

    if changeset.valid? do
      case Applications.create(payload, "operations_console") do
        {:ok, application} ->
          {:noreply,
           socket
           |> put_flash(
             :info,
             "Solicitud creada. La validación de proveedor y el motor de riesgo continuarán en segundo plano."
           )
           |> push_navigate(to: ~p"/applications/#{application.id}")}

        {:error, %Error{} = error} ->
          {:noreply,
           socket
           |> assign(:submit_error, error)
           |> assign(:form_params, params)
           |> assign_form(params, :validate)}
      end
    else
      {:noreply,
       socket
       |> assign(:submit_error, nil)
       |> assign(:form_params, params)
       |> assign_form(params, :validate)}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="bravo-shell space-y-6">
      <section class="bravo-surface bravo-hero p-6 sm:p-8">
        <div class="flex flex-col gap-4 lg:flex-row lg:items-center lg:justify-between">
          <div>
            <p class="text-xs font-semibold uppercase tracking-[0.14em] text-white/70">Originación</p>
            <h1 class="mt-2 text-2xl font-semibold sm:text-3xl">Crear Solicitud</h1>
            <p class="mt-2 max-w-2xl text-sm text-white/85 sm:text-base">
              Ingresa los datos del cliente para iniciar el proceso de evaluación de crédito.
              Usa identificadores de países válidos (MX/CO).
            </p>
          </div>
          <.button
            navigate={~p"/operations"}
            class="btn btn-outline border-white/40 text-white hover:bg-white/10"
          >
            Volver a Operaciones
          </.button>
        </div>
      </section>

      <div class="mx-auto w-full max-w-3xl">
        <section class="bravo-grid-card">
          <div :if={@submit_error} class="mb-5 rounded-xl border border-error/30 bg-error/10 p-4">
            <div class="font-semibold text-error">No pudimos crear la solicitud</div>
            <div class="mt-1 text-sm">{submit_error_message(@submit_error)}</div>
          </div>

          <.form id="application-form" for={@form} phx-change="validate" phx-submit="save">
            <div class="grid gap-4 md:grid-cols-2">
              <.input
                field={@form[:country_code]}
                type="select"
                label="País"
                options={country_options()}
              />
              <.input field={@form[:full_name]} label="Nombre Completo" />
              <.input field={@form[:document_id]} label="Documento de Identidad (ej. CURP/CC)" />
              <.input field={@form[:amount]} type="number" step="0.01" label="Monto Solicitado" />
              <.input
                field={@form[:monthly_income]}
                type="number"
                step="0.01"
                label="Ingreso Mensual"
              />
            </div>

            <div class="mt-8 flex justify-end gap-3">
              <.button navigate={~p"/operations"} class="btn btn-ghost">Cancelar</.button>
              <.button type="submit" class="btn btn-secondary">
                Crear Solicitud y Evaluar
              </.button>
            </div>
          </.form>
        </section>
      </div>
    </div>
    """
  end

  defp assign_form(socket, params, action \\ nil) do
    payload = build_payload(params)
    changeset = CreateInput.changeset(payload)
    changeset = if action, do: %{changeset | action: action}, else: changeset

    assign(socket, :form, to_form(changeset, as: :application))
  end

  defp build_payload(params) do
    channel =
      case params["channel"] do
        channel when is_binary(channel) and channel != "" -> channel
        _empty -> "operations-console"
      end

    metadata =
      %{"channel" => channel}

    params
    |> Map.drop(["channel"])
    |> Map.put("metadata", metadata)
  end

  defp country_options do
    [
      {"México", "MX"},
      {"Colombia", "CO"}
    ]
  end

  defp submit_error_message(%Error{code: "document.invalid_format"}) do
    "El documento no coincide con el formato esperado del país seleccionado."
  end

  defp submit_error_message(%Error{code: "rules.initial_rejected"}) do
    "No podemos continuar con esta solicitud por políticas de evaluación."
  end

  defp submit_error_message(%Error{code: "application.duplicate_document"}) do
    "Este documento ya tiene una solicitud registrada."
  end

  defp submit_error_message(%Error{code: "country.unsupported"}) do
    "El país seleccionado no está disponible por ahora."
  end

  defp submit_error_message(%Error{}) do
    "Revisa los datos e inténtalo de nuevo."
  end
end
