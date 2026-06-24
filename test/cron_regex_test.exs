defmodule PxImports.CronRegexTest do
  use ExUnit.Case, async: true

  @content """
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

  @new_cron """
  {Oban.Plugins.Cron,
       crontab: [
         {"50 2 * * *", MyApp.Workers.SyncMonthEndCloseWorker}
       ]}\
  """

  @bad_regex ~r/\{Oban\.Plugins\.Cron,\s*.*?\}/s
  @good_regex ~r/\{Oban\.Plugins\.Cron,\s*crontab:\s*\[.*?\]\s*\}/s

  test "broken regex leaves orphaned cron entries and fails to parse" do
    result = Regex.replace(@bad_regex, @content, @new_cron)

    assert String.contains?(result, "SyncOrgTreeWorker")
    assert String.contains?(result, "     ]}\n  ]")

    assert match?({:error, _}, Code.string_to_quoted(result))
  end

  test "fixed regex replaces full cron plugin and parses" do
    result = Regex.replace(@good_regex, @content, @new_cron)

    refute String.contains?(result, "     ]}\n    ]}")
    assert {:ok, _} = Code.string_to_quoted(result)
    assert String.contains?(result, "SyncMonthEndCloseWorker")
    refute String.contains?(result, "SyncEmployeesWorker")
  end
end
