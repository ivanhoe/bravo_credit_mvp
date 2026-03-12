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
              Usa identificadores de países válidos (BR/CO/ES/IT/MX/PT).
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
              <.input field={@form[:full_name]} label="Nombre Completo" phx-debounce="blur" />
              <.input
                field={@form[:document_id]}
                label={document_label(@form_params["country_code"])}
                placeholder={document_placeholder(@form_params["country_code"])}
                phx-debounce="blur"
              />
              <.input
                field={@form[:amount]}
                type="number"
                step="0.01"
                label="Monto Solicitado"
                phx-debounce="blur"
              />
              <.input
                field={@form[:monthly_income]}
                type="number"
                step="0.01"
                label="Ingreso Mensual"
                phx-debounce="blur"
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
      {"Brasil", "BR"},
      {"Colombia", "CO"},
      {"España", "ES"},
      {"Italia", "IT"},
      {"México", "MX"},
      {"Portugal", "PT"}
    ]
  end

  defp submit_error_message(%Error{
         code: "document.invalid_format",
         details: %{reason: "must_be_11_digits"}
       }) do
    "El CPF debe contener exactamente 11 dígitos numéricos."
  end

  defp submit_error_message(%Error{
         code: "document.invalid_format",
         details: %{reason: "repeated_digits"}
       }) do
    "El CPF no puede estar formado por dígitos repetidos."
  end

  defp submit_error_message(%Error{
         code: "document.invalid_format",
         details: %{reason: "invalid_checksum"}
       }) do
    "El CPF/DNI parece ser incorrecto (falló la validación matemática)."
  end

  defp submit_error_message(%Error{
         code: "document.invalid_format",
         details: %{reason: "must_be_8_digits_and_1_letter"}
       }) do
    "El DNI español debe tener exactamente 8 números y 1 letra al final."
  end

  defp submit_error_message(%Error{
         code: "document.invalid_format",
         details: %{reason: "must_be_9_digits"}
       }) do
    "El NIF portugués debe contener exactamente 9 dígitos numéricos."
  end

  defp submit_error_message(%Error{
         code: "document.invalid_format",
         details: %{reason: "invalid_prefix_pt"}
       }) do
    "El NIF portugués debe comenzar con un dígito válido (1, 2, 3, 5, 6, 8, 9)."
  end

  defp submit_error_message(%Error{
         code: "document.invalid_format",
         details: %{reason: "invalid_format_co"}
       }) do
    "La Cédula colombiana debe contener entre 6 y 10 dígitos numéricos."
  end

  defp submit_error_message(%Error{
         code: "document.invalid_format",
         details: %{reason: "invalid_format_mx"}
       }) do
    "La CURP mexicana debe contener 18 caracteres alfanuméricos en formato estándar."
  end

  defp submit_error_message(%Error{
         code: "document.invalid_format",
         details: %{reason: "invalid_format_it"}
       }) do
    "El Codice Fiscale debe tener 16 caracteres alfanuméricos en formato estándar."
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

  defp document_label("MX"), do: "Clave Única (CURP)"
  defp document_label("CO"), do: "Cédula de Ciudadanía (CC)"
  defp document_label("BR"), do: "Cadastro de Pessoa Física (CPF)"
  defp document_label("ES"), do: "Documento Nacional (DNI)"
  defp document_label("IT"), do: "Codice Fiscale"
  defp document_label("PT"), do: "Número de Identificação (NIF)"
  defp document_label(_), do: "Documento de Identidad"

  defp document_placeholder("MX"), do: "Ej. MOGG850101HDFRRN04"
  defp document_placeholder("CO"), do: "Ej. 1023456789"
  defp document_placeholder("BR"), do: "Ej. 12345678909 (11 dígitos)"
  defp document_placeholder("ES"), do: "Ej. 12345678Z"
  defp document_placeholder("IT"), do: "Ej. RSSMRA80A01H501U"
  defp document_placeholder("PT"), do: "Ej. 123456789"
  defp document_placeholder(_), do: ""
end
