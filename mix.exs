defmodule Razmetka.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/natasha-ex/razmetka"

  def project do
    [
      app: :razmetka,
      version: @version,
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description:
        "Priority-dispatch sentence classifier with pluggable ML fallback for Russian NLP",
      package: package(),
      docs: docs(),
      source_url: @source_url,
      aliases: aliases(),
      dialyzer: [plt_add_apps: [:ex_unit]]
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:yargy, "~> 0.4"},
      {:nx, "~> 0.9", optional: true},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false}
    ]
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url},
      maintainers: ["Danila Poyarkov"]
    ]
  end

  defp aliases do
    [
      lint: ["format --check-formatted", "credo --strict", "dialyzer"]
    ]
  end

  defp docs do
    [
      main: "Razmetka",
      source_ref: "v#{@version}"
    ]
  end
end
