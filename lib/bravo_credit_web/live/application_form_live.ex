defmodule BravoCreditWeb.ApplicationFormLive do
  @moduledoc """
  Console form for creating a credit application and watching the async pipeline continue.
  """

  use BravoCreditWeb, :live_view

  alias BravoCredit.Applications
  alias BravoCredit.Error

  @defaults %{
    "country_code" => "MX",
    "full_name" => "Jane Applicant",
    "document_id" => "GODE561231HDFRRN04",
    "amount" => "50000.00",
    "monthly_income" => "25000.00",
    "channel" => "operations-console"
  }

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Create Application")
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
     |> assign_form(params)}
  end

  @impl true
  def handle_event("save", %{"application" => params}, socket) do
    payload = build_payload(params)

    case Applications.create(payload, "operations_console") do
      {:ok, application} ->
        {:noreply,
         socket
         |> put_flash(
           :info,
           "Application created. Provider and risk workers will continue asynchronously."
         )
         |> push_navigate(to: ~p"/applications/#{application.id}")}

      {:error, %Error{} = error} ->
        {:noreply,
         socket
         |> assign(:submit_error, error)
         |> assign(:form_params, params)
         |> assign_form(params)}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-3xl px-4 py-8 sm:px-6 lg:px-8">
      <.header>
        Create Application
        <:subtitle>
          Use valid MX or CO documents to trigger the full provider and risk pipeline.
        </:subtitle>
        <:actions>
          <.button navigate={~p"/operations"} variant="primary">Back to Operations</.button>
        </:actions>
      </.header>

      <div class="grid gap-6 lg:grid-cols-[2fr_1fr]">
        <section class="rounded-box border border-base-300 bg-base-100 p-6 shadow-sm">
          <div :if={@submit_error} class="mb-4 rounded-box border border-error/30 bg-error/10 p-4">
            <div class="font-semibold text-error">{@submit_error.code}</div>
            <div class="mt-1 text-sm">{@submit_error.message}</div>
            <pre class="mt-3 overflow-x-auto text-xs">{pretty_json(@submit_error.details)}</pre>
          </div>

          <.form id="application-form" for={@form} phx-change="validate" phx-submit="save">
            <div class="grid gap-4 md:grid-cols-2">
              <.input
                field={@form[:country_code]}
                type="select"
                label="Country"
                options={country_options()}
              />
              <.input field={@form[:full_name]} label="Full Name" />
              <.input field={@form[:document_id]} label="Document ID" />
              <.input field={@form[:amount]} type="number" step="0.01" label="Amount" />
              <.input field={@form[:monthly_income]} type="number" step="0.01" label="Monthly Income" />
              <.input field={@form[:channel]} label="Channel" />
            </div>

            <div class="mt-6 flex items-center gap-3">
              <.button type="submit">Create and Monitor</.button>
              <.button navigate={~p"/operations"} class="btn btn-ghost">Cancel</.button>
            </div>
          </.form>
        </section>

        <section class="rounded-box border border-base-300 bg-base-100 p-6 shadow-sm">
          <.header>
            Reference Inputs
            <:subtitle>These examples are already valid for the current country configs.</:subtitle>
          </.header>

          <.list>
            <:item title="Mexico document">`GODE561231HDFRRN04`</:item>
            <:item title="Colombia document">`1234567890`</:item>
            <:item title="MX monthly income">`25000.00`</:item>
            <:item title="CO monthly income">`1500000.00`</:item>
          </.list>

          <div class="mt-6 rounded-box bg-base-200 p-4 text-sm text-base-content/70">
            After submit, the request will:
            <ol class="ml-4 mt-2 list-decimal space-y-1">
              <li>persist the application</li>
              <li>enqueue provider fetch</li>
              <li>persist provider data</li>
              <li>enqueue risk evaluation</li>
              <li>persist the final decision</li>
            </ol>
          </div>
        </section>
      </div>
    </div>
    """
  end

  defp assign_form(socket, params) do
    assign(socket, :form, to_form(params, as: :application))
  end

  defp build_payload(params) do
    metadata =
      case params["channel"] do
        channel when is_binary(channel) and channel != "" -> %{"channel" => channel}
        _empty -> %{}
      end

    params
    |> Map.drop(["channel"])
    |> Map.put("metadata", metadata)
  end

  defp country_options do
    [
      {"Mexico", "MX"},
      {"Colombia", "CO"}
    ]
  end

  defp pretty_json(map) when map == %{}, do: "{}"
  defp pretty_json(map), do: Jason.encode!(map, pretty: true)
end
