set shell := ["zsh", "-cu"]

default:
  @just --list

db-up:
  docker compose up -d postgres

db-down:
  docker compose down

db-logs:
  docker compose logs -f postgres

db-ps:
  docker compose ps

setup:
  mix setup

server:
  mix phx.server

test:
  mix test

lint:
  mix format --check-formatted
  mix credo --strict

check:
  just lint
  just test

ecto-create:
  mix ecto.create

ecto-migrate:
  mix ecto.migrate
