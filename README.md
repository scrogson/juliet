# Juliet

> An XMPP Server in Elixir

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed as:

  1. Add juliet to your list of dependencies in `mix.exs`:

        def deps do
          [{:juliet, "~> 0.0.1"}]
        end

  2. Ensure juliet is started before your application:

        def application do
          [applications: [:juliet]]
        end
