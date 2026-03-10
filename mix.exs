defmodule PxImports.MixProject do
  use Mix.Project

  def project do
    [
      app: :px_imports,
      version: "0.1.0",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:igniter, "~> 0.7", optional: true},
      {:ash, "~> 3.0", optional: true},
      {:spark, "~> 2.0", optional: true}
    ]
  end
end
