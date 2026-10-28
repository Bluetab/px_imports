defmodule PxImports.PlannedHoursInstallTest do
  use ExUnit.Case, async: true

  import Igniter.Test

  @resource_path "lib/test/projects/planned_hour.ex"
  @worker_path "lib/test/workers/sync_planned_hours_worker.ex"
  @domain_path "lib/test/projects.ex"
  @absences_worker_path "lib/test/workers/sync_employee_absences_worker.ex"

  # The installer only patches config/config.exs when it exists
  @config """
  import Config

  config :test, Oban,
    engine: Oban.Engines.Basic,
    queues: [default: 10],
    repo: Test.Repo,
    plugins: [{Oban.Plugins.Cron, []}]
  """

  defp install(argv \\ ["--planned-hours"]) do
    [files: %{"config/config.exs" => @config}]
    |> test_project()
    |> Igniter.compose_task("px_imports.install", argv)
  end

  defp content(igniter, path) do
    source = igniter.rewrite.sources[path]
    assert source, "expected #{path} to exist, got: #{created_files(igniter)}"
    Rewrite.Source.get(source, :content)
  end

  # Igniter formats generated code with or without parens depending on the host project's
  # formatter config, so `table "x"` and `table("x")` are the same thing to these tests
  defp assert_call(source, name, args) do
    pattern = ~r/\b#{Regex.escape(name)}\(?\s*#{Regex.escape(args)}\s*\)?/

    assert source =~ pattern, "expected a call to #{name} #{args} in:\n#{source}"
  end

  # The direct `resource ...` calls of the domain's `resources do` block
  defp resources_children(quoted) do
    {_, found} =
      Macro.prewalk(quoted, nil, fn
        {:resources, _, [[do: body]]} = node, nil -> {node, body}
        node, acc -> {node, acc}
      end)

    case found do
      {:__block__, _, children} -> children
      single -> [single]
    end
  end

  defp resource_name({:resource, _, [{:__aliases__, _, parts} | _]}), do: Enum.join(parts, ".")

  describe "mix px_imports.install --planned-hours" do
    test "creates the PlannedHour resource, the worker and the Projects domain" do
      igniter = install()

      assert_creates(igniter, @resource_path)
      assert_creates(igniter, @worker_path)
      assert_creates(igniter, @domain_path)
    end

    test "the generated resource is keyed by employee number, project and month" do
      resource = install() |> content(@resource_path)

      assert resource =~ "defmodule Test.Projects.PlannedHour do"
      assert_call(resource, "table", ~s|"planned_hours"|)

      for {name, type} <- [
            employee_number: :integer,
            doc_num: :integer,
            project_name: :string,
            month: :string,
            hours: :float,
            hidden_at: :utc_datetime
          ] do
        assert_call(resource, "attribute", ":#{name}, :#{type}")
      end

      assert_call(
        resource,
        "identity",
        ":unique_employee_doc_num_month, [:employee_number, :doc_num, :month]"
      )
    end

    test "the sync action only updates what can change for a given key" do
      resource = install() |> content(@resource_path)

      [_, sync_action] = String.split(resource, "update :sync_from_px do", parts: 2)
      [sync_action | _] = String.split(sync_action, "\n  end\n", parts: 2)

      assert sync_action =~ ":project_name"
      assert sync_action =~ ":hours"
      assert sync_action =~ ":hidden_at"
      refute sync_action =~ ":employee_number"
      refute sync_action =~ ":doc_num"
      refute sync_action =~ ":month"
    end

    test "the generated worker reads from Px.Rest.list_planned_hours/1" do
      worker = install() |> content(@worker_path)

      assert worker =~ "defmodule Test.Workers.SyncPlannedHoursWorker do"
      assert worker =~ "use Oban.Worker"
      assert worker =~ "BluetabConnect.Px.Rest.list_planned_hours()"
      assert worker =~ ~s|"planned_hours" => planned_hours|
    end

    test "the generated modules are valid Elixir" do
      igniter = install()

      for path <- [@resource_path, @worker_path, @domain_path] do
        assert {:ok, _quoted} = igniter |> content(path) |> Code.string_to_quoted(),
               "#{path} does not parse"
      end
    end

    test "registers the resource in the Projects domain" do
      domain = install() |> content(@domain_path)

      assert_call(domain, "resource", "Test.Projects.PlannedHour")
    end

    test "schedules the worker daily at 03:02" do
      config = install() |> content("config/config.exs")

      assert config =~ ~s|{"2 3 * * *", Test.Workers.SyncPlannedHoursWorker}|
      assert {:ok, _quoted} = Code.string_to_quoted(config)
    end

    test "does not install anything but planned hours" do
      igniter = install()

      refute_creates(igniter, @absences_worker_path)
      refute_creates(igniter, "lib/test/workers/sync_employee_per_diems_worker.ex")
      refute_creates(igniter, "lib/test/projects/employee_absence.ex")
    end

    test "combines with other flags in one Projects domain and one crontab" do
      igniter = install(["--planned-hours", "--employee-absences"])

      domain = content(igniter, @domain_path)
      assert_call(domain, "resource", "Test.Projects.PlannedHour")
      assert_call(domain, "resource", "Test.Projects.EmployeeAbsence")

      assert_creates(igniter, @worker_path)
      assert_creates(igniter, @absences_worker_path)

      config = content(igniter, "config/config.exs")
      assert config =~ ~s|{"2 3 * * *", Test.Workers.SyncPlannedHoursWorker}|
      assert config =~ ~s|{"59 2 * * *", Test.Workers.SyncEmployeeAbsencesWorker}|
      assert {:ok, _quoted} = Code.string_to_quoted(config)
    end

    test "running it twice does not duplicate the cron entry" do
      once = install()
      config_once = content(once, "config/config.exs")

      twice =
        [files: %{"config/config.exs" => config_once}]
        |> test_project()
        |> Igniter.compose_task("px_imports.install", ["--planned-hours"])

      config_twice = content(twice, "config/config.exs")

      assert length(String.split(config_twice, "SyncPlannedHoursWorker")) == 2
    end

    # Tempo's domain has a `resource X do ... end` block (code interface); the new resource
    # must land next to it in `resources`, not inside it
    test "adds the resource to the domain's resources block, not inside a nested resource block" do
      domain = """
      defmodule Test.Projects do
        use Ash.Domain, otp_app: :test

        resources do
          resource Test.Projects.Cluster

          resource Test.Projects.Holiday do
            define :list_holidays, action: :list_active
          end

          resource Test.Projects.MonthEndClose
        end
      end
      """

      igniter =
        [files: %{"config/config.exs" => @config, @domain_path => domain}]
        |> test_project()
        |> Igniter.compose_task("px_imports.install", ["--planned-hours"])

      {:ok, quoted} = igniter |> content(@domain_path) |> Code.string_to_quoted()

      assert resources_children(quoted) |> Enum.map(&resource_name/1) == [
               "Test.Projects.Cluster",
               "Test.Projects.Holiday",
               "Test.Projects.MonthEndClose",
               "Test.Projects.PlannedHour"
             ]

      holiday = Enum.find(resources_children(quoted), &(resource_name(&1) =~ "Holiday"))
      refute inspect(holiday) =~ "PlannedHour"
    end

    test "with no flag at all, planned hours is listed among the options in the issue" do
      igniter = install([])

      assert_has_issue(igniter, &(&1 =~ "--planned-hours"))
    end
  end
end
