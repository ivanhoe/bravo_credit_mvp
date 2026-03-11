set shell := ["zsh", "-cu"]

default:
  @just --list

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
