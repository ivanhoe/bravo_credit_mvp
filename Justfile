set shell := ["zsh", "-cu"]
set dotenv-load := true

default:
  @just --list

db-up:
  docker compose up -d postgres

app-up:
  docker compose up --build

app-down:
  docker compose down

db-down:
  docker compose down

db-logs:
  docker compose logs -f postgres

db-ps:
  docker compose ps

setup:
  mix setup

seed-data:
  mix run priv/repo/seeds.exs

seed-tokens:
  mix bravo.seed.tokens

seed-tokens-env:
  mix bravo.seed.tokens --env

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
