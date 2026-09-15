defmodule PxImports.ObanCron do
  @moduledoc false

  # Matches the Cron plugin tuple in all forms produced by Oban/ash_oban/mix format:
  #   {Oban.Plugins.Cron, []}
  #   {Oban.Plugins.Cron, crontab: []}
  #   {Oban.Plugins.Cron, crontab: [...]}
  #   {Oban.Plugins.Cron, [crontab: [...]]}
  #
  # Do not use `{Oban.Plugins.Cron, .*?}` — the first `}` is a crontab entry tuple,
  # which leaves orphaned entries and invalid Elixir.
  @cron_plugin_regex ~r/\{Oban\.Plugins\.Cron,\s*(?:\[\s*\]|crontab:\s*\[.*?\]|\[\s*crontab:\s*\[.*?\]\s*\])\s*\}/s

  @crontab_entries_regex ~r/\{Oban\.Plugins\.Cron,\s*(?:\[\s*)?crontab:\s*\[(.*?)\]/s

  def replace_plugin(content, new_plugin)
      when is_binary(content) and is_binary(new_plugin) do
    if Regex.match?(@cron_plugin_regex, content) do
      Regex.replace(@cron_plugin_regex, content, fn _match -> new_plugin end, global: false)
    else
      :no_match
    end
  end

  def extract_entries(content) when is_binary(content) do
    case Regex.run(@crontab_entries_regex, content, capture: :all_but_first) do
      [entries_block] ->
        Regex.scan(~r/\{"([^"]+)",\s*([^\}]+)\}/, entries_block)
        |> Enum.map(fn [_, cron, worker] -> {cron, String.trim(worker)} end)

      _ ->
        []
    end
  end

  def merge_entries(existing_entries, new_entries) do
    new_entries_as_strings =
      Enum.map(new_entries, fn {cron, worker} -> {cron, inspect(worker)} end)

    (existing_entries ++ new_entries_as_strings)
    |> Enum.reduce(%{}, fn {cron, worker}, acc ->
      Map.put(acc, worker, cron)
    end)
    |> Enum.map(fn {worker, cron} -> {cron, worker} end)
    |> Enum.sort_by(fn {_cron, worker} -> worker end)
  end

  def format_plugin(entries) do
    crontab_lines = format_crontab_lines(entries)

    """
    {Oban.Plugins.Cron,
         crontab: [
    #{crontab_lines}
         ]}\
    """
  end

  def format_crontab_lines(entries) do
    entries
    |> Enum.map(fn {cron, worker} -> ~s|       {"#{cron}", #{worker}}| end)
    |> Enum.join(",\n")
  end
end
