defmodule BravoCredit.Monitoring do
  @moduledoc """
  Read models and helpers for the operations monitoring LiveViews.
  """

  import Ecto.Query

  alias BravoCredit.Accounts.User
  alias BravoCredit.Applications.Application
  alias BravoCredit.Applications.ApplicationEvent
  alias BravoCredit.Applications.StatePolicy
  alias BravoCredit.Errors
  alias BravoCredit.Outbox.Event, as: OutboxEvent
  alias BravoCredit.Repo
  alias BravoCredit.Webhooks.WebhookEvent
  alias Oban.Job

  @dashboard_limit 20
  @event_limit 12
  @detail_limit 25
  @all_countries "ALL"
  @all_statuses "ALL"

  @type dashboard_snapshot :: %{
          applications: [Application.t()],
          status_counts: %{optional(Application.status()) => non_neg_integer()},
          queue_snapshot: %{optional(String.t()) => %{optional(String.t()) => non_neg_integer()}},
          outbox_counts: %{optional(OutboxEvent.status()) => non_neg_integer()},
          recent_activity: [map()],
          filters: %{country: String.t(), status: String.t()},
          generated_at: DateTime.t()
        }

  @type application_detail :: %{
          application: Application.t(),
          stage: map(),
          timeline: [ApplicationEvent.t()],
          webhooks: [WebhookEvent.t()],
          outbox_events: [OutboxEvent.t()],
          jobs: [Job.t()],
          available_transitions: [atom()],
          generated_at: DateTime.t()
        }

  @spec dashboard_snapshot(map()) :: dashboard_snapshot()
  def dashboard_snapshot(filters \\ %{}) when is_map(filters) do
    normalized_filters = normalize_filters(filters)

    %{
      applications: dashboard_applications(normalized_filters),
      status_counts: application_status_counts(normalized_filters),
      queue_snapshot: queue_snapshot(),
      outbox_counts: outbox_counts(),
      recent_activity: recent_activity(normalized_filters),
      filters: normalized_filters,
      generated_at: DateTime.utc_now()
    }
  end

  @spec application_detail(Ecto.UUID.t()) ::
          {:ok, application_detail()} | {:error, BravoCredit.Error.t()}
  def application_detail(application_id) when is_binary(application_id) do
    case Repo.get(Application, application_id) do
      %Application{} = application ->
        {:ok,
         %{
           application: application,
           stage: current_stage(application),
           timeline: timeline(application.id),
           webhooks: webhooks(application.id),
           outbox_events: outbox_events(application.id),
           jobs: jobs(application.id),
           available_transitions:
             StatePolicy.available_transitions(application.country_code, application.status),
           generated_at: DateTime.utc_now()
         }}

      nil ->
        {:error, Errors.application_not_found(application_id)}
    end
  end

  def application_detail(_application_id) do
    {:error, Errors.invalid_params(%{fields: %{application_id: ["is invalid"]}})}
  end

  @spec current_stage(Application.t()) :: map()
  def current_stage(%Application{status: :pending, risk_status: :not_started}) do
    %{
      key: :created,
      label: "Created",
      detail: "Application stored and waiting for provider fetch",
      tone: "badge-info"
    }
  end

  def current_stage(%Application{status: :provider_processing}) do
    %{
      key: :provider_processing,
      label: "Provider Processing",
      detail: "Provider job is running",
      tone: "badge-warning"
    }
  end

  def current_stage(%Application{status: :evaluating, risk_status: :provider_data_ready}) do
    %{
      key: :evaluating,
      label: "Evaluating Risk",
      detail: "Provider data is available and risk evaluation is in progress",
      tone: "badge-warning"
    }
  end

  def current_stage(%Application{status: :approved}) do
    %{
      key: :approved,
      label: "Approved",
      detail: "Application completed successfully",
      tone: "badge-success"
    }
  end

  def current_stage(%Application{status: :rejected}) do
    %{
      key: :rejected,
      label: "Rejected",
      detail: "Application was rejected by risk or manual review",
      tone: "badge-error"
    }
  end

  def current_stage(%Application{status: :in_review}) do
    %{
      key: :in_review,
      label: "Manual Review",
      detail: "Waiting for analyst decision or provider callback",
      tone: "badge-accent"
    }
  end

  def current_stage(%Application{status: :cancelled}) do
    %{
      key: :cancelled,
      label: "Cancelled",
      detail: "Application was cancelled",
      tone: "badge-neutral"
    }
  end

  def current_stage(%Application{} = application) do
    %{
      key: application.status,
      label:
        application.status |> Atom.to_string() |> String.replace("_", " ") |> String.capitalize(),
      detail: "Current status is tracked from the aggregate snapshot",
      tone: "badge-neutral"
    }
  end

  @spec console_actor() :: User.t()
  def console_actor do
    %User{
      id: "operations-console-admin",
      email: "operations-console@local",
      role: :admin,
      country_access: ["BR", "CO", "ES", "IT", "MX", "PT"]
    }
  end

  defp dashboard_applications(filters) do
    Application
    |> maybe_filter_country(filters.country)
    |> maybe_filter_status(filters.status)
    |> order_by([application], desc: application.requested_at)
    |> limit(^@dashboard_limit)
    |> Repo.all()
  end

  defp application_status_counts(filters) do
    Application
    |> maybe_filter_country(filters.country)
    |> group_by([application], application.status)
    |> select([application], {application.status, count(application.id)})
    |> Repo.all()
    |> Enum.into(%{})
  end

  defp outbox_counts do
    OutboxEvent
    |> group_by([event], event.status)
    |> select([event], {event.status, count(event.id)})
    |> Repo.all()
    |> Enum.into(%{})
  end

  defp queue_snapshot do
    Job
    |> group_by([job], [job.queue, job.state])
    |> select([job], {job.queue, job.state, count(job.id)})
    |> Repo.all()
    |> Enum.reduce(%{}, fn {queue, state, count}, acc ->
      Map.update(acc, queue, %{state => count}, &Map.put(&1, state, count))
    end)
  end

  defp recent_activity(filters) do
    application_events =
      ApplicationEvent
      |> join(:inner, [event], application in Application,
        on: application.id == event.application_id
      )
      |> maybe_filter_country_from_join(filters.country)
      |> order_by([event, _application], desc: event.inserted_at)
      |> limit(^@event_limit)
      |> select([event, application], %{
        id: event.id,
        kind: :application_event,
        event_type: event.event_type,
        actor: event.actor,
        application_id: event.application_id,
        country_code: application.country_code,
        inserted_at: event.inserted_at
      })
      |> Repo.all()

    webhook_events =
      WebhookEvent
      |> join(:left, [webhook], application in Application,
        on: application.id == webhook.application_id
      )
      |> maybe_filter_country_from_webhook_join(filters.country)
      |> order_by([webhook, _application], desc: webhook.inserted_at)
      |> limit(^@event_limit)
      |> select([webhook, application], %{
        id: webhook.id,
        kind: :webhook_event,
        event_type: webhook.event_type,
        actor: webhook.source,
        application_id: webhook.application_id,
        country_code: application.country_code,
        inserted_at: webhook.inserted_at,
        status: webhook.status
      })
      |> Repo.all()

    application_events
    |> Kernel.++(webhook_events)
    |> Enum.sort_by(& &1.inserted_at, {:desc, DateTime})
    |> Enum.take(@event_limit)
  end

  defp timeline(application_id) do
    ApplicationEvent
    |> where([event], event.application_id == ^application_id)
    |> order_by([event], desc: event.inserted_at)
    |> limit(^@detail_limit)
    |> Repo.all()
  end

  defp webhooks(application_id) do
    WebhookEvent
    |> where([webhook], webhook.application_id == ^application_id)
    |> order_by([webhook], desc: webhook.inserted_at)
    |> limit(^@detail_limit)
    |> Repo.all()
  end

  defp outbox_events(application_id) do
    OutboxEvent
    |> where(
      [event],
      (event.aggregate_type == "application" and event.aggregate_id == ^application_id) or
        fragment("?->>'application_id' = ?", event.payload, ^application_id)
    )
    |> order_by([event], desc: event.inserted_at)
    |> limit(^@detail_limit)
    |> Repo.all()
  end

  defp jobs(application_id) do
    Job
    |> where([job], fragment("?->>'application_id' = ?", job.args, ^application_id))
    |> order_by([job], desc: job.inserted_at)
    |> limit(^@detail_limit)
    |> Repo.all()
  end

  defp normalize_filters(filters) do
    %{
      country:
        filters
        |> Map.get("country", Map.get(filters, :country, @all_countries))
        |> normalize_country_filter(),
      status:
        filters
        |> Map.get("status", Map.get(filters, :status, @all_statuses))
        |> normalize_status_filter()
    }
  end

  defp normalize_country_filter(nil), do: @all_countries

  defp normalize_country_filter(country) when is_binary(country) do
    country
    |> String.trim()
    |> String.upcase()
    |> case do
      "" -> @all_countries
      "ALL" -> @all_countries
      normalized when byte_size(normalized) == 2 -> normalized
      _invalid -> @all_countries
    end
  end

  defp normalize_country_filter(_country), do: @all_countries

  defp normalize_status_filter(nil), do: @all_statuses

  defp normalize_status_filter(status) when is_binary(status) do
    normalized =
      status
      |> String.trim()
      |> String.downcase()

    cond do
      normalized in ["", "all"] ->
        @all_statuses

      normalized in Enum.map(Ecto.Enum.values(Application, :status), &Atom.to_string/1) ->
        normalized

      true ->
        @all_statuses
    end
  end

  defp normalize_status_filter(_status), do: @all_statuses

  defp maybe_filter_country(query, @all_countries), do: query

  defp maybe_filter_country(query, country),
    do: where(query, [application], application.country_code == ^country)

  defp maybe_filter_status(query, @all_statuses), do: query

  defp maybe_filter_status(query, status) do
    where(query, [application], application.status == ^String.to_existing_atom(status))
  rescue
    ArgumentError -> query
  end

  defp maybe_filter_country_from_join(query, @all_countries), do: query

  defp maybe_filter_country_from_join(query, country) do
    where(query, [_event, application], application.country_code == ^country)
  end

  defp maybe_filter_country_from_webhook_join(query, @all_countries), do: query

  defp maybe_filter_country_from_webhook_join(query, country) do
    where(query, [_webhook, application], application.country_code == ^country)
  end
end
