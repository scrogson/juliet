defmodule Juliet.Mixfile do
  use Mix.Project

  def project do
    [app: :juliet,
     version: "0.1.0",
     elixir: "~> 1.3",
     build_embedded: Mix.env == :prod,
     start_permanent: Mix.env == :prod,
     deps: deps()]
  end

  def application do
    [mod: {Juliet, []},
     applications: [
       :logger,
       :fast_xml,
       :ranch,
       :romeo,
       :uuid
    ]]
  end

  defp deps do
    [{:fast_xml, "~> 1.1"},
     {:ranch, "~> 1.2"},
     {:romeo, "~> 0.6"},
     {:uuid, "~> 1.1"}]
  end
end
