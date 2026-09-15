defmodule PxImports.CronRegexTest do
  use ExUnit.Case, async: true

  alias PxImports.ObanCron

  @oban_with_empty_opts """
  config :myapp, Oban,
    engine: Oban.Engines.Basic,
    plugins: [{Oban.Plugins.Cron, []}]
  """

  @oban_with_multiline_empty_opts """
  config :myapp, Oban,
    engine: Oban.Engines.Basic,
    plugins: [
      {Oban.Plugins.Cron, []}
    ]
  """

  @oban_with_empty_crontab """
  config :myapp, Oban,
    engine: Oban.Engines.Basic,
    plugins: [
      {Oban.Plugins.Cron, crontab: []}
    ]
  """

  @oban_with_entries """
  config :myapp, Oban,
    engine: Oban.Engines.Basic,
    plugins: [
      {Oban.Plugins.Cron,
       crontab: [
         {"0 2 * * *", MyApp.Workers.SyncEmployeesWorker},
         {"0 3 * * *", MyApp.Workers.SyncOrgTreeWorker}
       ]}
    ]
  """

  @new_entries [{"59 2 * * *", MyApp.Workers.SyncEmployeeAbsencesWorker}]

  test "broken regex leaves orphaned cron entries and fails to parse" do
    bad_regex = ~r/\{Oban\.Plugins\.Cron,\s*.*?\}/s
    new_plugin = ObanCron.format_plugin([{"50 2 * * *", "MyApp.Workers.SyncMonthEndCloseWorker"}])
    result = Regex.replace(bad_regex, @oban_with_entries, new_plugin)

    assert String.contains?(result, "SyncOrgTreeWorker")
    assert match?({:error, _}, Code.string_to_quoted(result))
  end

  test "replaces default Oban Cron plugin with empty options list" do
    result = replace_with_new_entries(@oban_with_empty_opts)

    assert {:ok, _} = Code.string_to_quoted(result)
    assert String.contains?(result, "SyncEmployeeAbsencesWorker")
    refute String.contains?(result, "{Oban.Plugins.Cron, []}")
  end

  test "replaces multiline Oban Cron plugin with empty options list" do
    result = replace_with_new_entries(@oban_with_multiline_empty_opts)

    assert {:ok, _} = Code.string_to_quoted(result)
    assert String.contains?(result, "SyncEmployeeAbsencesWorker")
  end

  test "replaces Cron plugin with empty crontab keyword" do
    result = replace_with_new_entries(@oban_with_empty_crontab)

    assert {:ok, _} = Code.string_to_quoted(result)
    assert String.contains?(result, "SyncEmployeeAbsencesWorker")
  end

  test "merges new workers into an existing populated crontab" do
    result = replace_with_new_entries(@oban_with_entries)

    assert {:ok, _} = Code.string_to_quoted(result)
    assert String.contains?(result, "SyncEmployeesWorker")
    assert String.contains?(result, "SyncOrgTreeWorker")
    assert String.contains?(result, "SyncEmployeeAbsencesWorker")
  end

  test "extract_entries returns [] for empty Cron options" do
    assert ObanCron.extract_entries(@oban_with_empty_opts) == []
    assert ObanCron.extract_entries(@oban_with_multiline_empty_opts) == []
    assert ObanCron.extract_entries(@oban_with_empty_crontab) == []
  end

  defp replace_with_new_entries(content) do
    merged =
      content
      |> ObanCron.extract_entries()
      |> ObanCron.merge_entries(@new_entries)

    plugin = ObanCron.format_plugin(merged)

    assert is_binary(ObanCron.replace_plugin(content, plugin))
    ObanCron.replace_plugin(content, plugin)
  end
end
