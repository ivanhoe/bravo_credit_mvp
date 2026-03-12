defmodule BravoCredit.Repo.Migrations.AddApplicationEventOutboxTrigger do
  use Ecto.Migration

  def up do
    execute("CREATE EXTENSION IF NOT EXISTS pgcrypto", "")

    execute("""
    CREATE OR REPLACE FUNCTION sync_application_event_to_outbox()
    RETURNS trigger AS $$
    BEGIN
      INSERT INTO event_outbox (
        id,
        aggregate_type,
        aggregate_id,
        event_type,
        payload,
        status,
        attempts,
        next_attempt_at,
        inserted_at,
        updated_at
      )
      VALUES (
        gen_random_uuid(),
        'application_event',
        NEW.id,
        NEW.event_type,
        jsonb_build_object(
          'application_event_id', NEW.id,
          'application_id', NEW.application_id,
          'source_event_type', NEW.event_type,
          'actor', NEW.actor,
          'payload', COALESCE(NEW.payload, '{}'::jsonb)
        ),
        'pending',
        0,
        timezone('utc', now()),
        timezone('utc', now()),
        timezone('utc', now())
      );

      RETURN NEW;
    END;
    $$ LANGUAGE plpgsql;
    """)

    execute("""
    CREATE TRIGGER application_event_outbox_trigger
    AFTER INSERT ON application_events
    FOR EACH ROW
    EXECUTE FUNCTION sync_application_event_to_outbox();
    """)
  end

  def down do
    execute("DROP TRIGGER IF EXISTS application_event_outbox_trigger ON application_events", "")
    execute("DROP FUNCTION IF EXISTS sync_application_event_to_outbox()", "")
  end
end
