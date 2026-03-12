defmodule BravoCredit.Countries.Loader do
  @moduledoc """
  Reads YAML files from disk and normalizes them into country config structs.
  """

  alias BravoCredit.Countries.Validator

  @spec load!(String.t(), map(), map()) :: %{
          String.t() => BravoCredit.Countries.CountryConfig.t()
        }
  def load!(path, validator_registry, provider_registry) do
    path
    |> list_config_files!()
    |> Enum.map(&load_file!(&1, validator_registry, provider_registry))
    |> build_country_map!()
  end

  defp list_config_files!(path) do
    files =
      path
      |> Path.join("*.yaml")
      |> Path.wildcard(match_dot: false)
      |> Kernel.++(
        path
        |> Path.join("*.yml")
        |> Path.wildcard(match_dot: false)
      )
      |> Enum.sort()

    case files do
      [] -> raise ArgumentError, "no country config files were found in #{inspect(path)}"
      files -> files
    end
  end

  defp load_file!(file_path, validator_registry, provider_registry) do
    file_path
    |> YamlElixir.read_from_file!()
    |> Validator.validate!(validator_registry, provider_registry)
  rescue
    error in [ArgumentError, YamlElixir.ParsingError, YamlElixir.FileNotFoundError] ->
      reraise(
        ArgumentError.exception(
          "failed to load #{Path.basename(file_path)}: #{Exception.message(error)}"
        ),
        __STACKTRACE__
      )
  end

  defp build_country_map!(configs) do
    Enum.reduce(configs, %{}, fn config, acc ->
      if Map.has_key?(acc, config.country_code) do
        raise ArgumentError, "duplicate country_code detected: #{config.country_code}"
      else
        Map.put(acc, config.country_code, config)
      end
    end)
  end
end
