if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Tasks.PxImports.Install do
    @shortdoc "Adds Oban job admin UI and PX sync workers to an Ash Phoenix project"

    @moduledoc """
    Wires a Phoenix + Ash + Oban project into the PX (Bluetab Connect) ecosystem.

    ## Prerequisites

    - Project created with `ash_authentication_phoenix` and `bluetab_phoenix` (includes `bds`)
    - `:oban` and `:oban_web` must already be in your `mix.exs` dependencies
    - Admin UI uses Bluetab Design System (`bt_*` components); installer adds
      `import Bds.Components.CatalogUi` when missing

    ## What is always generated

      * `<App>.Jobs` context for querying Oban jobs
      * `<App>Web.AdminLive` admin dashboard
      * `<App>Web.Admin.JobsLive` scheduled/recent jobs list with manual trigger
      * `<App>Web.Admin.JobShowLive` detailed job inspection (meta, errors)
      * Router entries: `/admin`, `/admin/jobs`, `/admin/jobs/:id`
      * Dev-mode `oban_dashboard("/oban")` route
      * Oban config block in `config/config.exs`

    ## Flags

    At least one must be provided:

      * `--org-tree` — generates Ash resources under `<App>.Projects`
        (BusinessUnit, Cluster, ClientGroup, Client, Project) plus
        `SyncProjectsWorker` (module only; invoked from org-tree sync) and
        `SyncOrgTreeWorker` (daily at 03:00). Projects attach to a client and/or cluster.

      * `--spend-types` — generates `<App>.Projects.SpendType` Ash resource
        plus `SyncSpendTypesWorker` (daily at 02:45)

      * `--hour-types` — generates `<App>.Projects.HourType` Ash resource
        plus `SyncHourTypesWorker` (daily at 02:47)

      * `--month_close` — generates `<App>.Projects.MonthEndClose` Ash resource
        plus `SyncMonthEndCloseWorker` (daily at 02:50)

      * `--positions` — generates `<App>.Projects.Position` and
        `<App>.Projects.PositionRelationship` Ash resources plus
        `SyncPositionsWorker` (daily at 02:55)

      * `--holidays` — generates `<App>.Projects.Holiday` Ash resource
        plus `SyncHolidaysWorker` (daily at 02:58), flattening SuccessFactors
        holiday calendars into holiday rows with `calendar_code`.

      * `--users` — patches `Accounts.User` with PX employee fields (see generated
        resource), `:provision_from_employee_sync`, `:sync_employee_fields`,
        `:list_for_admin`, `:set_admin`, and `SyncEmployeesWorker` (daily at 02:00).
        Also generates `/admin/users` (`Admin.UsersLive`) and complete impersonation
        flow (`ImpersonationController` + banner wiring in `LiveUserAuth`/`Layouts`).
        Sync creates users when an employee email is not yet present. Stores PX
        `category`, `category_name`, and `hub` as strings only
        (no separate Catalog domain).

        If this installer was already run with `--users`, Ash Igniter skips
        attributes and actions that already exist and does not overwrite an
        existing `SyncEmployeesWorker` module. Add new columns and merge by hand,
        or remove the worker module and re-run to regenerate it.

    ## Usage

        mix px_imports.install --org-tree
        mix px_imports.install --users
        mix px_imports.install --spend-types
        mix px_imports.install --hour-types
        mix px_imports.install --month_close
        mix px_imports.install --positions
        mix px_imports.install --holidays
        mix px_imports.install --org-tree --users
    """

    use Igniter.Mix.Task

    @impl Igniter.Mix.Task
    def info(_argv, _composing_task) do
      %Igniter.Mix.Task.Info{
        group: :px_imports,
        example: "mix px_imports.install --org-tree --users",
        schema: [
          users: :boolean,
          org_tree: :boolean,
          spend_types: :boolean,
          hour_types: :boolean,
          month_close: :boolean,
          positions: :boolean,
          holidays: :boolean
        ]
      }
    end

    @impl Igniter.Mix.Task
    def igniter(igniter) do
      opts = igniter.args.options
      install_org_tree? = Keyword.get(opts, :org_tree, false)
      install_users? = Keyword.get(opts, :users, false)
      install_spend_types? = Keyword.get(opts, :spend_types, false)
      install_hour_types? = Keyword.get(opts, :hour_types, false)
      install_month_close? = Keyword.get(opts, :month_close, false)
      install_positions? = Keyword.get(opts, :positions, false)
      install_holidays? = Keyword.get(opts, :holidays, false)

      if not (install_org_tree? or install_users? or install_spend_types? or install_hour_types? or
                install_month_close? or install_positions? or install_holidays?) do
        Igniter.add_issue(igniter, """
        At least one of --org-tree, --users, --spend-types, --hour-types, --month_close, --positions, or --holidays must be specified.

        Examples:
          mix px_imports.install --org-tree
          mix px_imports.install --users
          mix px_imports.install --spend-types
          mix px_imports.install --hour-types
          mix px_imports.install --month_close
          mix px_imports.install --positions
          mix px_imports.install --holidays
          mix px_imports.install --org-tree --users
        """)
      else
        prefix = Igniter.Project.Module.module_name_prefix(igniter)

        otp_app =
          prefix |> Module.split() |> List.last() |> Macro.underscore() |> String.to_atom()

        web_module = :"#{prefix}Web"

        router_module = Module.concat(web_module, Router)
        live_user_auth_module = Module.concat(web_module, LiveUserAuth)
        layouts_module = Module.concat(web_module, Layouts)
        repo_module = Module.concat(prefix, Repo)
        accounts_module = Module.concat(prefix, Accounts)
        user_resource_module = Module.concat([prefix, Accounts, User])

        jobs_module = Module.concat(prefix, Jobs)
        home_live_module = Module.concat(web_module, HomeLive)
        admin_live_module = Module.concat(web_module, AdminLive)
        jobs_live_module = Module.concat([web_module, Admin, JobsLive])
        job_show_live_module = Module.concat([web_module, Admin, JobShowLive])
        users_live_module = Module.concat([web_module, Admin, UsersLive])
        impersonation_controller_module = Module.concat(web_module, ImpersonationController)

        projects_domain_module = Module.concat(prefix, Projects)
        sync_org_tree_worker_module = Module.concat([prefix, Workers, SyncOrgTreeWorker])
        sync_employees_worker_module = Module.concat([prefix, Workers, SyncEmployeesWorker])
        sync_projects_worker_module = Module.concat([prefix, Workers, SyncProjectsWorker])
        sync_spend_types_worker_module = Module.concat([prefix, Workers, SyncSpendTypesWorker])
        sync_hour_types_worker_module = Module.concat([prefix, Workers, SyncHourTypesWorker])
        sync_positions_worker_module = Module.concat([prefix, Workers, SyncPositionsWorker])
        sync_holidays_worker_module = Module.concat([prefix, Workers, SyncHolidaysWorker])

        sync_month_end_close_worker_module =
          Module.concat([prefix, Workers, SyncMonthEndCloseWorker])

        cron_entries =
          []
          |> then(fn e ->
            if install_users?,
              do: e ++ [{"0 2 * * *", sync_employees_worker_module}],
              else: e
          end)
          |> then(fn e ->
            if install_org_tree?,
              do: e ++ [{"0 3 * * *", sync_org_tree_worker_module}],
              else: e
          end)
          |> then(fn e ->
            if install_spend_types?,
              do: e ++ [{"45 2 * * *", sync_spend_types_worker_module}],
              else: e
          end)
          |> then(fn e ->
            if install_hour_types?,
              do: e ++ [{"47 2 * * *", sync_hour_types_worker_module}],
              else: e
          end)
          |> then(fn e ->
            if install_month_close?,
              do: e ++ [{"50 2 * * *", sync_month_end_close_worker_module}],
              else: e
          end)
          |> then(fn e ->
            if install_positions?,
              do: e ++ [{"55 2 * * *", sync_positions_worker_module}],
              else: e
          end)
          |> then(fn e ->
            if install_holidays?,
              do: e ++ [{"58 2 * * *", sync_holidays_worker_module}],
              else: e
          end)

        org_tree_resources =
          if install_org_tree? do
            [
              Module.concat([prefix, Projects, BusinessUnit]),
              Module.concat([prefix, Projects, Cluster]),
              Module.concat([prefix, Projects, ClientGroup]),
              Module.concat([prefix, Projects, Client]),
              Module.concat([prefix, Projects, Project])
            ]
          else
            []
          end

        project_resources =
          []
          |> then(fn resources ->
            if install_spend_types?,
              do: resources ++ [Module.concat([prefix, Projects, SpendType])],
              else: resources
          end)
          |> then(fn resources ->
            if install_hour_types?,
              do: resources ++ [Module.concat([prefix, Projects, HourType])],
              else: resources
          end)
          |> then(fn resources ->
            if install_month_close?,
              do: resources ++ [Module.concat([prefix, Projects, MonthEndClose])],
              else: resources
          end)
          |> then(fn resources ->
            if install_positions? do
              resources ++
                [
                  Module.concat([prefix, Projects, Position]),
                  Module.concat([prefix, Projects, PositionRelationship])
                ]
            else
              resources
            end
          end)
          |> then(fn resources ->
            if install_holidays?,
              do: resources ++ [Module.concat([prefix, Projects, Holiday])],
              else: resources
          end)

        all_project_resources = org_tree_resources ++ project_resources

        domains_to_add =
          if install_org_tree? or install_spend_types? or install_hour_types? or
               install_month_close? or
               install_positions? or install_holidays?,
             do: [projects_domain_module],
             else: []

        igniter
        |> check_oban_present()
        |> ensure_bds_catalog_ui_import(otp_app)
        |> setup_oban_config(otp_app, repo_module, cron_entries)
        |> update_ash_domains_config(otp_app, domains_to_add)
        |> create_jobs_context(jobs_module, repo_module, otp_app)
        |> create_admin_live(
          admin_live_module,
          web_module,
          live_user_auth_module,
          install_users?
        )
        |> create_jobs_live(jobs_live_module, web_module, live_user_auth_module, jobs_module)
        |> create_job_show_live(
          job_show_live_module,
          web_module,
          live_user_auth_module,
          jobs_module
        )
        |> update_router(router_module, live_user_auth_module, install_users?)
        |> then(fn ign ->
          if install_org_tree? do
            ign
            |> create_projects_domain(projects_domain_module, all_project_resources, otp_app)
            |> create_business_unit(
              Module.concat([prefix, Projects, BusinessUnit]),
              projects_domain_module,
              repo_module
            )
            |> create_cluster(
              Module.concat([prefix, Projects, Cluster]),
              projects_domain_module,
              repo_module
            )
            |> create_client_group(
              Module.concat([prefix, Projects, ClientGroup]),
              projects_domain_module,
              repo_module
            )
            |> create_client(
              Module.concat([prefix, Projects, Client]),
              projects_domain_module,
              repo_module
            )
            |> create_project_resource(
              Module.concat([prefix, Projects, Project]),
              projects_domain_module,
              repo_module
            )
            |> create_sync_projects_worker(
              sync_projects_worker_module,
              projects_domain_module,
              prefix
            )
            |> create_sync_org_tree_worker(
              sync_org_tree_worker_module,
              projects_domain_module,
              prefix
            )
          else
            ign
          end
        end)
        |> then(fn ign ->
          if install_users? do
            ign
            |> patch_user_resource(user_resource_module)
            |> create_users_live(
              users_live_module,
              web_module,
              live_user_auth_module,
              accounts_module,
              user_resource_module
            )
            |> patch_users_live(users_live_module)
            |> create_impersonation_controller(
              impersonation_controller_module,
              web_module,
              prefix
            )
            |> patch_live_user_auth_for_impersonation(live_user_auth_module, prefix)
            |> patch_layouts_for_impersonation(layouts_module)
            |> patch_layouts_invocations_for_impersonation([
              home_live_module,
              admin_live_module,
              jobs_live_module,
              job_show_live_module,
              users_live_module
            ])
            |> create_sync_employees_worker(
              sync_employees_worker_module,
              prefix,
              user_resource_module
            )
          else
            ign
          end
        end)
        |> then(fn ign ->
          if install_spend_types? do
            spend_type_module = Module.concat([prefix, Projects, SpendType])

            ign
            |> then(fn i ->
              if install_org_tree? or install_spend_types? do
                i
              else
                create_projects_domain(i, projects_domain_module, all_project_resources, otp_app)
              end
            end)
            |> ensure_resource_in_domain(projects_domain_module, spend_type_module)
            |> create_spend_type_resource(
              spend_type_module,
              projects_domain_module,
              repo_module
            )
            |> create_sync_spend_types_worker(
              sync_spend_types_worker_module,
              projects_domain_module,
              prefix
            )
          else
            ign
          end
        end)
        |> then(fn ign ->
          if install_month_close? do
            month_end_close_module = Module.concat([prefix, Projects, MonthEndClose])

            ign
            |> then(fn i ->
              if install_org_tree? or install_spend_types? do
                i
              else
                create_projects_domain(i, projects_domain_module, all_project_resources, otp_app)
              end
            end)
            |> ensure_resource_in_domain(projects_domain_module, month_end_close_module)
            |> create_month_end_close_resource(
              month_end_close_module,
              projects_domain_module,
              repo_module
            )
            |> create_sync_month_end_close_worker(
              sync_month_end_close_worker_module,
              projects_domain_module,
              prefix
            )
          else
            ign
          end
        end)
        |> then(fn ign ->
          if install_hour_types? do
            hour_type_module = Module.concat([prefix, Projects, HourType])

            ign
            |> then(fn i ->
              if install_org_tree? or install_spend_types? or install_month_close? do
                i
              else
                create_projects_domain(i, projects_domain_module, all_project_resources, otp_app)
              end
            end)
            |> ensure_resource_in_domain(projects_domain_module, hour_type_module)
            |> create_hour_type_resource(
              hour_type_module,
              projects_domain_module,
              repo_module
            )
            |> create_sync_hour_types_worker(
              sync_hour_types_worker_module,
              projects_domain_module,
              prefix
            )
          else
            ign
          end
        end)
        |> then(fn ign ->
          if install_positions? do
            position_module = Module.concat([prefix, Projects, Position])
            position_relationship_module = Module.concat([prefix, Projects, PositionRelationship])

            ign
            |> then(fn i ->
              if install_org_tree? or install_spend_types? or install_hour_types? or
                   install_month_close? do
                i
              else
                create_projects_domain(i, projects_domain_module, all_project_resources, otp_app)
              end
            end)
            |> ensure_resource_in_domain(projects_domain_module, position_module)
            |> ensure_resource_in_domain(projects_domain_module, position_relationship_module)
            |> create_position_resource(
              position_module,
              projects_domain_module,
              repo_module
            )
            |> create_position_relationship_resource(
              position_relationship_module,
              projects_domain_module,
              repo_module
            )
            |> create_sync_positions_worker(
              sync_positions_worker_module,
              projects_domain_module,
              prefix
            )
          else
            ign
          end
        end)
        |> then(fn ign ->
          if install_holidays? do
            holiday_module = Module.concat([prefix, Projects, Holiday])

            ign
            |> then(fn i ->
              if install_org_tree? or install_spend_types? or install_hour_types? or
                   install_month_close? or
                   install_positions? do
                i
              else
                create_projects_domain(i, projects_domain_module, all_project_resources, otp_app)
              end
            end)
            |> ensure_resource_in_domain(projects_domain_module, holiday_module)
            |> create_holiday_resource(
              holiday_module,
              projects_domain_module,
              repo_module
            )
            |> create_sync_holidays_worker(
              sync_holidays_worker_module,
              projects_domain_module,
              prefix
            )
          else
            ign
          end
        end)
        |> Igniter.add_notice("""
        PxImports has been configured!

        Next steps:

        1. Generate and run database migrations:

             mix ash_postgres.generate_migrations --name px_imports
             mix ash_postgres.migrate

        2. Verify your Oban config in config/config.exs includes the correct
           repo and cron schedule.

        3. Ensure the following env vars are set for BluetabConnect:

             PX_BASE_URL=https://your-px-instance.example.com
             PX_BEARER_TOKEN=your-bearer-token

        4. The Oban dev dashboard is available at /oban (dev mode only).

        5. The jobs admin page is at /admin/jobs.

        6. With --users, the users admin page is at /admin/users and impersonation
           routes are available at:
             POST /admin/impersonation/start/:user_id
             GET /admin/impersonation/stop

        7. To install spend type sync only:

             mix px_imports.install --spend-types

        8. To install month end close sync only:

             mix px_imports.install --month_close

        9. To install hour type sync only:

             mix px_imports.install --hour-types

        10. To install positions sync only:

             mix px_imports.install --positions

        11. To install holidays sync only:

             mix px_imports.install --holidays
        """)
      end
    end

    # ──────────────────────────────────────────────
    # Validation & environment checks
    # ──────────────────────────────────────────────

    defp ensure_bds_catalog_ui_import(igniter, otp_app) do
      web_path = "lib/#{otp_app}_web.ex"

      if Igniter.exists?(igniter, web_path) do
        Igniter.update_file(igniter, web_path, fn source ->
          content = Rewrite.Source.get(source, :content)

          content =
            cond do
              String.contains?(content, "Bds.Components.CatalogUi") ->
                content

              String.contains?(content, "import Bds.Components\n") ->
                String.replace(
                  content,
                  "import Bds.Components\n",
                  "import Bds.Components\n      import Bds.Components.CatalogUi\n",
                  global: false
                )

              String.contains?(content, "import Bds.Components") ->
                String.replace(
                  content,
                  "import Bds.Components",
                  "import Bds.Components\n      import Bds.Components.CatalogUi",
                  global: false
                )

              true ->
                content
            end

          Rewrite.Source.update(source, :content, content)
        end)
      else
        igniter
      end
    end

    defp check_oban_present(igniter) do
      mix_exs_content = File.read!("mix.exs")

      oban_present? = String.contains?(mix_exs_content, ":oban")
      oban_web_present? = String.contains?(mix_exs_content, ":oban_web")

      igniter =
        if oban_present? do
          igniter
        else
          Igniter.add_issue(igniter, """
          Could not find :oban in your project dependencies.

          Please add the following to your mix.exs before running this installer:

              {:oban, "~> 2.0"},
              {:oban_web, "~> 2.0"},
              {:ash_oban, "~> 0.7"}
          """)
        end

      if oban_web_present? do
        igniter
      else
        Igniter.add_warning(igniter, """
        :oban_web was not found in your dependencies. The Oban dev dashboard
        route will be added to your router, but you'll need to add
        `{:oban_web, "~> 2.0"}` to your mix.exs for it to work.
        """)
      end
    end

    # ──────────────────────────────────────────────
    # Config: Oban block
    # ──────────────────────────────────────────────

    defp setup_oban_config(igniter, otp_app, repo_module, cron_entries) do
      Igniter.update_file(igniter, "config/config.exs", fn source ->
        content = Rewrite.Source.get(source, :content)

        all_workers_present? =
          cron_entries != [] and
            Enum.all?(cron_entries, fn {_cron, worker} ->
              String.contains?(content, inspect(worker))
            end)

        if all_workers_present? do
          source
        else
          otp_app_str = inspect(otp_app)

          merged_cron_entries =
            content
            |> extract_existing_cron_entries()
            |> merge_cron_entries(cron_entries)

          crontab_lines =
            merged_cron_entries
            |> Enum.map(fn {cron, worker} ->
              ~s|       {"#{cron}", #{worker}}|
            end)
            |> Enum.join(",\n")

          new_cron_plugin = """
          {Oban.Plugins.Cron,
               crontab: [
          #{crontab_lines}
               ]}\
          """

          new_content =
            cond do
              # Oban block exists with an empty or non-empty Cron plugin — replace it
              String.contains?(content, "#{otp_app_str}, Oban") and
                  String.contains?(content, "Oban.Plugins.Cron") ->
                Regex.replace(
                  ~r/\{Oban\.Plugins\.Cron,\s*.*?\}/s,
                  content,
                  new_cron_plugin,
                  global: false
                )

              # Oban block exists but no Cron plugin at all — inject into plugins list
              String.contains?(content, "#{otp_app_str}, Oban") ->
                String.replace(
                  content,
                  "plugins: [",
                  "plugins: [\n    #{new_cron_plugin},",
                  global: false
                )

              # No Oban block at all — inject the full block
              true ->
                oban_block = """

                config :ash_oban, pro?: false

                config #{otp_app_str}, Oban,
                  engine: Oban.Engines.Basic,
                  notifier: Oban.Notifiers.Postgres,
                  queues: [default: 10],
                  repo: #{inspect(repo_module)},
                  plugins: [
                    {Oban.Plugins.Cron,
                     crontab: [
                #{crontab_lines}
                     ]}
                  ]
                """

                String.trim_trailing(content) <> oban_block
            end

          Rewrite.Source.update(source, :content, new_content)
        end
      end)
    end

    defp extract_existing_cron_entries(content) do
      case Regex.run(
             ~r/\{Oban\.Plugins\.Cron,\s*.*?crontab:\s*\[(.*?)\]\s*\}/s,
             content,
             capture: :all_but_first
           ) do
        [entries_block] ->
          Regex.scan(~r/\{"([^"]+)",\s*([^\}]+)\}/, entries_block)
          |> Enum.map(fn [_, cron, worker] -> {cron, String.trim(worker)} end)

        _ ->
          []
      end
    end

    defp merge_cron_entries(existing_entries, new_entries) do
      new_entries_as_strings =
        Enum.map(new_entries, fn {cron, worker} -> {cron, inspect(worker)} end)

      (existing_entries ++ new_entries_as_strings)
      |> Enum.reduce(%{}, fn {cron, worker}, acc ->
        Map.put(acc, worker, cron)
      end)
      |> Enum.map(fn {worker, cron} -> {cron, worker} end)
      |> Enum.sort_by(fn {_cron, worker} -> worker end)
    end

    # ──────────────────────────────────────────────
    # Config: ash_domains list
    # ──────────────────────────────────────────────

    defp update_ash_domains_config(igniter, _otp_app, []), do: igniter

    defp update_ash_domains_config(igniter, otp_app, domains) do
      Enum.reduce(domains, igniter, fn domain, ign ->
        Igniter.update_file(ign, "config/config.exs", fn source ->
          content = Rewrite.Source.get(source, :content)
          domain_str = inspect(domain)

          if String.contains?(content, domain_str) do
            source
          else
            content =
              cond do
                String.contains?(content, "ash_domains:") ->
                  Regex.replace(
                    ~r/(ash_domains:\s*\[)([^\]]*)\]/,
                    content,
                    fn _, prefix, existing ->
                      existing_trimmed = String.trim(existing)
                      separator = if existing_trimmed == "", do: "", else: ", "
                      "#{prefix}#{existing}#{separator}#{domain_str}]"
                    end,
                    global: false
                  )

                true ->
                  String.trim_trailing(content) <>
                    "\n\nconfig #{inspect(otp_app)},\n  ash_domains: [#{domain_str}]\n"
              end

            Rewrite.Source.update(source, :content, content)
          end
        end)
      end)
    end

    # ──────────────────────────────────────────────
    # Jobs context
    # ──────────────────────────────────────────────

    defp create_jobs_context(igniter, jobs_module, repo_module, otp_app) do
      {exists?, igniter} = Igniter.Project.Module.module_exists(igniter, jobs_module)

      if exists? do
        igniter
      else
        contents = """
        @moduledoc \"\"\"
        Context for querying and managing Oban jobs.
        \"\"\"

        import Ecto.Query

        alias #{inspect(repo_module)}, as: Repo

        @doc \"\"\"
        Returns the list of configured cron jobs from the Oban config.
        \"\"\"
        def list_scheduled_jobs do
          oban_config = Application.fetch_env!(#{inspect(otp_app)}, Oban)

          oban_config
          |> Keyword.get(:plugins, [])
          |> Enum.flat_map(fn
            {Oban.Plugins.Cron, opts} -> Keyword.get(opts, :crontab, [])
            _ -> []
          end)
          |> Enum.map(fn {cron_expr, worker} ->
            %{
              worker: worker_name(worker),
              worker_module: worker,
              cron: cron_expr
            }
          end)
        end

        @doc \"\"\"
        Returns recent Oban job executions, most recent first.
        \"\"\"
        def list_recent_jobs(limit \\\\ 50) do
          from(j in "oban_jobs",
            select: %{
              id: j.id,
              worker: j.worker,
              state: j.state,
              queue: j.queue,
              attempt: j.attempt,
              max_attempts: j.max_attempts,
              inserted_at: j.inserted_at,
              attempted_at: j.attempted_at,
              completed_at: j.completed_at,
              errors: j.errors,
              meta: j.meta
            },
            order_by: [desc: j.id],
            limit: ^limit
          )
          |> Repo.all()
        end

        @doc \"\"\"
        Gets a single Oban job by ID.
        \"\"\"
        def get_job!(id) do
          from(j in "oban_jobs",
            select: %{
              id: j.id,
              worker: j.worker,
              state: j.state,
              queue: j.queue,
              args: j.args,
              attempt: j.attempt,
              max_attempts: j.max_attempts,
              inserted_at: j.inserted_at,
              scheduled_at: j.scheduled_at,
              attempted_at: j.attempted_at,
              completed_at: j.completed_at,
              cancelled_at: j.cancelled_at,
              discarded_at: j.discarded_at,
              errors: j.errors,
              meta: j.meta
            },
            where: j.id == ^id
          )
          |> Repo.one!()
        end

        @doc \"\"\"
        Manually enqueues a job for the given worker module.
        \"\"\"
        def run_job_now(worker_module) do
          worker_module.new(%{})
          |> Oban.insert()
        end

        defp worker_name(module) when is_atom(module) do
          module
          |> Module.split()
          |> List.last()
        end
        """

        Igniter.Project.Module.create_module(igniter, jobs_module, contents)
      end
    end

    # ──────────────────────────────────────────────
    # Admin LiveViews
    # ──────────────────────────────────────────────

    defp create_admin_live(
           igniter,
           admin_live_module,
           web_module,
           live_user_auth_module,
           include_users?
         ) do
      full_contents =
        PxImports.AdminTemplates.admin_live_module(
          web_module,
          live_user_auth_module,
          include_users?
        )

      {exists?, igniter} = Igniter.Project.Module.module_exists(igniter, admin_live_module)

      if exists? do
        case Igniter.Project.Module.find_module(igniter, admin_live_module) do
          {:ok, {igniter, source, _zipper}} ->
            path = Rewrite.Source.get(source, :path)

            Igniter.update_file(igniter, path, fn source ->
              content = Rewrite.Source.get(source, :content)

              has_jobs_card? = String.contains?(content, ~s|navigate={~p"/admin/jobs"}|)
              has_users_card? = String.contains?(content, ~s|navigate={~p"/admin/users"}|)
              uses_bds? = String.contains?(content, "bt_example_grid")

              if uses_bds? and has_jobs_card? and (not include_users? or has_users_card?) do
                source
              else
                render_body = PxImports.AdminTemplates.admin_live_render(include_users?)

                new_content =
                  Regex.replace(
                    ~r/(def render\(assigns\) do\s*~H""")(.*?)("""(\s*)end)/s,
                    content,
                    fn _, open, _old_body, close, _ ->
                      open <>
                        """

                        <Layouts.app
                          flash={@flash}
                          current_user={@current_user}
                          current_path={assigns[:current_path] || "/"}
                          impersonator={assigns[:impersonator]}
                        >
                    """ <> render_body <> """
                        </Layouts.app>
                    """ <> close
                    end,
                    global: false
                  )

                new_content = ensure_admin_nav_card_fn(new_content)

                Rewrite.Source.update(source, :content, new_content)
              end
            end)

          {:error, igniter} ->
            Igniter.add_warning(
              igniter,
              "Could not find #{inspect(admin_live_module)} to patch. Admin cards not added."
            )
        end
      else
        Igniter.Project.Module.create_module(igniter, admin_live_module, full_contents)
      end
    end

    defp ensure_admin_nav_card_fn(content) do
      if String.contains?(content, "defp admin_nav_card") do
        content
      else
        nav_card_fn = """

      attr :navigate, :string, required: true
      attr :icon, :string, required: true
      attr :title, :string, required: true
      attr :description, :string, required: true

      defp admin_nav_card(assigns) do
        ~H\"\"\"
        <.link
          navigate={@navigate}
          class="bt-card bt-card--elevated bt-card--half"
          style="text-decoration: none; color: inherit; transition: box-shadow var(--bt-duration-base) var(--bt-ease);"
        >
          <h3 class="bt-section__title">
            <.icon name={@icon} class="size-5" /> {@title}
          </h3>
          <p class="bt-section__description" style="margin-bottom: 0;">{@description}</p>
        </.link>
        \"\"\"
      end
    """

        append_before_module_end(content, nav_card_fn)
      end
    end

    defp create_jobs_live(
           igniter,
           jobs_live_module,
           web_module,
           live_user_auth_module,
           jobs_module
         ) do
      {exists?, igniter} = Igniter.Project.Module.module_exists(igniter, jobs_live_module)

      if exists? do
        igniter
      else
        contents =
          PxImports.AdminTemplates.jobs_live_module(
            web_module,
            live_user_auth_module,
            jobs_module
          )

        Igniter.Project.Module.create_module(igniter, jobs_live_module, contents)
      end
    end

    defp create_job_show_live(
           igniter,
           job_show_live_module,
           web_module,
           live_user_auth_module,
           jobs_module
         ) do
      {exists?, igniter} = Igniter.Project.Module.module_exists(igniter, job_show_live_module)

      if exists? do
        igniter
      else
        contents =
          PxImports.AdminTemplates.job_show_live_module(
            web_module,
            live_user_auth_module,
            jobs_module
          )

        Igniter.Project.Module.create_module(igniter, job_show_live_module, contents)
      end
    end

    defp create_users_live(
           igniter,
           users_live_module,
           web_module,
           live_user_auth_module,
           accounts_module,
           user_module
         ) do
      {exists?, igniter} = Igniter.Project.Module.module_exists(igniter, users_live_module)

      if exists? do
        igniter
      else
        contents =
          PxImports.AdminTemplates.users_live_module(
            web_module,
            live_user_auth_module,
            accounts_module,
            user_module
          )

        Igniter.Project.Module.create_module(igniter, users_live_module, contents)
      end
    end

    defp patch_users_live(igniter, users_live_module) do
      case Igniter.Project.Module.find_module(igniter, users_live_module) do
        {:ok, {igniter, source, _zipper}} ->
          path = Rewrite.Source.get(source, :path)

          Igniter.update_file(igniter, path, fn source ->
            content = Rewrite.Source.get(source, :content)

            content =
              String.replace(
                content,
                ~S'<.link navigate={~p"/users/#{user.id}"} class="font-medium link link-hover">
                        {user.email}
                      </.link>',
                ~S'<span class="font-medium">{user.email}</span>'
              )

            Rewrite.Source.update(source, :content, content)
          end)

        {:error, igniter} ->
          igniter
      end
    end

    defp create_impersonation_controller(igniter, module, web_module, prefix) do
      {exists?, igniter} = Igniter.Project.Module.module_exists(igniter, module)

      if exists? do
        igniter
      else
        user_module = Module.concat([prefix, Accounts, User])
        accounts_module = Module.concat(prefix, Accounts)

        contents = """
        @moduledoc \"\"\"
        Controller for admin impersonation. Admins can start impersonating another
        user for the duration of their session and stop at any time.
        \"\"\"

        use #{inspect(web_module)}, :controller

        alias #{inspect(user_module)}, as: User
        alias #{inspect(accounts_module)}, as: Accounts

        def start(conn, %{"user_id" => user_id}) do
          with %User{is_admin: true} = admin <- conn.assigns[:current_user],
               %User{} = target <- safe_get_user(user_id) do
            conn
            |> store_user_in_session(target)
            |> put_session(:impersonator_id, admin.id)
            |> put_flash(:info, "Now impersonating \#{target.email}")
            |> redirect(to: ~p"/")
          else
            _ ->
              conn
              |> put_flash(:error, "Unable to impersonate that user")
              |> redirect(to: ~p"/admin")
          end
        end

        def stop(conn, params) do
          return_to = safe_return_to(params["return_to"])

          case get_session(conn, :impersonator_id) do
            nil ->
              conn
              |> put_flash(:info, "You are not currently impersonating anyone")
              |> redirect(to: return_to || ~p"/")

            admin_id ->
              case safe_get_user(admin_id) do
                %User{} = admin ->
                  conn
                  |> delete_session(:impersonator_id)
                  |> store_user_in_session(admin)
                  |> put_flash(:info, "Stopped impersonating")
                  |> redirect(to: return_to || ~p"/admin")

                _ ->
                  conn
                  |> delete_session(:impersonator_id)
                  |> redirect(to: ~p"/sign-in")
              end
          end
        end

        defp safe_return_to(path) when is_binary(path) do
          cond do
            String.starts_with?(path, "/admin/impersonation") -> nil
            String.match?(path, ~r{\\A/[^/\\\\]}) -> path
            path == "/" -> path
            true -> nil
          end
        end

        defp safe_return_to(_), do: nil

        defp store_user_in_session(conn, user) do
          {:ok, token, _claims} =
            AshAuthentication.Jwt.token_for_user(user, %{"purpose" => "user"})

          user_with_token = put_in(user.__metadata__[:token], token)

          AshAuthentication.Plug.Helpers.store_in_session(conn, user_with_token)
        end

        defp safe_get_user(id) do
          Ash.get(User, id, domain: Accounts, authorize?: false)
          |> case do
            {:ok, user} -> user
            _ -> nil
          end
        end
        """

        Igniter.Project.Module.create_module(igniter, module, contents)
      end
    end

    defp patch_live_user_auth_for_impersonation(igniter, live_user_auth_module, prefix) do
      case Igniter.Project.Module.find_module(igniter, live_user_auth_module) do
        {:ok, {igniter, source, _zipper}} ->
          path = Rewrite.Source.get(source, :path)
          accounts_module = Module.concat(prefix, Accounts)
          user_module = Module.concat([prefix, Accounts, User])

          Igniter.update_file(igniter, path, fn source ->
            content = Rewrite.Source.get(source, :content)

            content =
              content
              |> ensure_current_user_mount_impersonation()
              |> ensure_live_user_auth_helpers(accounts_module, user_module)

            Rewrite.Source.update(source, :content, content)
          end)

        {:error, igniter} ->
          Igniter.add_warning(
            igniter,
            "Could not find #{inspect(live_user_auth_module)}. Impersonation mount wiring skipped."
          )
      end
    end

    defp ensure_current_user_mount_impersonation(content) do
      has_path? = String.contains?(content, "attach_path_hook()")
      has_impersonator? = String.contains?(content, "attach_impersonator(session)")

      if has_path? and has_impersonator? do
        content
      else
        append_lines =
          []
          |> then(fn acc ->
            if has_path?, do: acc, else: acc ++ ["      |> attach_path_hook()"]
          end)
          |> then(fn acc ->
            if has_impersonator?,
              do: acc,
              else: acc ++ ["      |> attach_impersonator(session)"]
          end)

        append_pipeline =
          case append_lines do
            [] -> ""
            lines -> "\n" <> Enum.join(lines, "\n")
          end

        updated =
          Regex.replace(
            ~r/(\|>\s*AshAuthentication\.Phoenix\.LiveSession\.assign_new_resources\(session\))/,
            content,
            &(&1 <> append_pipeline),
            global: false
          )

        updated
        |> then(fn updated ->
          if updated != content do
            updated
          else
            String.replace(
              updated,
              "{:cont, AshAuthentication.Phoenix.LiveSession.assign_new_resources(socket, session)}",
              """
                  {:cont,
                   socket
                   |> AshAuthentication.Phoenix.LiveSession.assign_new_resources(session)#{append_pipeline}}
              """,
              global: false
            )
          end
        end)
      end
    end

    defp ensure_live_user_auth_helpers(content, accounts_module, user_module) do
      content
      |> then(fn c ->
        if String.contains?(c, "defp attach_path_hook(socket)") do
          c
        else
          append_before_module_end(
            c,
            """

              defp attach_path_hook(socket) do
                Phoenix.LiveView.attach_hook(
                  socket,
                  :active_path,
                  :handle_params,
                  fn _params, url, socket ->
                    path =
                      case URI.parse(url) do
                        %URI{path: nil} -> "/"
                        %URI{path: path} -> path
                      end

                    {:cont, Phoenix.Component.assign(socket, :current_path, path)}
                  end
                )
              rescue
                _ -> socket
              end
            """
          )
        end
      end)
      |> then(fn c ->
        if String.contains?(c, "defp attach_impersonator(socket, session)") do
          c
        else
          append_before_module_end(
            c,
            """

              defp attach_impersonator(socket, session) do
                case session["impersonator_id"] do
                  nil ->
                    Phoenix.Component.assign_new(socket, :impersonator, fn -> nil end)

                  id ->
                    impersonator =
                      try do
                        Ash.get!(#{inspect(user_module)}, id,
                          domain: #{inspect(accounts_module)},
                          authorize?: false
                        )
                      rescue
                        _ -> nil
                      end

                    Phoenix.Component.assign(socket, :impersonator, impersonator)
                end
              end
            """
          )
        end
      end)
    end

    defp patch_layouts_for_impersonation(igniter, layouts_module) do
      case Igniter.Project.Module.find_module(igniter, layouts_module) do
        {:ok, {igniter, source, _zipper}} ->
          path = Rewrite.Source.get(source, :path)

          Igniter.update_file(igniter, path, fn source ->
            content = Rewrite.Source.get(source, :content)

            content =
              content
              |> ensure_layout_attrs_for_impersonation()
              |> ensure_layout_impersonation_banner_render()
              |> ensure_layout_impersonation_banner_fn()

            Rewrite.Source.update(source, :content, content)
          end)

        {:error, igniter} ->
          Igniter.add_warning(
            igniter,
            "Could not find #{inspect(layouts_module)}. Impersonation banner wiring skipped."
          )
      end
    end

    defp ensure_layout_attrs_for_impersonation(content) do
      content
      |> then(fn c ->
        if String.contains?(c, "attr :current_path, :string") do
          c
        else
          c
          |> String.replace(
            ~S'attr :current_user, :map, default: nil, doc: "the current authenticated user"',
            ~S'attr :current_user, :map, default: nil, doc: "the current authenticated user"' <>
              "\n" <>
              ~S'  attr :current_path, :string, default: "/", doc: "the active URL path for nav highlighting"',
            global: false
          )
          |> then(fn maybe_changed ->
            if maybe_changed != c do
              maybe_changed
            else
              String.replace(
                c,
                ~S'attr :flash, :map, required: true, doc: "the map of flash messages"',
                ~S'attr :flash, :map, required: true, doc: "the map of flash messages"' <>
                  "\n" <>
                  ~S'  attr :current_path, :string, default: "/", doc: "the active URL path for nav highlighting"',
                global: false
              )
            end
          end)
        end
      end)
      |> then(fn c ->
        if String.contains?(c, "attr :impersonator, :map") do
          c
        else
          c
          |> String.replace(
            ~S'attr :current_path, :string, default: "/", doc: "the active URL path for nav highlighting"',
            ~S'attr :current_path, :string, default: "/", doc: "the active URL path for nav highlighting"' <>
              "\n" <>
              ~S'  attr :impersonator, :map, default: nil, doc: "admin user currently impersonating, if any"',
            global: false
          )
          |> then(fn maybe_changed ->
            if maybe_changed != c do
              maybe_changed
            else
              String.replace(
                c,
                ~S'attr :current_user, :map, default: nil, doc: "the current authenticated user"',
                ~S'attr :current_user, :map, default: nil, doc: "the current authenticated user"' <>
                  "\n" <>
                  ~S'  attr :impersonator, :map, default: nil, doc: "admin user currently impersonating, if any"',
                global: false
              )
            end
          end)
        end
      end)
    end

    defp ensure_layout_impersonation_banner_render(content) do
      content =
        String.replace(
          content,
          """
          <.impersonation_banner
            :if={@impersonator}
            impersonator={@impersonator}
            current_user={@current_user}
            current_path={@current_path}
          />

          """,
          """
              <.impersonation_banner
                :if={@impersonator}
                impersonator={@impersonator}
                current_user={@current_user}
                current_path={@current_path}
              />

          """
        )

      if String.contains?(content, "<.impersonation_banner") do
        content
      else
        banner_render =
          [
            "    <.impersonation_banner",
            "      :if={@impersonator}",
            "      impersonator={@impersonator}",
            "      current_user={@current_user}",
            "      current_path={@current_path}",
            "    />",
            ""
          ]
          |> Enum.join("\n")

        Regex.replace(
          ~r/(def app\(assigns\) do\s*\n\s*~H"""\n)/,
          content,
          fn _, opener ->
            opener <> banner_render
          end,
          global: false
        )
      end
    end

    defp ensure_layout_impersonation_banner_fn(content) do
      if String.contains?(content, "defp impersonation_banner(assigns)") do
        content
      else
        banner_fn = PxImports.AdminTemplates.impersonation_banner_fn()

        if String.contains?(content, ~S'@doc """
  Shows the flash group with standard titles and content.') do
          String.replace(
            content,
            ~S'@doc """
  Shows the flash group with standard titles and content.',
            banner_fn <>
              ~S'@doc """
  Shows the flash group with standard titles and content.',
            global: false
          )
        else
          append_before_module_end(content, "\n" <> banner_fn)
        end
      end
    end

    defp patch_layouts_invocations_for_impersonation(igniter, modules) do
      Enum.reduce(modules, igniter, fn module, acc ->
        patch_module_layouts_invocation_for_impersonation(acc, module)
      end)
    end

    defp patch_module_layouts_invocation_for_impersonation(igniter, module) do
      case Igniter.Project.Module.find_module(igniter, module) do
        {:ok, {igniter, source, _zipper}} ->
          path = Rewrite.Source.get(source, :path)

          Igniter.update_file(igniter, path, fn source ->
            content = Rewrite.Source.get(source, :content)

            if not String.contains?(content, "<Layouts.app") or
                 String.contains?(content, "impersonator={assigns[:impersonator]}") do
              source
            else
              new_content = patch_layouts_app_opening(content)

              Rewrite.Source.update(source, :content, new_content)
            end
          end)

        {:error, igniter} ->
          igniter
      end
    end

    defp patch_layouts_app_opening(content) do
      Regex.replace(
        ~r/<Layouts\.app(?<attrs>[\s\S]*?)>/,
        content,
        fn _match, attrs ->
          additions =
            []
            |> then(fn lines ->
              if String.contains?(attrs, "current_path=") do
                lines
              else
                lines ++ ["\n            current_path={assigns[:current_path] || \"/\"}"]
              end
            end)
            |> then(fn lines ->
              if String.contains?(attrs, "impersonator=") do
                lines
              else
                lines ++ ["\n            impersonator={assigns[:impersonator]}"]
              end
            end)
            |> Enum.join("")

          "<Layouts.app" <> attrs <> additions <> ">"
        end,
        global: false
      )
    end

    defp append_before_module_end(content, code) do
      Regex.replace(~r/\nend\s*$/, content, code <> "\nend", global: false)
    end

    # ──────────────────────────────────────────────
    # Router: admin routes + oban dashboard
    # ──────────────────────────────────────────────

    defp update_router(igniter, router_module, live_user_auth_module, include_users?) do
      live_user_auth_str = inspect(live_user_auth_module)

      case Igniter.Project.Module.find_module(igniter, router_module) do
        {:ok, {igniter, source, _zipper}} ->
          path = Rewrite.Source.get(source, :path)

          Igniter.update_file(igniter, path, fn source ->
            content = Rewrite.Source.get(source, :content)

            content =
              content
              |> add_oban_web_import()
              |> add_admin_routes(live_user_auth_str)
              |> then(fn c ->
                if include_users?, do: add_users_admin_route(c, live_user_auth_str), else: c
              end)
              |> then(fn c -> if include_users?, do: add_impersonation_routes(c), else: c end)
              |> add_oban_dashboard()

            Rewrite.Source.update(source, :content, content)
          end)

        {:error, igniter} ->
          Igniter.add_warning(
            igniter,
            "Could not find router module #{inspect(router_module)}. Router modifications skipped."
          )
      end
    end

    defp add_oban_web_import(content) do
      if String.contains?(content, "Oban.Web.Router") do
        content
      else
        String.replace(
          content,
          "use AshAuthentication.Phoenix.Router",
          "use AshAuthentication.Phoenix.Router\n\n  import Oban.Web.Router",
          global: false
        )
      end
    end

    defp add_admin_routes(content, live_user_auth_str) do
      if String.contains?(content, ~s|live "/admin/jobs"|) do
        content
      else
        admin_session_block = """
            ash_authentication_live_session :admin_routes,
              on_mount: [{#{live_user_auth_str}, :current_user}] do
              live "/admin", AdminLive
              live "/admin/jobs", Admin.JobsLive
              live "/admin/jobs/:id", Admin.JobShowLive
            end
        """

        cond do
          String.contains?(content, ":admin_routes") ->
            # Inject job routes just before the closing `end` of the admin_routes session,
            # so they appear after any routes already declared in the block.
            Regex.replace(
              ~r/(ash_authentication_live_session\s+:admin_routes\b.*?)(^\s+end)/ms,
              content,
              fn _, block, ending ->
                block <>
                  "      live \"/admin/jobs\", Admin.JobsLive\n" <>
                  "      live \"/admin/jobs/:id\", Admin.JobShowLive\n" <>
                  ending
              end,
              global: false
            )

          String.contains?(content, ":authenticated_routes") ->
            Regex.replace(
              ~r/(ash_authentication_live_session\s+:authenticated_routes\b.*?end\n)/s,
              content,
              fn _, block -> block <> "\n" <> admin_session_block end,
              global: false
            )

          true ->
            content <> "\n" <> admin_session_block
        end
      end
    end

    defp add_users_admin_route(content, live_user_auth_str) do
      if String.contains?(content, ~s|live "/admin/users"|) do
        content
      else
        admin_session_block = """
            ash_authentication_live_session :admin_routes,
              on_mount: [{#{live_user_auth_str}, :current_user}] do
              live "/admin", AdminLive
              live "/admin/users", Admin.UsersLive
            end
        """

        cond do
          String.contains?(content, ":admin_routes") ->
            Regex.replace(
              ~r/(ash_authentication_live_session\s+:admin_routes\b.*?)(^\s+end)/ms,
              content,
              fn _, block, ending ->
                block <> "      live \"/admin/users\", Admin.UsersLive\n" <> ending
              end,
              global: false
            )

          String.contains?(content, ":authenticated_routes") ->
            Regex.replace(
              ~r/(ash_authentication_live_session\s+:authenticated_routes\b.*?end\n)/s,
              content,
              fn _, block -> block <> "\n" <> admin_session_block end,
              global: false
            )

          true ->
            content <> "\n" <> admin_session_block
        end
      end
    end

    defp add_impersonation_routes(content) do
      content
      |> add_route_after_sign_out(
        ~s|post "/admin/impersonation/start/:user_id", ImpersonationController, :start|
      )
      |> add_route_after_sign_out(
        ~s|get "/admin/impersonation/stop", ImpersonationController, :stop|
      )
    end

    defp add_route_after_sign_out(content, route_line) do
      if String.contains?(content, route_line) do
        content
      else
        Regex.replace(
          ~r/(^\s*sign_out_route AuthController[^\n]*\n)/m,
          content,
          fn match -> match <> "    " <> route_line <> "\n" end,
          global: false
        )
      end
    end

    defp add_oban_dashboard(content) do
      if String.contains?(content, "oban_dashboard") do
        content
      else
        oban_scope = """
              scope "/" do
                pipe_through :browser

                oban_dashboard("/oban")
              end
        """

        cond do
          String.contains?(content, "import Phoenix.LiveDashboard.Router") ->
            String.replace(
              content,
              "    import Phoenix.LiveDashboard.Router",
              oban_scope <> "\n    import Phoenix.LiveDashboard.Router",
              global: false
            )

          Regex.match?(~r/compile_env.*:dev_routes\) do/, content) ->
            Regex.replace(
              ~r/(compile_env\([^)]+, :dev_routes\) do)\s*\n/,
              content,
              "\\1\n" <> oban_scope <> "\n",
              global: false
            )

          true ->
            content
        end
      end
    end

    # ──────────────────────────────────────────────
    # Org tree: Projects domain + 5 resources + worker
    # ──────────────────────────────────────────────

    defp create_projects_domain(igniter, domain_module, resource_modules, otp_app) do
      {exists?, igniter} = Igniter.Project.Module.module_exists(igniter, domain_module)

      if exists? do
        igniter
      else
        resources_str =
          resource_modules
          |> Enum.map(fn mod -> "    resource #{inspect(mod)}" end)
          |> Enum.join("\n")

        contents = """
        use Ash.Domain, otp_app: #{inspect(otp_app)}

        resources do
        #{resources_str}
        end
        """

        Igniter.Project.Module.create_module(igniter, domain_module, contents)
      end
    end

    # Patches an existing domain module to include a resource declaration
    # if it isn't already present. Safe to call whether the domain was just
    # created in this run or existed from a previous install.
    defp ensure_resource_in_domain(igniter, domain_module, resource_module) do
      resource_str = inspect(resource_module)

      Igniter.Project.Module.find_and_update_module!(igniter, domain_module, fn zipper ->
        source = Sourceror.Zipper.root(zipper) |> Sourceror.to_string()

        if String.contains?(source, resource_str) do
          {:ok, zipper}
        else
          resource_line = "    resource #{resource_str}"

          new_source =
            Regex.replace(
              ~r/(resources\s+do\n)(.*?)(^\s*end)/ms,
              source,
              fn _, opener, existing, closer ->
                opener <> existing <> resource_line <> "\n" <> closer
              end,
              global: false
            )

          {:ok, Sourceror.parse_string!(new_source) |> Sourceror.Zipper.zip()}
        end
      end)
    end

    defp create_business_unit(igniter, module, domain_module, repo_module) do
      {exists?, igniter} = Igniter.Project.Module.module_exists(igniter, module)

      if exists? do
        igniter
      else
        contents = """
        use Ash.Resource,
          domain: #{inspect(domain_module)},
          data_layer: AshPostgres.DataLayer,
          authorizers: [Ash.Policy.Authorizer]

        postgres do
          table "business_units"
          repo #{inspect(repo_module)}
        end

        actions do
          defaults [:read]

          create :create do
            primary? true
            accept [:id, :name, :description, :bu_leader_sap_id, :created_at, :hidden_at]
          end

          update :sync_from_px do
            accept [:name, :description, :bu_leader_sap_id, :created_at, :hidden_at]
          end
        end

        policies do
          bypass always() do
            authorize_if always()
          end
        end

        attributes do
          attribute :id, :integer do
            primary_key? true
            allow_nil? false
            public? true
          end

          attribute :name, :string do
            allow_nil? false
            public? true
          end

          attribute :description, :string do
            public? true
          end

          attribute :bu_leader_sap_id, :integer do
            public? true
          end

          attribute :created_at, :utc_datetime do
            public? true
          end

          attribute :hidden_at, :utc_datetime do
            public? true
          end
        end
        """

        Igniter.Project.Module.create_module(igniter, module, contents)
      end
    end

    defp create_cluster(igniter, module, domain_module, repo_module) do
      {exists?, igniter} = Igniter.Project.Module.module_exists(igniter, module)

      if exists? do
        igniter
      else
        bu_module = Module.concat(domain_module, BusinessUnit)

        contents = """
        use Ash.Resource,
          domain: #{inspect(domain_module)},
          data_layer: AshPostgres.DataLayer,
          authorizers: [Ash.Policy.Authorizer]

        postgres do
          table "clusters"
          repo #{inspect(repo_module)}
        end

        actions do
          defaults [:read]

          create :create do
            primary? true
            accept [:id, :name, :description, :business_unit_id, :cluster_leader_sap_id, :created_at, :hidden_at]
          end

          update :sync_from_px do
            accept [:name, :description, :business_unit_id, :cluster_leader_sap_id, :created_at, :hidden_at]
          end
        end

        policies do
          bypass always() do
            authorize_if always()
          end
        end

        attributes do
          attribute :id, :integer do
            primary_key? true
            allow_nil? false
            public? true
          end

          attribute :name, :string do
            allow_nil? false
            public? true
          end

          attribute :description, :string do
            public? true
          end

          attribute :business_unit_id, :integer do
            allow_nil? false
            public? true
          end

          attribute :cluster_leader_sap_id, :integer do
            public? true
          end

          attribute :created_at, :utc_datetime do
            public? true
          end

          attribute :hidden_at, :utc_datetime do
            public? true
          end
        end

        relationships do
          belongs_to :business_unit, #{inspect(bu_module)} do
            source_attribute :business_unit_id
            destination_attribute :id
            define_attribute? false
          end
        end
        """

        Igniter.Project.Module.create_module(igniter, module, contents)
      end
    end

    defp create_client_group(igniter, module, domain_module, repo_module) do
      {exists?, igniter} = Igniter.Project.Module.module_exists(igniter, module)

      if exists? do
        igniter
      else
        cluster_module = Module.concat(domain_module, Cluster)

        contents = """
        use Ash.Resource,
          domain: #{inspect(domain_module)},
          data_layer: AshPostgres.DataLayer,
          authorizers: [Ash.Policy.Authorizer]

        postgres do
          table "client_groups"
          repo #{inspect(repo_module)}
        end

        actions do
          defaults [:read]

          create :create do
            primary? true
            accept [:id, :name, :description, :cluster_id, :sector_id, :account_manager_sap_id, :created_at, :hidden_at]
          end

          update :sync_from_px do
            accept [:name, :description, :cluster_id, :sector_id, :account_manager_sap_id, :created_at, :hidden_at]
          end
        end

        policies do
          bypass always() do
            authorize_if always()
          end
        end

        attributes do
          attribute :id, :integer do
            primary_key? true
            allow_nil? false
            public? true
          end

          attribute :name, :string do
            allow_nil? false
            public? true
          end

          attribute :description, :string do
            public? true
          end

          attribute :cluster_id, :integer do
            public? true
          end

          attribute :sector_id, :integer do
            public? true
          end

          attribute :account_manager_sap_id, :integer do
            public? true
          end

          attribute :created_at, :utc_datetime do
            public? true
          end

          attribute :hidden_at, :utc_datetime do
            public? true
          end
        end

        relationships do
          belongs_to :cluster, #{inspect(cluster_module)} do
            source_attribute :cluster_id
            destination_attribute :id
            define_attribute? false
          end
        end
        """

        Igniter.Project.Module.create_module(igniter, module, contents)
      end
    end

    defp create_client(igniter, module, domain_module, repo_module) do
      {exists?, igniter} = Igniter.Project.Module.module_exists(igniter, module)

      if exists? do
        igniter
      else
        client_group_module = Module.concat(domain_module, ClientGroup)

        contents = """
        use Ash.Resource,
          domain: #{inspect(domain_module)},
          data_layer: AshPostgres.DataLayer,
          authorizers: [Ash.Policy.Authorizer]

        postgres do
          table "clients"
          repo #{inspect(repo_module)}
        end

        actions do
          defaults [:read]

          create :create do
            primary? true
            accept [:id, :name, :description, :logo, :client_group_id, :account_manager_sap_id, :created_at, :updated_at, :hidden_at]
          end

          update :sync_from_px do
            accept [:name, :description, :logo, :client_group_id, :account_manager_sap_id, :created_at, :updated_at, :hidden_at]
          end
        end

        policies do
          bypass always() do
            authorize_if always()
          end
        end

        attributes do
          attribute :id, :integer do
            primary_key? true
            allow_nil? false
            public? true
          end

          attribute :name, :string do
            allow_nil? false
            public? true
          end

          attribute :description, :string do
            public? true
          end

          attribute :logo, :string do
            public? true
          end

          attribute :client_group_id, :integer do
            public? true
          end

          attribute :account_manager_sap_id, :integer do
            public? true
          end

          attribute :created_at, :utc_datetime do
            public? true
          end

          attribute :updated_at, :utc_datetime do
            public? true
          end

          attribute :hidden_at, :utc_datetime do
            public? true
          end
        end

        relationships do
          belongs_to :client_group, #{inspect(client_group_module)} do
            source_attribute :client_group_id
            destination_attribute :id
            define_attribute? false
          end
        end
        """

        Igniter.Project.Module.create_module(igniter, module, contents)
      end
    end

    defp create_sync_org_tree_worker(igniter, module, domain_module, prefix) do
      {exists?, igniter} = Igniter.Project.Module.module_exists(igniter, module)

      if exists? do
        igniter
      else
        repo_module = Module.concat(prefix, Repo)
        bu_module = Module.concat(domain_module, BusinessUnit)
        cluster_module = Module.concat(domain_module, Cluster)
        cg_module = Module.concat(domain_module, ClientGroup)
        client_module = Module.concat(domain_module, Client)
        sync_projects_worker_module = Module.concat([prefix, Workers, SyncProjectsWorker])

        contents = """
        @moduledoc \"\"\"
        Synchronizes PX organizational tree entities and projects in dependency order.
        \"\"\"

        use Oban.Worker, queue: :default, max_attempts: 3

        alias #{inspect(domain_module)}
        alias #{inspect(bu_module)}
        alias #{inspect(cluster_module)}
        alias #{inspect(cg_module)}
        alias #{inspect(client_module)}
        alias #{inspect(sync_projects_worker_module)}
        alias #{inspect(repo_module)}

        @impl Oban.Worker
        def perform(job) do
          case run_sync() do
            {:ok, summary} ->
              details = Map.put(summary, :completed_at, DateTime.utc_now() |> DateTime.to_iso8601())

              job
              |> Ecto.Changeset.change(%{meta: Map.merge(job.meta, details)})
              |> Repo.update!()

              :ok

            {:error, failed_stage, reason, summary} ->
              details =
                summary
                |> Map.put(:failed_stage, failed_stage)
                |> Map.put(:error, inspect(reason))
                |> Map.put(:completed_at, DateTime.utc_now() |> DateTime.to_iso8601())

              _ =
                job
                |> Ecto.Changeset.change(%{meta: Map.merge(job.meta, details)})
                |> Repo.update()

              {:error, {:stage_failed, failed_stage, reason}}
          end
        end

        @doc \"\"\"
        Executes a full org-tree sync for the provided payload.
        \"\"\"
        def execute(%{
              business_units: business_units,
              clusters: clusters,
              client_groups: client_groups,
              clients: clients,
              projects: projects
            }) do
          {:ok,
           %{}
           |> Map.put(:business_units, sync_business_units(business_units))
           |> Map.put(:clusters, sync_clusters(clusters))
           |> Map.put(:client_groups, sync_client_groups(client_groups))
           |> Map.put(:clients, sync_clients(clients))
           |> Map.put(:projects, sync_projects(projects))}
        end

        defp run_sync do
          with {:ok, business_units} <- BluetabConnect.Px.Rest.list_business_units(),
               {:ok, clusters} <- BluetabConnect.Px.Rest.list_clusters(),
               {:ok, client_groups} <- BluetabConnect.Px.Rest.list_client_groups(),
               {:ok, clients} <- BluetabConnect.Px.Rest.list_clients(),
               {:ok, projects} <- fetch_all_projects(),
               {:ok, summary} <-
                 execute(%{
                   business_units: business_units,
                   clusters: clusters,
                   client_groups: client_groups,
                   clients: clients,
                   projects: projects
                 }) do
            {:ok, summary}
          else
            {:error, reason} -> {:error, :fetch, reason, %{}}
            {:error, stage, reason, summary} -> {:error, stage, reason, summary}
          end
        end

        defp sync_business_units(items) do
          sync_resource(:business_units, BusinessUnit, items, :id, &map_business_unit/1)
        end

        defp sync_clusters(items) do
          sync_resource(:clusters, Cluster, items, :id, &map_cluster/1)
        end

        defp sync_client_groups(items) do
          sync_resource(:client_groups, ClientGroup, items, :id, &map_client_group/1)
        end

        defp sync_clients(items) do
          sync_resource(:clients, Client, items, :id, &map_client/1)
        end

        defp sync_projects(items) do
          SyncProjectsWorker.execute(items)
        end

        defp sync_resource(_stage_name, resource, items, key_field, mapper) do
          existing_items = Ash.read!(resource, domain: Projects, authorize?: false)
          existing_by_key = Map.new(existing_items, &{Map.get(&1, key_field), &1})

          result =
            Enum.reduce(
              items,
              %{created: [], updated: [], skipped: [], hidden: [], failed: []},
              fn raw_item, acc ->
                attrs = mapper.(raw_item)
                key = Map.get(attrs, key_field)
                name = Map.get(attrs, :name)

                case Map.get(existing_by_key, key) do
                  nil ->
                    case Ash.create(resource, attrs,
                           action: :create,
                           domain: Projects,
                           authorize?: false
                         ) do
                      {:ok, _created} ->
                        %{acc | created: [%{key_field => key, name: name} | acc.created]}

                      {:error, error} ->
                        %{
                          acc
                          | failed: [
                              %{key_field => key, name: name, error: inspect(error)}
                              | acc.failed
                            ]
                        }
                    end

                  existing ->
                    changes = build_changes(existing, attrs, key_field)

                    if map_size(changes) == 0 do
                      %{acc | skipped: [%{key_field => key, name: name} | acc.skipped]}
                    else
                      case existing
                           |> Ash.Changeset.for_update(:sync_from_px, changes)
                           |> Ash.update(authorize?: false) do
                        {:ok, _updated} ->
                          %{
                            acc
                            | updated: [
                                %{key_field => key, name: name, changes: presentable_changes(changes)}
                                | acc.updated
                              ]
                          }

                        {:error, error} ->
                          %{
                            acc
                            | failed: [
                                %{key_field => key, name: name, error: inspect(error)}
                                | acc.failed
                              ]
                          }
                      end
                    end
                end
              end
            )

          incoming_keys =
            items
            |> Enum.map(&mapper.(&1))
            |> Enum.map(&Map.get(&1, key_field))
            |> MapSet.new()

          hidden_result = soft_hide_missing(existing_items, incoming_keys, key_field, result)

          %{
            total: length(items),
            created_count: length(hidden_result.created),
            updated_count: length(hidden_result.updated),
            skipped_count: length(hidden_result.skipped),
            hidden_count: length(hidden_result.hidden),
            failed_count: length(hidden_result.failed),
            created: Enum.reverse(hidden_result.created),
            updated: Enum.reverse(hidden_result.updated),
            skipped: Enum.reverse(hidden_result.skipped),
            hidden: Enum.reverse(hidden_result.hidden),
            failed: Enum.reverse(hidden_result.failed)
          }
        end

        defp soft_hide_missing(existing_items, incoming_keys, key_field, result) do
          Enum.reduce(existing_items, result, fn item, acc ->
            key = Map.get(item, key_field)
            name = Map.get(item, :name)

            cond do
              MapSet.member?(incoming_keys, key) ->
                acc

              not is_nil(item.hidden_at) ->
                acc

              true ->
                case item
                     |> Ash.Changeset.for_update(:sync_from_px, %{
                       hidden_at: DateTime.utc_now()
                     })
                     |> Ash.update(authorize?: false) do
                  {:ok, _hidden} ->
                    %{acc | hidden: [%{key_field => key, name: name} | acc.hidden]}

                  {:error, error} ->
                    %{acc | failed: [%{key_field => key, name: name, error: inspect(error)} | acc.failed]}
                end
            end
          end)
        end

        defp build_changes(existing, attrs, key_field) do
          attrs
          |> Map.put_new(:hidden_at, nil)
          |> Map.drop([key_field])
          |> Enum.reduce(%{}, fn {key, value}, changes ->
            if Map.get(existing, key) != value do
              Map.put(changes, key, value)
            else
              changes
            end
          end)
        end

        defp map_business_unit(raw) do
          %{
            id: parse_integer(raw["id"]),
            name: normalize_string(raw["name"]),
            description: normalize_string(raw["description"]),
            bu_leader_sap_id: parse_integer(raw["bu_leader_sap_id"]),
            created_at: parse_datetime(raw["created_at"])
          }
          |> drop_nil_values()
        end

        defp map_cluster(raw) do
          %{
            id: parse_integer(raw["id"]),
            name: normalize_string(raw["name"]),
            description: normalize_string(raw["description"]),
            business_unit_id: parse_integer(raw["business_unit_id"]),
            cluster_leader_sap_id: parse_integer(raw["cluster_leader_sap_id"]),
            created_at: parse_datetime(raw["created_at"])
          }
          |> drop_nil_values()
        end

        defp map_client_group(raw) do
          %{
            id: parse_integer(raw["id"]),
            name: normalize_string(raw["name"]),
            description: normalize_string(raw["description"]),
            cluster_id: parse_integer(raw["cluster_id"]),
            sector_id: parse_integer(raw["sector_id"]),
            account_manager_sap_id: parse_integer(raw["account_manager_sap_id"]),
            created_at: parse_datetime(raw["created_at"])
          }
          |> drop_nil_values()
        end

        defp map_client(raw) do
          %{
            id: parse_integer(raw["id"]),
            name: normalize_string(raw["name"]),
            description: normalize_string(raw["description"]),
            logo: normalize_string(raw["logo"]),
            client_group_id: parse_integer(raw["client_group_id"]),
            account_manager_sap_id: parse_integer(raw["account_manager_sap_id"]),
            created_at: parse_datetime(raw["created_at"]),
            updated_at: parse_datetime(raw["updated_at"])
          }
          |> drop_nil_values()
        end

        defp drop_nil_values(map) do
          map
          |> Enum.reject(fn {_key, value} -> is_nil(value) end)
          |> Map.new()
        end

        defp presentable_changes(changes) do
          Enum.map(changes, fn {field, value} ->
            %{field: to_string(field), new_value: to_string(value)}
          end)
        end

        defp parse_integer(nil), do: nil
        defp parse_integer(value) when is_integer(value), do: value

        defp parse_integer(value) when is_binary(value) do
          case Integer.parse(value) do
            {number, ""} -> number
            _ -> nil
          end
        end

        defp parse_integer(_), do: nil

        defp normalize_string(nil), do: nil

        defp normalize_string(value) when is_binary(value) do
          case String.trim(value) do
            "" -> nil
            trimmed -> trimmed
          end
        end

        defp normalize_string(value), do: to_string(value)

        defp parse_datetime(nil), do: nil
        defp parse_datetime(%DateTime{} = datetime), do: datetime

        defp parse_datetime(value) when is_binary(value) do
          case DateTime.from_iso8601(value) do
            {:ok, datetime, _offset} ->
              datetime

            _ ->
              case NaiveDateTime.from_iso8601(value) do
                {:ok, naive_datetime} -> DateTime.from_naive!(naive_datetime, "Etc/UTC")
                _ -> nil
              end
          end
        end

        defp parse_datetime(_), do: nil

        defp fetch_all_projects(page \\\\ 1, acc \\\\ []) do
          case BluetabConnect.Px.Rest.list_projects(
                 page: page,
                 per_page: 100,
                 fields: "client_id,owner,is_time_off,cluster_id"
               ) do
            {:ok, %{"projects" => [], "pagination" => _pagination}} ->
              {:ok, acc}

            {:ok, %{"projects" => projects, "pagination" => _pagination}} ->
              fetch_all_projects(page + 1, acc ++ projects)

            error ->
              error
          end
        end
        """

        Igniter.Project.Module.create_module(igniter, module, contents)
      end
    end

    # ──────────────────────────────────────────────
    # Users: patch Accounts.User + SyncEmployeesWorker
    # ──────────────────────────────────────────────

    defp patch_user_resource(igniter, user_module) do
      igniter
      |> Ash.Resource.Igniter.add_new_attribute(
        user_module,
        :sap_id,
        "attribute :sap_id, :integer"
      )
      |> Ash.Resource.Igniter.add_new_attribute(
        user_module,
        :join_date,
        "attribute :join_date, :date"
      )
      |> Ash.Resource.Igniter.add_new_attribute(
        user_module,
        :hidden_at,
        "attribute :hidden_at, :utc_datetime"
      )
      |> Ash.Resource.Igniter.add_new_attribute(
        user_module,
        :category,
        "attribute :category, :string"
      )
      |> Ash.Resource.Igniter.add_new_attribute(
        user_module,
        :category_name,
        "attribute :category_name, :string"
      )
      |> Ash.Resource.Igniter.add_new_attribute(
        user_module,
        :hub,
        "attribute :hub, :string"
      )
      |> Ash.Resource.Igniter.add_new_action(
        user_module,
        :provision_from_employee_sync,
        """
        create :provision_from_employee_sync do
          description \"Create a user from PX employee data when they have not signed in yet\"

          accept [
            :email,
            :given_name,
            :family_name,
            :join_date,
            :hidden_at,
            :sap_id,
            :category,
            :category_name,
            :hub
          ]

          change set_attribute(:confirmed_at, &DateTime.utc_now/0)
        end
        """
      )
      |> Ash.Resource.Igniter.add_new_action(
        user_module,
        :sync_employee_fields,
        """
        update :sync_employee_fields do
          accept [
            :join_date,
            :hidden_at,
            :sap_id,
            :category,
            :category_name,
            :hub
          ]
        end
        """
      )
      |> Ash.Resource.Igniter.add_new_action(
        user_module,
        :list_for_admin,
        """
        read :list_for_admin do
          description "Paginated directory for the admin users screen"

          pagination offset?: true,
                     default_limit: 25,
                     max_page_size: 100,
                     required?: true,
                     countable: true
        end
        """
      )
      |> Ash.Resource.Igniter.add_new_action(
        user_module,
        :set_admin,
        """
        update :set_admin do
          accept [:is_admin]
        end
        """
      )
    end

    defp create_sync_employees_worker(igniter, module, prefix, user_module) do
      {exists?, igniter} = Igniter.Project.Module.module_exists(igniter, module)

      if exists? do
        igniter
      else
        repo_module = Module.concat(prefix, Repo)
        accounts_module = Module.concat(prefix, Accounts)

        contents = """
        @moduledoc \"\"\"
        Synchronizes PX employee data into Accounts.User records.

        Matches employees to existing users by email address. Updates employee
        fields on existing users (sap_id, join_date, hidden_at from termination_date,
        `category`, `category_name`, and `hub` from PX). Creates new users when no row exists
        for the employee email yet.

        Reporting structure is synced via `SyncPositionsWorker`, not from employee records.
        \"\"\"

        use Oban.Worker, queue: :default, max_attempts: 3

        require Ash.Query
        require Ash.Expr

        alias #{inspect(accounts_module)}
        alias #{inspect(user_module)}, as: User
        alias #{inspect(repo_module)}

        @impl Oban.Worker
        def perform(job) do
          with {:ok, %{"employees" => employees}} <- BluetabConnect.Px.Rest.list_employees() do
            result = execute(employees)
            details = Map.put(result, :completed_at, DateTime.utc_now() |> DateTime.to_iso8601())

            job
            |> Ecto.Changeset.change(%{meta: Map.merge(job.meta, details)})
            |> Repo.update()

            :ok
          end
        end

        @doc \"\"\"
        Syncs a list of employee maps into the users table.
        \"\"\"
        def execute(employees) do
          sync_employees(employees)
        end

        @doc false
        def sync_employees(employees) do
          emails =
            employees
            |> Enum.map(&normalize_email(&1["email"]))
            |> Enum.reject(&is_nil/1)
            |> Enum.uniq()

          users_by_email =
            if emails == [] do
              %{}
            else
              User
              |> Ash.Query.filter(Ash.Expr.expr(email in ^emails))
              |> Ash.read!(domain: Accounts, authorize?: false)
              |> Map.new(&{&1.email, &1})
            end

          init = %{updated: [], skipped: [], created: [], failed: [], not_found: []}

          {_, results} =
            Enum.reduce(employees, {users_by_email, init}, fn employee, {by_email, acc} ->
              email = normalize_email(employee["email"])

              cond do
                is_nil(email) ->
                  {by_email, %{acc | skipped: [skipped_label(employee, :no_email) | acc.skipped]}}

                true ->
                  case Map.get(by_email, email) do
                    nil ->
                      case create_user_from_employee(employee) do
                        {:ok, user} ->
                          name = user_display_name(user)

                          entry = %{
                            "email" => user.email,
                            "name" => name,
                            "sap_id" => user.sap_id
                          }

                          {Map.put(by_email, user.email, user), %{acc | created: [entry | acc.created]}}

                        {:error, reason} ->
                          err = %{
                            "email" => email,
                            "sap_id" => parse_integer_field(employee["sap_employee_number"]),
                            "error" => format_ash_error(reason)
                          }

                          {by_email, %{acc | failed: [err | acc.failed]}}
                      end

                    user ->
                      case maybe_update_user(user, employee) do
                        {:updated, changes} ->
                          {by_email,
                           %{acc | updated: [%{email: user.email, changes: changes} | acc.updated]}}

                        :no_changes ->
                          {by_email, %{acc | skipped: [user.email | acc.skipped]}}
                      end
                  end
              end
            end)

          %{
            total_employees: length(employees),
            created_count: length(results.created),
            updated_count: length(results.updated),
            skipped_count: length(results.skipped),
            failed_count: length(results.failed),
            not_found_count: length(results.not_found),
            created: Enum.reverse(results.created),
            updated: Enum.reverse(results.updated),
            skipped: Enum.reverse(results.skipped),
            failed: Enum.reverse(results.failed),
            not_found: Enum.reverse(results.not_found)
          }
        end

        defp normalize_email(nil), do: nil

        defp normalize_email(email) when is_binary(email) do
          case String.trim(email) do
            "" -> nil
            e -> e
          end
        end

        defp normalize_email(_), do: nil

        defp skipped_label(employee, :no_email) do
          sap = parse_integer_field(employee["sap_employee_number"])

          case sap do
            nil -> "Missing email"
            n -> "Missing email (SAP: " <> Integer.to_string(n) <> ")"
          end
        end

        defp user_display_name(%User{} = user) do
          [user.given_name, user.family_name]
          |> Enum.reject(&(&1 in [nil, ""]))
          |> Enum.join(" ")
        end

        defp format_ash_error(%Ash.Changeset{} = cs), do: inspect(cs.errors)
        defp format_ash_error(other), do: inspect(other)

        defp create_user_from_employee(employee) do
          attrs = build_provision_attrs(employee)

          case attrs[:email] do
            nil ->
              {:error, :missing_email}

            _ ->
              User
              |> Ash.Changeset.for_create(:provision_from_employee_sync, attrs)
              |> Ash.create(domain: Accounts, authorize?: false)
          end
        end

        defp build_provision_attrs(employee) do
          {given, family} = employee_name_parts(employee)

          %{email: normalize_email(employee["email"]), given_name: given, family_name: family}
          |> put_if_present(:join_date, parse_start_date(employee["start_date"]))
          |> put_if_present(:hidden_at, parse_termination_date(employee["termination_date"]))
          |> put_if_present(:sap_id, parse_integer_field(employee["sap_employee_number"]))
          |> Map.put(:category, normalize_optional_string(employee["category"]))
          |> Map.put(:category_name, normalize_optional_string(employee["category_name"]))
          |> Map.put(:hub, normalize_optional_string(employee["hub"]))
        end

        defp put_if_present(attrs, _key, nil), do: attrs
        defp put_if_present(attrs, key, value), do: Map.put(attrs, key, value)

        defp employee_name_parts(emp) do
          given = normalize_optional_string(emp["given_name"] || emp["first_name"])
          family = normalize_optional_string(emp["family_name"] || emp["last_name"])

          if given || family do
            {given, family}
          else
            parse_full_name(emp["full_name"])
          end
        end

        defp normalize_optional_string(nil), do: nil

        defp normalize_optional_string(s) when is_binary(s) do
          case String.trim(s) do
            "" -> nil
            t -> t
          end
        end

        defp normalize_optional_string(_), do: nil

        defp parse_full_name(nil), do: {nil, nil}

        defp parse_full_name(name) when is_binary(name) do
          case String.trim(name) |> String.split(~r/\\s+/, trim: true) do
            [] -> {nil, nil}
            [one] -> {one, nil}
            [g | rest] -> {g, Enum.join(rest, " ")}
          end
        end

        defp parse_full_name(_), do: {nil, nil}

        defp parse_start_date(nil), do: nil

        defp parse_start_date(date_string) when is_binary(date_string) do
          parse_iso8601_date(date_string)
        end

        defp parse_start_date(_), do: nil

        defp maybe_update_user(user, employee) do
          attrs = build_update_attrs(user, employee)

          if map_size(attrs) > 0 do
            _updated =
              user
              |> Ash.Changeset.for_update(:sync_employee_fields, attrs)
              |> Ash.update!(authorize?: false)

            changes =
              Enum.map(attrs, fn {field, value} ->
                %{field: to_string(field), new_value: to_string(value)}
              end)

            {:updated, changes}
          else
            :no_changes
          end
        end

        defp build_update_attrs(user, employee) do
          %{}
          |> maybe_put_join_date(user, employee)
          |> maybe_put_hidden_at(user, employee)
          |> maybe_put_sap_id(user, employee)
          |> maybe_put_category(user, employee)
          |> maybe_put_category_name(user, employee)
          |> maybe_put_hub(user, employee)
        end

        defp maybe_put_join_date(attrs, user, employee) do
          case {user.join_date, parse_start_date(employee["start_date"])} do
            {nil, %Date{} = start_date} -> Map.put(attrs, :join_date, start_date)
            _ -> attrs
          end
        end

        defp maybe_put_hidden_at(attrs, user, employee) do
          desired_hidden_at = parse_termination_date(employee["termination_date"])

          if hidden_at_changed?(user.hidden_at, desired_hidden_at) do
            Map.put(attrs, :hidden_at, desired_hidden_at)
          else
            attrs
          end
        end

        defp maybe_put_sap_id(attrs, user, employee) do
          sap_id = parse_integer_field(employee["sap_employee_number"])

          cond do
            is_nil(sap_id) -> attrs
            user.sap_id != sap_id -> Map.put(attrs, :sap_id, sap_id)
            true -> attrs
          end
        end

        defp maybe_put_category(attrs, user, employee) do
          desired = normalize_optional_string(employee["category"])

          if normalize_optional_string(Map.get(user, :category)) != desired do
            Map.put(attrs, :category, desired)
          else
            attrs
          end
        end

        defp maybe_put_category_name(attrs, user, employee) do
          desired = normalize_optional_string(employee["category_name"])

          if normalize_optional_string(Map.get(user, :category_name)) != desired do
            Map.put(attrs, :category_name, desired)
          else
            attrs
          end
        end

        defp maybe_put_hub(attrs, user, employee) do
          desired = normalize_optional_string(employee["hub"])

          if normalize_optional_string(Map.get(user, :hub)) != desired do
            Map.put(attrs, :hub, desired)
          else
            attrs
          end
        end

        defp parse_termination_date(nil), do: nil

        defp parse_termination_date(date_string) when is_binary(date_string) do
          case parse_iso8601_date(date_string) do
            %Date{} = date -> DateTime.new!(date, ~T[00:00:00], "Etc/UTC")
            nil -> nil
          end
        end

        defp parse_termination_date(_), do: nil

        defp parse_iso8601_date(value) when is_binary(value) do
          trimmed = String.trim(value)

          if trimmed == "" do
            nil
          else
            case Date.from_iso8601(trimmed) do
              {:ok, date} ->
                date

              {:error, _} ->
                case DateTime.from_iso8601(trimmed) do
                  {:ok, datetime, _offset} ->
                    DateTime.to_date(datetime)

                  {:error, _} ->
                    case NaiveDateTime.from_iso8601(trimmed) do
                      {:ok, naive_datetime} -> NaiveDateTime.to_date(naive_datetime)
                      {:error, _} -> nil
                    end
                end
            end
          end
        end

        defp parse_iso8601_date(_), do: nil

        defp parse_integer_field(nil), do: nil
        defp parse_integer_field(value) when is_integer(value), do: value

        defp parse_integer_field(value) when is_binary(value) do
          case Integer.parse(value) do
            {number, ""} -> number
            _ -> nil
          end
        end

        defp parse_integer_field(_), do: nil

        defp hidden_at_changed?(nil, nil), do: false
        defp hidden_at_changed?(nil, %DateTime{}), do: true
        defp hidden_at_changed?(%DateTime{}, nil), do: true

        defp hidden_at_changed?(%DateTime{} = current, %DateTime{} = desired) do
          DateTime.compare(current, desired) != :eq
        end
        """

        Igniter.Project.Module.create_module(igniter, module, contents)
      end
    end

    # ──────────────────────────────────────────────
    # Spend types: SpendType resource + SyncSpendTypesWorker
    # ──────────────────────────────────────────────

    defp create_spend_type_resource(igniter, module, domain_module, repo_module) do
      {exists?, igniter} = Igniter.Project.Module.module_exists(igniter, module)

      if exists? do
        igniter
      else
        contents = """
        use Ash.Resource,
          domain: #{inspect(domain_module)},
          data_layer: AshPostgres.DataLayer,
          authorizers: [Ash.Policy.Authorizer]

        postgres do
          table "spend_types"
          repo #{inspect(repo_module)}
        end

        actions do
          defaults [:read]

          create :create do
            primary? true
            accept [:id, :name, :sap_id, :sap_name, :custom_fields, :hidden_at]
          end

          update :sync_from_px do
            accept [:name, :sap_id, :sap_name, :custom_fields, :hidden_at]
          end
        end

        policies do
          bypass always() do
            authorize_if always()
          end
        end

        attributes do
          attribute :id, :integer do
            primary_key? true
            allow_nil? false
            public? true
          end

          attribute :name, :string do
            allow_nil? false
            public? true
          end

          attribute :sap_id, :string do
            public? true
          end

          attribute :sap_name, :string do
            public? true
          end

          attribute :custom_fields, :map do
            public? true
          end

          attribute :hidden_at, :utc_datetime do
            public? true
          end
        end
        """

        Igniter.Project.Module.create_module(igniter, module, contents)
      end
    end

    defp create_sync_spend_types_worker(igniter, module, domain_module, prefix) do
      {exists?, igniter} = Igniter.Project.Module.module_exists(igniter, module)

      if exists? do
        igniter
      else
        repo_module = Module.concat(prefix, Repo)
        spend_type_module = Module.concat(domain_module, SpendType)

        contents = """
        @moduledoc \"\"\"
        Synchronizes PX spend types into the local Projects.SpendType resource.
        \"\"\"

        use Oban.Worker, queue: :default, max_attempts: 3

        alias #{inspect(domain_module)}
        alias #{inspect(spend_type_module)}
        alias #{inspect(repo_module)}

        @impl Oban.Worker
        def perform(job) do
          case run_sync() do
            {:ok, summary} ->
              details = Map.put(summary, :completed_at, DateTime.utc_now() |> DateTime.to_iso8601())

              job
              |> Ecto.Changeset.change(%{meta: Map.merge(job.meta, details)})
              |> Repo.update!()

              :ok

            {:error, reason, summary} ->
              details =
                summary
                |> Map.put(:error, inspect(reason))
                |> Map.put(:completed_at, DateTime.utc_now() |> DateTime.to_iso8601())

              _ =
                job
                |> Ecto.Changeset.change(%{meta: Map.merge(job.meta, details)})
                |> Repo.update()

              {:error, reason}
          end
        end

        @doc \"\"\"
        Syncs the provided spend types payload into the local spend_types table.
        \"\"\"
        def execute(spend_types) when is_list(spend_types) do
          sync_spend_types(spend_types)
        end

        defp run_sync do
          case BluetabConnect.Px.Rest.list_spend_types() do
            {:ok, spend_types} when is_list(spend_types) ->
              {:ok, execute(spend_types)}

            {:ok, _unexpected_payload} ->
              {:error, :invalid_payload, empty_result()}

            {:error, reason} ->
              {:error, reason, empty_result()}
          end
        end

        defp sync_spend_types(spend_types) do
          existing_spend_types = Ash.read!(SpendType, domain: Projects, authorize?: false)
          existing_by_id = Map.new(existing_spend_types, &{&1.id, &1})

          result =
            Enum.reduce(
              spend_types,
              %{created: [], updated: [], skipped: [], hidden: [], failed: []},
              fn raw_spend_type, acc ->
                attrs = extract_spend_type_attrs(raw_spend_type)
                spend_type_id = Map.get(attrs, :id)
                name = Map.get(attrs, :name)

                case Map.get(existing_by_id, spend_type_id) do
                  nil ->
                    case Ash.create(SpendType, attrs,
                           action: :create,
                           domain: Projects,
                           authorize?: false
                         ) do
                      {:ok, _created} ->
                        %{acc | created: [%{id: spend_type_id, name: name} | acc.created]}

                      {:error, error} ->
                        %{
                          acc
                          | failed: [
                              %{id: spend_type_id, name: name, error: inspect(error)}
                              | acc.failed
                            ]
                        }
                    end

                  existing ->
                    changes = build_changes(existing, attrs)

                    if map_size(changes) == 0 do
                      %{acc | skipped: [%{id: spend_type_id, name: name} | acc.skipped]}
                    else
                      case existing
                           |> Ash.Changeset.for_update(:sync_from_px, changes)
                           |> Ash.update(authorize?: false) do
                        {:ok, _updated} ->
                          %{
                            acc
                            | updated: [
                                %{id: spend_type_id, name: name, changes: presentable_changes(changes)}
                                | acc.updated
                              ]
                          }

                        {:error, error} ->
                          %{
                            acc
                            | failed: [
                                %{id: spend_type_id, name: name, error: inspect(error)}
                                | acc.failed
                              ]
                          }
                      end
                    end
                end
              end
            )

          incoming_ids =
            spend_types
            |> Enum.map(&extract_spend_type_attrs/1)
            |> Enum.map(&Map.get(&1, :id))
            |> MapSet.new()

          hidden_result = soft_hide_missing(existing_spend_types, incoming_ids, result)

          %{
            total: length(spend_types),
            created_count: length(hidden_result.created),
            updated_count: length(hidden_result.updated),
            skipped_count: length(hidden_result.skipped),
            hidden_count: length(hidden_result.hidden),
            failed_count: length(hidden_result.failed),
            created: Enum.reverse(hidden_result.created),
            updated: Enum.reverse(hidden_result.updated),
            skipped: Enum.reverse(hidden_result.skipped),
            hidden: Enum.reverse(hidden_result.hidden),
            failed: Enum.reverse(hidden_result.failed)
          }
        end

        defp extract_spend_type_attrs(raw) do
          %{
            id: parse_integer(raw["id"]),
            name: normalize_string(raw["name"]),
            sap_id: normalize_string(raw["sap_id"]),
            sap_name: normalize_string(raw["sap_name"]),
            custom_fields: normalize_custom_fields(raw["custom_fields"])
          }
          |> drop_nil_values()
        end

        defp build_changes(existing, attrs) do
          attrs
          |> Map.put_new(:hidden_at, nil)
          |> Map.drop([:id])
          |> Enum.reduce(%{}, fn {key, value}, changes ->
            if Map.get(existing, key) != value do
              Map.put(changes, key, value)
            else
              changes
            end
          end)
        end

        defp soft_hide_missing(existing_spend_types, incoming_ids, result) do
          Enum.reduce(existing_spend_types, result, fn spend_type, acc ->
            cond do
              MapSet.member?(incoming_ids, spend_type.id) ->
                acc

              not is_nil(spend_type.hidden_at) ->
                acc

              true ->
                case spend_type
                     |> Ash.Changeset.for_update(:sync_from_px, %{hidden_at: DateTime.utc_now()})
                     |> Ash.update(authorize?: false) do
                  {:ok, _hidden} ->
                    %{acc | hidden: [%{id: spend_type.id, name: spend_type.name} | acc.hidden]}

                  {:error, error} ->
                    %{
                      acc
                      | failed: [%{id: spend_type.id, name: spend_type.name, error: inspect(error)} | acc.failed]
                    }
                end
            end
          end)
        end

        defp empty_result do
          %{
            total: 0,
            created_count: 0,
            updated_count: 0,
            skipped_count: 0,
            hidden_count: 0,
            failed_count: 0,
            created: [],
            updated: [],
            skipped: [],
            hidden: [],
            failed: []
          }
        end

        defp normalize_custom_fields(nil), do: %{"fields" => []}
        defp normalize_custom_fields(value) when is_map(value), do: value
        defp normalize_custom_fields(value) when is_list(value), do: %{"fields" => value}
        defp normalize_custom_fields(_), do: %{"fields" => []}

        defp drop_nil_values(map) do
          map
          |> Enum.reject(fn {_key, value} -> is_nil(value) end)
          |> Map.new()
        end

        defp presentable_changes(changes) do
          Enum.map(changes, fn {field, value} ->
            %{field: to_string(field), new_value: format_change_value(value)}
          end)
        end

        defp format_change_value(value) when is_binary(value), do: value
        defp format_change_value(value), do: inspect(value)

        defp parse_integer(nil), do: nil
        defp parse_integer(value) when is_integer(value), do: value

        defp parse_integer(value) when is_binary(value) do
          case Integer.parse(value) do
            {number, ""} -> number
            _ -> nil
          end
        end

        defp parse_integer(_), do: nil

        defp normalize_string(nil), do: nil

        defp normalize_string(value) when is_binary(value) do
          case String.trim(value) do
            "" -> nil
            trimmed -> trimmed
          end
        end

        defp normalize_string(value), do: to_string(value)
        """

        Igniter.Project.Module.create_module(igniter, module, contents)
      end
    end

    # ──────────────────────────────────────────────
    # Hour types: HourType resource + SyncHourTypesWorker
    # ──────────────────────────────────────────────

    defp create_hour_type_resource(igniter, module, domain_module, repo_module) do
      {exists?, igniter} = Igniter.Project.Module.module_exists(igniter, module)

      if exists? do
        igniter
      else
        contents = """
        use Ash.Resource,
          domain: #{inspect(domain_module)},
          data_layer: AshPostgres.DataLayer,
          authorizers: [Ash.Policy.Authorizer]

        postgres do
          table "hour_types"
          repo #{inspect(repo_module)}
        end

        actions do
          defaults [:read]

          create :create do
            primary? true
            accept [:id, :name, :is_default, :hidden_at]
          end

          update :sync_from_px do
            accept [:name, :is_default, :hidden_at]
          end
        end

        policies do
          bypass always() do
            authorize_if always()
          end
        end

        attributes do
          attribute :id, :string do
            primary_key? true
            allow_nil? false
            public? true
          end

          attribute :name, :string do
            allow_nil? false
            public? true
          end

          attribute :is_default, :boolean do
            allow_nil? false
            default false
            public? true
          end

          attribute :hidden_at, :utc_datetime do
            public? true
          end
        end
        """

        Igniter.Project.Module.create_module(igniter, module, contents)
      end
    end

    defp create_sync_hour_types_worker(igniter, module, domain_module, prefix) do
      {exists?, igniter} = Igniter.Project.Module.module_exists(igniter, module)

      if exists? do
        igniter
      else
        repo_module = Module.concat(prefix, Repo)
        hour_type_module = Module.concat(domain_module, HourType)

        contents = """
        @moduledoc \"\"\"
        Synchronizes SAP SOAP hour types into the local Projects.HourType resource.
        \"\"\"

        use Oban.Worker, queue: :default, max_attempts: 3

        alias #{inspect(domain_module)}
        alias #{inspect(hour_type_module)}
        alias #{inspect(repo_module)}

        @impl Oban.Worker
        def perform(job) do
          case run_sync() do
            {:ok, summary} ->
              details = Map.put(summary, :completed_at, DateTime.utc_now() |> DateTime.to_iso8601())

              job
              |> Ecto.Changeset.change(%{meta: Map.merge(job.meta, details)})
              |> Repo.update!()

              :ok

            {:error, reason, summary} ->
              details =
                summary
                |> Map.put(:error, inspect(reason))
                |> Map.put(:completed_at, DateTime.utc_now() |> DateTime.to_iso8601())

              _ =
                job
                |> Ecto.Changeset.change(%{meta: Map.merge(job.meta, details)})
                |> Repo.update()

              {:error, reason}
          end
        end

        @doc \"\"\"
        Syncs the provided hour types payload into the local hour_types table.
        \"\"\"
        def execute(hour_types) when is_list(hour_types) do
          sync_hour_types(hour_types)
        end

        defp run_sync do
          case BluetabConnect.Sap.Soap.Proyectos.get_tipos_horas() do
            {:ok, hour_types} when is_list(hour_types) ->
              {:ok, execute(hour_types)}

            {:ok, _unexpected_payload} ->
              {:error, :invalid_payload, empty_result()}

            {:error, reason} ->
              {:error, reason, empty_result()}
          end
        end

        defp sync_hour_types(hour_types) do
          existing_hour_types = Ash.read!(HourType, domain: Projects, authorize?: false)
          existing_by_id = Map.new(existing_hour_types, &{&1.id, &1})

          result =
            Enum.reduce(
              hour_types,
              %{created: [], updated: [], skipped: [], hidden: [], failed: []},
              fn raw_hour_type, acc ->
                attrs = extract_hour_type_attrs(raw_hour_type)
                hour_type_id = Map.get(attrs, :id)
                name = Map.get(attrs, :name)

                case Map.get(existing_by_id, hour_type_id) do
                  nil ->
                    case Ash.create(HourType, attrs,
                           action: :create,
                           domain: Projects,
                           authorize?: false
                         ) do
                      {:ok, _created} ->
                        %{acc | created: [%{id: hour_type_id, name: name} | acc.created]}

                      {:error, error} ->
                        %{
                          acc
                          | failed: [
                              %{id: hour_type_id, name: name, error: inspect(error)}
                              | acc.failed
                            ]
                        }
                    end

                  existing ->
                    changes = build_changes(existing, attrs)

                    if map_size(changes) == 0 do
                      %{acc | skipped: [%{id: hour_type_id, name: name} | acc.skipped]}
                    else
                      case existing
                           |> Ash.Changeset.for_update(:sync_from_px, changes)
                           |> Ash.update(authorize?: false) do
                        {:ok, _updated} ->
                          %{
                            acc
                            | updated: [
                                %{id: hour_type_id, name: name, changes: presentable_changes(changes)}
                                | acc.updated
                              ]
                          }

                        {:error, error} ->
                          %{
                            acc
                            | failed: [
                                %{id: hour_type_id, name: name, error: inspect(error)}
                                | acc.failed
                              ]
                          }
                      end
                    end
                end
              end
            )

          incoming_ids =
            hour_types
            |> Enum.map(&extract_hour_type_attrs/1)
            |> Enum.map(&Map.get(&1, :id))
            |> MapSet.new()

          hidden_result = soft_hide_missing(existing_hour_types, incoming_ids, result)

          %{
            total: length(hour_types),
            created_count: length(hidden_result.created),
            updated_count: length(hidden_result.updated),
            skipped_count: length(hidden_result.skipped),
            hidden_count: length(hidden_result.hidden),
            failed_count: length(hidden_result.failed),
            created: Enum.reverse(hidden_result.created),
            updated: Enum.reverse(hidden_result.updated),
            skipped: Enum.reverse(hidden_result.skipped),
            hidden: Enum.reverse(hidden_result.hidden),
            failed: Enum.reverse(hidden_result.failed)
          }
        end

        defp extract_hour_type_attrs(raw) do
          %{
            id: raw |> map_get(:code) |> normalize_string(),
            name: raw |> map_get(:name) |> normalize_string(),
            is_default: raw |> map_get(:is_default) |> parse_boolean()
          }
          |> drop_nil_values()
        end

        defp build_changes(existing, attrs) do
          attrs
          |> Map.put_new(:hidden_at, nil)
          |> Map.drop([:id])
          |> Enum.reduce(%{}, fn {key, value}, changes ->
            if Map.get(existing, key) != value do
              Map.put(changes, key, value)
            else
              changes
            end
          end)
        end

        defp soft_hide_missing(existing_hour_types, incoming_ids, result) do
          Enum.reduce(existing_hour_types, result, fn hour_type, acc ->
            cond do
              MapSet.member?(incoming_ids, hour_type.id) ->
                acc

              not is_nil(hour_type.hidden_at) ->
                acc

              true ->
                case hour_type
                     |> Ash.Changeset.for_update(:sync_from_px, %{hidden_at: DateTime.utc_now()})
                     |> Ash.update(authorize?: false) do
                  {:ok, _hidden} ->
                    %{acc | hidden: [%{id: hour_type.id, name: hour_type.name} | acc.hidden]}

                  {:error, error} ->
                    %{
                      acc
                      | failed: [%{id: hour_type.id, name: hour_type.name, error: inspect(error)} | acc.failed]
                    }
                end
            end
          end)
        end

        defp empty_result do
          %{
            total: 0,
            created_count: 0,
            updated_count: 0,
            skipped_count: 0,
            hidden_count: 0,
            failed_count: 0,
            created: [],
            updated: [],
            skipped: [],
            hidden: [],
            failed: []
          }
        end

        defp map_get(map, key) when is_map(map) do
          Map.get(map, key) || Map.get(map, to_string(key))
        end

        defp map_get(_map, _key), do: nil

        defp drop_nil_values(map) do
          map
          |> Enum.reject(fn {_key, value} -> is_nil(value) end)
          |> Map.new()
        end

        defp presentable_changes(changes) do
          Enum.map(changes, fn {field, value} ->
            %{field: to_string(field), new_value: format_change_value(value)}
          end)
        end

        defp format_change_value(value) when is_binary(value), do: value
        defp format_change_value(value), do: inspect(value)

        defp parse_boolean(true), do: true
        defp parse_boolean(false), do: false
        defp parse_boolean(1), do: true
        defp parse_boolean(0), do: false

        defp parse_boolean(value) when is_binary(value) do
          case String.downcase(String.trim(value)) do
            "true" -> true
            "1" -> true
            "false" -> false
            "0" -> false
            _ -> nil
          end
        end

        defp parse_boolean(_), do: nil

        defp normalize_string(nil), do: nil

        defp normalize_string(value) when is_binary(value) do
          case String.trim(value) do
            "" -> nil
            trimmed -> trimmed
          end
        end

        defp normalize_string(value), do: to_string(value)
        """

        Igniter.Project.Module.create_module(igniter, module, contents)
      end
    end

    # ──────────────────────────────────────────────
    # Holidays: Holiday resource + SyncHolidaysWorker
    # ──────────────────────────────────────────────

    defp create_holiday_resource(igniter, module, domain_module, repo_module) do
      {exists?, igniter} = Igniter.Project.Module.module_exists(igniter, module)

      if exists? do
        igniter
      else
        contents = """
        use Ash.Resource,
          domain: #{inspect(domain_module)},
          data_layer: AshPostgres.DataLayer,
          authorizers: [Ash.Policy.Authorizer]

        postgres do
          table "holidays"
          repo #{inspect(repo_module)}
        end

        actions do
          defaults [:read]

          create :create do
            primary? true
            accept [:calendar_code, :date, :holiday_code, :name, :hidden_at]
          end

          update :sync_from_px do
            accept [:name, :hidden_at]
          end
        end

        policies do
          bypass always() do
            authorize_if always()
          end
        end

        attributes do
          uuid_primary_key :id

          attribute :calendar_code, :string do
            allow_nil? false
            public? true
          end

          attribute :date, :date do
            allow_nil? false
            public? true
          end

          attribute :holiday_code, :string do
            allow_nil? false
            public? true
          end

          attribute :name, :string do
            public? true
          end

          attribute :hidden_at, :utc_datetime do
            public? true
          end
        end

        identities do
          identity :unique_holiday, [:calendar_code, :date, :holiday_code]
        end
        """

        Igniter.Project.Module.create_module(igniter, module, contents)
      end
    end

    defp create_sync_holidays_worker(igniter, module, domain_module, prefix) do
      {exists?, igniter} = Igniter.Project.Module.module_exists(igniter, module)

      if exists? do
        igniter
      else
        repo_module = Module.concat(prefix, Repo)
        holiday_module = Module.concat(domain_module, Holiday)

        contents = """
        @moduledoc \"\"\"
        Synchronizes SuccessFactors holiday calendars into the local Projects.Holiday resource.

        The source payload is nested (`calendars.holidays`) and gets flattened into holiday rows.
        \"\"\"

        use Oban.Worker, queue: :default, max_attempts: 3

        alias #{inspect(domain_module)}
        alias #{inspect(holiday_module)}, as: Holiday
        alias #{inspect(repo_module)}

        @impl Oban.Worker
        def perform(job) do
          case run_sync() do
            {:ok, summary} ->
              details = Map.put(summary, :completed_at, DateTime.utc_now() |> DateTime.to_iso8601())

              job
              |> Ecto.Changeset.change(%{meta: Map.merge(job.meta, details)})
              |> Repo.update!()

              :ok

            {:error, reason, summary} ->
              details =
                summary
                |> Map.put(:error, inspect(reason))
                |> Map.put(:completed_at, DateTime.utc_now() |> DateTime.to_iso8601())

              _ =
                job
                |> Ecto.Changeset.change(%{meta: Map.merge(job.meta, details)})
                |> Repo.update()

              {:error, reason}
          end
        end

        @doc \"\"\"
        Syncs a flat holiday list into the local holidays table.
        \"\"\"
        def execute(holidays) when is_list(holidays) do
          sync_holidays(holidays)
        end

        defp run_sync do
          case BluetabConnect.Sap.SuccessFactors.list_holiday_calendars() do
            {:ok, calendars} when is_list(calendars) ->
              calendars
              |> flatten_holiday_calendars()
              |> execute()
              |> then(&{:ok, &1})

            {:ok, _unexpected_payload} ->
              {:error, :invalid_payload, empty_result()}

            {:error, reason} ->
              {:error, reason, empty_result()}
          end
        end

        defp flatten_holiday_calendars(calendars) do
          Enum.flat_map(calendars, fn calendar ->
            calendar_code = normalize_string(map_get(calendar, :code))

            holidays =
              case map_get(calendar, :holidays) do
                items when is_list(items) -> items
                _ -> []
              end

            Enum.map(holidays, fn holiday ->
              %{
                calendar_code: calendar_code,
                date: map_get(holiday, :date),
                holiday_code: map_get(holiday, :holiday_code),
                name: map_get(holiday, :name)
              }
            end)
          end)
        end

        defp sync_holidays(holidays) do
          existing_holidays = Ash.read!(Holiday, domain: Projects, authorize?: false)
          existing_by_key = Map.new(existing_holidays, &{holiday_key(&1), &1})

          result =
            Enum.reduce(
              holidays,
              %{created: [], updated: [], skipped: [], hidden: [], failed: []},
              fn raw_holiday, acc ->
                attrs = extract_holiday_attrs(raw_holiday)
                key = holiday_key(attrs)

                if is_nil(key) do
                  %{acc | failed: [%{item: raw_holiday, error: "missing holiday key fields"} | acc.failed]}
                else
                  case Map.get(existing_by_key, key) do
                    nil ->
                      case Ash.create(Holiday, attrs,
                             action: :create,
                             domain: Projects,
                             authorize?: false
                           ) do
                        {:ok, _created} ->
                          %{acc | created: [entry_from_key(key) | acc.created]}

                        {:error, error} ->
                          %{
                            acc
                            | failed: [
                                entry_from_key(key)
                                |> Map.put(:error, inspect(error))
                                | acc.failed
                              ]
                          }
                      end

                    existing ->
                      changes = build_changes(existing, attrs)

                      if map_size(changes) == 0 do
                        %{acc | skipped: [entry_from_key(key) | acc.skipped]}
                      else
                        case existing
                             |> Ash.Changeset.for_update(:sync_from_px, changes)
                             |> Ash.update(authorize?: false) do
                          {:ok, _updated} ->
                            %{
                              acc
                              | updated: [
                                  entry_from_key(key)
                                  |> Map.put(:changes, presentable_changes(changes))
                                  | acc.updated
                                ]
                            }

                          {:error, error} ->
                            %{
                              acc
                              | failed: [
                                  entry_from_key(key)
                                  |> Map.put(:error, inspect(error))
                                  | acc.failed
                                ]
                            }
                        end
                      end
                  end
                end
              end
            )

          incoming_keys =
            holidays
            |> Enum.map(&extract_holiday_attrs/1)
            |> Enum.map(&holiday_key/1)
            |> Enum.reject(&is_nil/1)
            |> MapSet.new()

          hidden_result = soft_hide_missing(existing_holidays, incoming_keys, result)

          %{
            total: length(holidays),
            created_count: length(hidden_result.created),
            updated_count: length(hidden_result.updated),
            skipped_count: length(hidden_result.skipped),
            hidden_count: length(hidden_result.hidden),
            failed_count: length(hidden_result.failed),
            created: Enum.reverse(hidden_result.created),
            updated: Enum.reverse(hidden_result.updated),
            skipped: Enum.reverse(hidden_result.skipped),
            hidden: Enum.reverse(hidden_result.hidden),
            failed: Enum.reverse(hidden_result.failed)
          }
        end

        defp soft_hide_missing(existing_holidays, incoming_keys, result) do
          Enum.reduce(existing_holidays, result, fn holiday, acc ->
            key = holiday_key(holiday)

            cond do
              MapSet.member?(incoming_keys, key) ->
                acc

              not is_nil(holiday.hidden_at) ->
                acc

              true ->
                case holiday
                     |> Ash.Changeset.for_update(:sync_from_px, %{hidden_at: DateTime.utc_now()})
                     |> Ash.update(authorize?: false) do
                  {:ok, _hidden} ->
                    %{acc | hidden: [entry_from_key(key) | acc.hidden]}

                  {:error, error} ->
                    %{
                      acc
                      | failed: [
                          entry_from_key(key)
                          |> Map.put(:error, inspect(error))
                          | acc.failed
                        ]
                    }
                end
            end
          end)
        end

        defp extract_holiday_attrs(raw) do
          %{
            calendar_code: normalize_string(map_get(raw, :calendar_code)),
            date: parse_date(map_get(raw, :date)),
            holiday_code: normalize_string(map_get(raw, :holiday_code)),
            name: normalize_string(map_get(raw, :name))
          }
          |> drop_nil_values()
        end

        defp build_changes(existing, attrs) do
          attrs
          |> Map.put_new(:hidden_at, nil)
          |> Map.drop([:calendar_code, :date, :holiday_code])
          |> Enum.reduce(%{}, fn {key, value}, changes ->
            if Map.get(existing, key) != value do
              Map.put(changes, key, value)
            else
              changes
            end
          end)
        end

        defp holiday_key(attrs) when is_map(attrs) do
          calendar_code = Map.get(attrs, :calendar_code)
          date = Map.get(attrs, :date)
          holiday_code = Map.get(attrs, :holiday_code)

          if is_binary(calendar_code) and match?(%Date{}, date) and is_binary(holiday_code) do
            {calendar_code, date, holiday_code}
          else
            nil
          end
        end

        defp entry_from_key({calendar_code, date, holiday_code}) do
          %{
            calendar_code: calendar_code,
            date: Date.to_iso8601(date),
            holiday_code: holiday_code
          }
        end

        defp empty_result do
          %{
            total: 0,
            created_count: 0,
            updated_count: 0,
            skipped_count: 0,
            hidden_count: 0,
            failed_count: 0,
            created: [],
            updated: [],
            skipped: [],
            hidden: [],
            failed: []
          }
        end

        defp map_get(map, key) when is_map(map) do
          Map.get(map, key) || Map.get(map, Atom.to_string(key))
        end

        defp map_get(_, _), do: nil

        defp drop_nil_values(map) do
          map
          |> Enum.reject(fn {_key, value} -> is_nil(value) end)
          |> Map.new()
        end

        defp presentable_changes(changes) do
          Enum.map(changes, fn {field, value} ->
            %{field: to_string(field), new_value: format_change_value(value)}
          end)
        end

        defp format_change_value(value) when is_binary(value), do: value
        defp format_change_value(value), do: inspect(value)

        defp parse_date(nil), do: nil
        defp parse_date(%Date{} = date), do: date

        defp parse_date(value) when is_binary(value) do
          value
          |> String.trim()
          |> case do
            "" ->
              nil

            trimmed ->
              case Date.from_iso8601(trimmed) do
                {:ok, date} ->
                  date

                {:error, _} ->
                  case DateTime.from_iso8601(trimmed) do
                    {:ok, datetime, _offset} ->
                      DateTime.to_date(datetime)

                    {:error, _} ->
                      case NaiveDateTime.from_iso8601(trimmed) do
                        {:ok, naive_datetime} -> NaiveDateTime.to_date(naive_datetime)
                        {:error, _} -> nil
                      end
                  end
              end
          end
        end

        defp parse_date(_), do: nil

        defp normalize_string(nil), do: nil

        defp normalize_string(value) when is_binary(value) do
          case String.trim(value) do
            "" -> nil
            trimmed -> trimmed
          end
        end

        defp normalize_string(value), do: to_string(value)
        """

        Igniter.Project.Module.create_module(igniter, module, contents)
      end
    end

    # ──────────────────────────────────────────────
    # Month end close: MonthEndClose + SyncMonthEndCloseWorker
    # ──────────────────────────────────────────────

    defp create_month_end_close_resource(igniter, module, domain_module, repo_module) do
      {exists?, igniter} = Igniter.Project.Module.module_exists(igniter, module)

      if exists? do
        igniter
      else
        contents = """
        use Ash.Resource,
          domain: #{inspect(domain_module)},
          data_layer: AshPostgres.DataLayer,
          authorizers: [Ash.Policy.Authorizer]

        postgres do
          table "month_end_closes"
          repo #{inspect(repo_module)}
        end

        actions do
          defaults [:read]

          create :create do
            primary? true
            accept [
              :id,
              :year,
              :month,
              :is_closed,
              :standard_work_hours,
              :preliminary_close_date,
              :report_lock_date,
              :approval_lock_date,
              :albaran_lock_date,
              :closing_date,
              :created_at,
              :updated_at
            ]
          end

          update :sync_from_px do
            accept [
              :year,
              :month,
              :is_closed,
              :standard_work_hours,
              :preliminary_close_date,
              :report_lock_date,
              :approval_lock_date,
              :albaran_lock_date,
              :closing_date,
              :created_at,
              :updated_at
            ]
          end
        end

        policies do
          bypass always() do
            authorize_if always()
          end
        end

        attributes do
          attribute :id, :integer do
            primary_key? true
            allow_nil? false
            public? true
          end

          attribute :year, :integer do
            allow_nil? false
            public? true
          end

          attribute :month, :integer do
            allow_nil? false
            public? true
          end

          attribute :is_closed, :boolean do
            allow_nil? false
            public? true
          end

          attribute :standard_work_hours, :integer do
            public? true
          end

          attribute :preliminary_close_date, :date do
            public? true
          end

          attribute :report_lock_date, :date do
            public? true
          end

          attribute :approval_lock_date, :date do
            public? true
          end

          attribute :albaran_lock_date, :date do
            public? true
          end

          attribute :closing_date, :date do
            public? true
          end

          attribute :created_at, :utc_datetime do
            public? true
          end

          attribute :updated_at, :utc_datetime do
            public? true
          end
        end
        """

        Igniter.Project.Module.create_module(igniter, module, contents)
      end
    end

    defp create_sync_month_end_close_worker(igniter, module, domain_module, prefix) do
      {exists?, igniter} = Igniter.Project.Module.module_exists(igniter, module)

      if exists? do
        igniter
      else
        repo_module = Module.concat(prefix, Repo)
        month_end_close_module = Module.concat(domain_module, MonthEndClose)

        contents = """
        @moduledoc \"\"\"
        Synchronizes PX month end close rows into the local Projects.MonthEndClose resource.

        Rows missing from a future API response are not deleted or hidden locally.
        \"\"\"

        use Oban.Worker, queue: :default, max_attempts: 3

        alias #{inspect(domain_module)}
        alias #{inspect(month_end_close_module)}
        alias #{inspect(repo_module)}

        @impl Oban.Worker
        def perform(job) do
          case run_sync() do
            {:ok, summary} ->
              details = Map.put(summary, :completed_at, DateTime.utc_now() |> DateTime.to_iso8601())

              job
              |> Ecto.Changeset.change(%{meta: Map.merge(job.meta, details)})
              |> Repo.update!()

              :ok

            {:error, reason, summary} ->
              details =
                summary
                |> Map.put(:error, inspect(reason))
                |> Map.put(:completed_at, DateTime.utc_now() |> DateTime.to_iso8601())

              _ =
                job
                |> Ecto.Changeset.change(%{meta: Map.merge(job.meta, details)})
                |> Repo.update()

              {:error, reason}
          end
        end

        @doc \"\"\"
        Syncs the provided month end close payload into the month_end_closes table.
        \"\"\"
        def execute(records) when is_list(records) do
          sync_month_end_closes(records)
        end

        defp run_sync do
          case BluetabConnect.Px.Rest.list_month_end_close() do
            {:ok, %{"month_end_close" => records}} when is_list(records) ->
              {:ok, execute(records)}

            {:ok, _unexpected_payload} ->
              {:error, :invalid_payload, empty_result()}

            {:error, reason} ->
              {:error, reason, empty_result()}
          end
        end

        defp sync_month_end_closes(records) do
          existing = Ash.read!(MonthEndClose, domain: Projects, authorize?: false)
          existing_by_id = Map.new(existing, &{&1.id, &1})

          result =
            Enum.reduce(
              records,
              %{created: [], updated: [], skipped: [], failed: []},
              fn raw, acc ->
                attrs = extract_month_end_close_attrs(raw)
                id = Map.get(attrs, :id)

                case Map.get(existing_by_id, id) do
                  nil ->
                    case Ash.create(MonthEndClose, attrs,
                           action: :create,
                           domain: Projects,
                           authorize?: false
                         ) do
                      {:ok, _created} ->
                        %{acc | created: [%{id: id, year: attrs[:year], month: attrs[:month]} | acc.created]}

                      {:error, error} ->
                        %{
                          acc
                          | failed: [
                              %{id: id, year: attrs[:year], month: attrs[:month], error: inspect(error)}
                              | acc.failed
                            ]
                        }
                    end

                  row ->
                    changes = build_changes(row, attrs)

                    if map_size(changes) == 0 do
                      %{acc | skipped: [%{id: id, year: row.year, month: row.month} | acc.skipped]}
                    else
                      case row
                           |> Ash.Changeset.for_update(:sync_from_px, changes)
                           |> Ash.update(authorize?: false) do
                        {:ok, _updated} ->
                          %{
                            acc
                            | updated: [
                                %{
                                  id: id,
                                  year: row.year,
                                  month: row.month,
                                  changes: presentable_changes(changes)
                                }
                                | acc.updated
                              ]
                          }

                        {:error, error} ->
                          %{
                            acc
                            | failed: [
                                %{id: id, year: row.year, month: row.month, error: inspect(error)}
                                | acc.failed
                              ]
                          }
                      end
                    end
                end
              end
            )

          %{
            total: length(records),
            created_count: length(result.created),
            updated_count: length(result.updated),
            skipped_count: length(result.skipped),
            failed_count: length(result.failed),
            created: Enum.reverse(result.created),
            updated: Enum.reverse(result.updated),
            skipped: Enum.reverse(result.skipped),
            failed: Enum.reverse(result.failed)
          }
        end

        defp extract_month_end_close_attrs(raw) do
          %{
            id: parse_integer(raw["id"]),
            year: parse_integer(raw["year"]),
            month: parse_integer(raw["month"]),
            is_closed: parse_boolean(raw["is_closed"]),
            standard_work_hours: parse_integer(raw["standard_work_hours"]),
            preliminary_close_date: parse_date(raw["preliminary_close_date"]),
            report_lock_date: parse_date(raw["report_lock_date"]),
            approval_lock_date: parse_date(raw["approval_lock_date"]),
            albaran_lock_date: parse_date(raw["albaran_lock_date"]),
            closing_date: parse_date(raw["closing_date"]),
            created_at: parse_datetime_utc(raw["created_at"]),
            updated_at: parse_datetime_utc(raw["updated_at"])
          }
        end

        defp build_changes(existing, attrs) do
          attrs
          |> Map.drop([:id])
          |> Enum.reduce(%{}, fn {key, value}, changes ->
            if Map.get(existing, key) != value do
              Map.put(changes, key, value)
            else
              changes
            end
          end)
        end

        defp empty_result do
          %{
            total: 0,
            created_count: 0,
            updated_count: 0,
            skipped_count: 0,
            failed_count: 0,
            created: [],
            updated: [],
            skipped: [],
            failed: []
          }
        end

        defp presentable_changes(changes) do
          Enum.map(changes, fn {field, value} ->
            %{field: to_string(field), new_value: format_change_value(value)}
          end)
        end

        defp format_change_value(%Date{} = d), do: Date.to_iso8601(d)
        defp format_change_value(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
        defp format_change_value(value) when is_binary(value), do: value
        defp format_change_value(value), do: inspect(value)

        defp parse_boolean(true), do: true
        defp parse_boolean(false), do: false
        defp parse_boolean("true"), do: true
        defp parse_boolean("false"), do: false
        defp parse_boolean(_), do: false

        defp parse_integer(nil), do: nil
        defp parse_integer(value) when is_integer(value), do: value

        defp parse_integer(value) when is_binary(value) do
          case Integer.parse(value) do
            {number, ""} -> number
            _ -> nil
          end
        end

        defp parse_integer(_), do: nil

        defp parse_date(nil), do: nil
        defp parse_date(%Date{} = date), do: date

        defp parse_date(date) when is_binary(date) do
          case Date.from_iso8601(date) do
            {:ok, parsed} -> parsed
            {:error, _} -> nil
          end
        end

        defp parse_date(_), do: nil

        defp parse_datetime_utc(nil), do: nil
        defp parse_datetime_utc(%DateTime{} = dt), do: dt

        defp parse_datetime_utc(value) when is_binary(value) do
          case DateTime.from_iso8601(value) do
            {:ok, dt, _} ->
              dt

            {:error, _} ->
              case NaiveDateTime.from_iso8601(value) do
                {:ok, naive} -> DateTime.from_naive!(naive, "Etc/UTC")
                {:error, _} -> nil
              end
          end
        end

        defp parse_datetime_utc(_), do: nil
        """

        Igniter.Project.Module.create_module(igniter, module, contents)
      end
    end

    # ──────────────────────────────────────────────
    # Positions: Position + PositionRelationship + SyncPositionsWorker
    # ──────────────────────────────────────────────

    defp create_position_resource(igniter, module, domain_module, repo_module) do
      {exists?, igniter} = Igniter.Project.Module.module_exists(igniter, module)

      if exists? do
        igniter
      else
        contents = """
        use Ash.Resource,
          domain: #{inspect(domain_module)},
          data_layer: AshPostgres.DataLayer,
          authorizers: [Ash.Policy.Authorizer]

        postgres do
          table "positions"
          repo #{inspect(repo_module)}
        end

        actions do
          defaults [:read]

          create :create do
            primary? true

            accept [
              :id,
              :name,
              :is_default,
              :is_active,
              :employee_number,
              :default_for_employee_number,
              :manager_position_id,
              :hidden_at
            ]
          end

          update :sync_from_px do
            accept [
              :name,
              :is_default,
              :is_active,
              :employee_number,
              :default_for_employee_number,
              :manager_position_id,
              :hidden_at
            ]
          end
        end

        policies do
          bypass always() do
            authorize_if always()
          end
        end

        attributes do
          attribute :id, :integer do
            primary_key? true
            allow_nil? false
            public? true
          end

          attribute :name, :string do
            allow_nil? false
            public? true
          end

          attribute :is_default, :boolean do
            public? true
          end

          attribute :is_active, :boolean do
            public? true
          end

          attribute :employee_number, :integer do
            public? true
          end

          attribute :default_for_employee_number, :integer do
            public? true
          end

          attribute :manager_position_id, :integer do
            public? true
          end

          attribute :hidden_at, :utc_datetime do
            public? true
          end
        end
        """

        Igniter.Project.Module.create_module(igniter, module, contents)
      end
    end

    defp create_position_relationship_resource(igniter, module, domain_module, repo_module) do
      {exists?, igniter} = Igniter.Project.Module.module_exists(igniter, module)

      if exists? do
        igniter
      else
        position_module = Module.concat(domain_module, Position)

        contents = """
        use Ash.Resource,
          domain: #{inspect(domain_module)},
          data_layer: AshPostgres.DataLayer,
          authorizers: [Ash.Policy.Authorizer]

        postgres do
          table "position_relationships"
          repo #{inspect(repo_module)}
        end

        actions do
          defaults [:read]

          create :create do
            primary? true
            accept [:position_id, :manager_position_id, :hidden_at]
          end

          update :sync_from_px do
            accept [:manager_position_id, :hidden_at]
          end
        end

        policies do
          bypass always() do
            authorize_if always()
          end
        end

        attributes do
          attribute :position_id, :integer do
            primary_key? true
            allow_nil? false
            public? true
          end

          attribute :manager_position_id, :integer do
            public? true
          end

          attribute :hidden_at, :utc_datetime do
            public? true
          end
        end

        relationships do
          belongs_to :position, #{inspect(position_module)} do
            source_attribute :position_id
            destination_attribute :id
            define_attribute? false
          end

          belongs_to :manager_position, #{inspect(position_module)} do
            source_attribute :manager_position_id
            destination_attribute :id
            define_attribute? false
          end
        end
        """

        Igniter.Project.Module.create_module(igniter, module, contents)
      end
    end

    defp create_sync_positions_worker(igniter, module, domain_module, prefix) do
      {exists?, igniter} = Igniter.Project.Module.module_exists(igniter, module)

      if exists? do
        igniter
      else
        repo_module = Module.concat(prefix, Repo)
        position_module = Module.concat(domain_module, Position)
        position_relationship_module = Module.concat(domain_module, PositionRelationship)

        contents = """
        @moduledoc \"\"\"
        Synchronizes PX positions and current position relationships into local resources.

        `assigned_employee` is intentionally ignored for now.
        \"\"\"

        use Oban.Worker, queue: :default, max_attempts: 3

        alias #{inspect(domain_module)}
        alias #{inspect(position_module)}, as: Position
        alias #{inspect(position_relationship_module)}, as: PositionRelationship
        alias #{inspect(repo_module)}

        @impl Oban.Worker
        def perform(job) do
          case run_sync() do
            {:ok, summary} ->
              details = Map.put(summary, :completed_at, DateTime.utc_now() |> DateTime.to_iso8601())

              job
              |> Ecto.Changeset.change(%{meta: Map.merge(job.meta, details)})
              |> Repo.update!()

              :ok

            {:error, reason, summary} ->
              details =
                summary
                |> Map.put(:error, inspect(reason))
                |> Map.put(:completed_at, DateTime.utc_now() |> DateTime.to_iso8601())

              _ =
                job
                |> Ecto.Changeset.change(%{meta: Map.merge(job.meta, details)})
                |> Repo.update()

              {:error, reason}
          end
        end

        @doc \"\"\"
        Syncs positions and relationships payload into local resources.
        \"\"\"
        def execute(%{positions: positions, relationships: relationships})
            when is_list(positions) and is_list(relationships) do
          positions_result = sync_positions(positions)
          relationships_result = sync_position_relationships(relationships)

          %{
            total_positions: length(positions),
            total_relationships: length(relationships),
            positions: positions_result,
            relationships: relationships_result
          }
        end

        def execute(_), do: empty_result()

        defp run_sync do
          case BluetabConnect.Px.Rest.list_positions() do
            {:ok, %{"positions" => positions, "relationships" => relationships}}
            when is_list(positions) and is_list(relationships) ->
              {:ok, execute(%{positions: positions, relationships: relationships})}

            {:ok, _unexpected_payload} ->
              {:error, :invalid_payload, empty_result()}

            {:error, reason} ->
              {:error, reason, empty_result()}
          end
        end

        defp sync_positions(items) do
          sync_resource(Position, items, :id, &map_position/1)
        end

        defp sync_position_relationships(items) do
          sync_resource(PositionRelationship, items, :position_id, &map_relationship/1)
        end

        defp sync_resource(resource, items, key_field, mapper) do
          existing_items = Ash.read!(resource, domain: Projects, authorize?: false)
          existing_by_key = Map.new(existing_items, &{Map.get(&1, key_field), &1})

          result =
            Enum.reduce(
              items,
              %{created: [], updated: [], skipped: [], hidden: [], failed: []},
              fn raw_item, acc ->
                attrs = mapper.(raw_item)
                key = Map.get(attrs, key_field)
                name = Map.get(attrs, :name)

                if is_nil(key) do
                  %{
                    acc
                    | failed: [
                        %{item: raw_item, error: "missing \#{key_field}"}
                        | acc.failed
                      ]
                  }
                else
                  case Map.get(existing_by_key, key) do
                    nil ->
                      case Ash.create(resource, attrs,
                             action: :create,
                             domain: Projects,
                             authorize?: false
                           ) do
                        {:ok, _created} ->
                          %{acc | created: [resource_entry(key_field, key, name) | acc.created]}

                        {:error, error} ->
                          %{
                            acc
                            | failed: [
                                resource_entry(key_field, key, name)
                                |> Map.put(:error, inspect(error))
                                | acc.failed
                              ]
                          }
                      end

                    existing ->
                      changes = build_changes(existing, attrs, key_field)

                      if map_size(changes) == 0 do
                        %{acc | skipped: [resource_entry(key_field, key, name) | acc.skipped]}
                      else
                        case existing
                             |> Ash.Changeset.for_update(:sync_from_px, changes)
                             |> Ash.update(authorize?: false) do
                          {:ok, _updated} ->
                            %{
                              acc
                              | updated: [
                                  resource_entry(key_field, key, name)
                                  |> Map.put(:changes, presentable_changes(changes))
                                  | acc.updated
                                ]
                            }

                          {:error, error} ->
                            %{
                              acc
                              | failed: [
                                  resource_entry(key_field, key, name)
                                  |> Map.put(:error, inspect(error))
                                  | acc.failed
                                ]
                            }
                        end
                      end
                  end
                end
              end
            )

          incoming_keys =
            items
            |> Enum.map(&mapper.(&1))
            |> Enum.map(&Map.get(&1, key_field))
            |> Enum.reject(&is_nil/1)
            |> MapSet.new()

          hidden_result = soft_hide_missing(existing_items, incoming_keys, key_field, result)

          %{
            total: length(items),
            created_count: length(hidden_result.created),
            updated_count: length(hidden_result.updated),
            skipped_count: length(hidden_result.skipped),
            hidden_count: length(hidden_result.hidden),
            failed_count: length(hidden_result.failed),
            created: Enum.reverse(hidden_result.created),
            updated: Enum.reverse(hidden_result.updated),
            skipped: Enum.reverse(hidden_result.skipped),
            hidden: Enum.reverse(hidden_result.hidden),
            failed: Enum.reverse(hidden_result.failed)
          }
        end

        defp soft_hide_missing(existing_items, incoming_keys, key_field, result) do
          Enum.reduce(existing_items, result, fn item, acc ->
            key = Map.get(item, key_field)
            name = Map.get(item, :name)

            cond do
              MapSet.member?(incoming_keys, key) ->
                acc

              not is_nil(item.hidden_at) ->
                acc

              true ->
                case item
                     |> Ash.Changeset.for_update(:sync_from_px, %{hidden_at: DateTime.utc_now()})
                     |> Ash.update(authorize?: false) do
                  {:ok, _hidden} ->
                    %{acc | hidden: [resource_entry(key_field, key, name) | acc.hidden]}

                  {:error, error} ->
                    %{
                      acc
                      | failed: [
                          resource_entry(key_field, key, name)
                          |> Map.put(:error, inspect(error))
                          | acc.failed
                        ]
                    }
                end
            end
          end)
        end

        defp map_position(raw) do
          manager_position_id = parse_integer(raw["manager_position_id"])

          %{
            id: parse_integer(raw["id"]),
            name: normalize_string(raw["name"]),
            is_default: parse_boolean(raw["is_default"]),
            is_active: parse_boolean(raw["is_active"]),
            employee_number: parse_integer(raw["employee_number"]),
            default_for_employee_number: parse_integer(raw["default_for_employee_number"]),
            manager_position_id: manager_position_id
          }
          |> drop_nil_values()
          |> Map.put(:manager_position_id, manager_position_id)
        end

        defp map_relationship(raw) do
          %{
            position_id: parse_integer(raw["position_id"]),
            manager_position_id: parse_integer(raw["manager_position_id"])
          }
        end

        defp resource_entry(key_field, key, name) do
          entry = Map.put(%{}, key_field, key)

          if is_nil(name) do
            entry
          else
            Map.put(entry, :name, name)
          end
        end

        defp build_changes(existing, attrs, key_field) do
          attrs
          |> Map.put_new(:hidden_at, nil)
          |> Map.drop([key_field])
          |> Enum.reduce(%{}, fn {key, value}, changes ->
            if Map.get(existing, key) != value do
              Map.put(changes, key, value)
            else
              changes
            end
          end)
        end

        defp empty_stage_result do
          %{
            total: 0,
            created_count: 0,
            updated_count: 0,
            skipped_count: 0,
            hidden_count: 0,
            failed_count: 0,
            created: [],
            updated: [],
            skipped: [],
            hidden: [],
            failed: []
          }
        end

        defp empty_result do
          %{
            total_positions: 0,
            total_relationships: 0,
            positions: empty_stage_result(),
            relationships: empty_stage_result()
          }
        end

        defp presentable_changes(changes) do
          Enum.map(changes, fn {field, value} ->
            %{field: to_string(field), new_value: format_change_value(value)}
          end)
        end

        defp format_change_value(value) when is_binary(value), do: value
        defp format_change_value(value), do: inspect(value)

        defp drop_nil_values(map) do
          map
          |> Enum.reject(fn {_key, value} -> is_nil(value) end)
          |> Map.new()
        end

        defp parse_boolean(nil), do: nil
        defp parse_boolean(value) when is_boolean(value), do: value
        defp parse_boolean(1), do: true
        defp parse_boolean(0), do: false

        defp parse_boolean(value) when is_binary(value) do
          case String.downcase(String.trim(value)) do
            "true" -> true
            "false" -> false
            "1" -> true
            "0" -> false
            _ -> nil
          end
        end

        defp parse_boolean(_), do: nil

        defp parse_integer(nil), do: nil
        defp parse_integer(value) when is_integer(value), do: value
        defp parse_integer(value) when is_float(value), do: trunc(value)

        defp parse_integer(value) when is_binary(value) do
          case Integer.parse(value) do
            {number, ""} -> number
            _ -> parse_float_string(value)
          end
        end

        defp parse_integer(_), do: nil

        defp parse_float_string(value) do
          case Float.parse(value) do
            {number, ""} -> trunc(number)
            _ -> nil
          end
        end

        defp normalize_string(nil), do: nil

        defp normalize_string(value) when is_binary(value) do
          case String.trim(value) do
            "" -> nil
            trimmed -> trimmed
          end
        end

        defp normalize_string(value), do: to_string(value)
        """

        Igniter.Project.Module.create_module(igniter, module, contents)
      end
    end

    # ──────────────────────────────────────────────
    # Projects: Project resource + SyncProjectsWorker
    # ──────────────────────────────────────────────

    defp create_project_resource(igniter, module, domain_module, repo_module) do
      {exists?, igniter} = Igniter.Project.Module.module_exists(igniter, module)

      if exists? do
        igniter
      else
        client_module = Module.concat(domain_module, Client)
        cluster_module = Module.concat(domain_module, Cluster)

        contents = """
        use Ash.Resource,
          domain: #{inspect(domain_module)},
          data_layer: AshPostgres.DataLayer,
          authorizers: [Ash.Policy.Authorizer]

        postgres do
          table "projects"
          repo #{inspect(repo_module)}
        end

        actions do
          defaults [:read]

          create :create do
            primary? true

            accept [
              :sap_id,
              :doc_num,
              :name,
              :owner_sap_id,
              :client_id,
              :cluster_id,
              :is_time_off,
              :start_date,
              :end_date,
              :status
            ]
          end

          update :sync_from_px do
            accept [
              :sap_id,
              :name,
              :owner_sap_id,
              :client_id,
              :cluster_id,
              :is_time_off,
              :start_date,
              :end_date,
              :status
            ]
          end
        end

        policies do
          bypass always() do
            authorize_if always()
          end
        end

        attributes do
          uuid_primary_key :id

          attribute :sap_id, :integer do
            public? true
          end

          attribute :doc_num, :integer do
            allow_nil? false
            public? true
          end

          attribute :name, :string do
            allow_nil? false
            public? true
          end

          attribute :owner_sap_id, :integer do
            public? true
          end

          attribute :client_id, :integer do
            public? true
          end

          attribute :cluster_id, :integer do
            public? true
          end

          attribute :is_time_off, :boolean do
            public? true
          end

          attribute :start_date, :date do
            public? true
          end

          attribute :end_date, :date do
            public? true
          end

          attribute :status, :string do
            public? true
          end
        end

        relationships do
          belongs_to :client, #{inspect(client_module)} do
            source_attribute :client_id
            destination_attribute :id
            define_attribute? false
          end

          belongs_to :cluster, #{inspect(cluster_module)} do
            source_attribute :cluster_id
            destination_attribute :id
            define_attribute? false
          end
        end

        identities do
          identity :unique_doc_num, [:doc_num]
        end
        """

        Igniter.Project.Module.create_module(igniter, module, contents)
      end
    end

    defp create_sync_projects_worker(igniter, module, domain_module, prefix) do
      {exists?, igniter} = Igniter.Project.Module.module_exists(igniter, module)

      if exists? do
        igniter
      else
        repo_module = Module.concat(prefix, Repo)
        project_module = Module.concat(domain_module, Project)

        contents = """
        @moduledoc \"\"\"
        Synchronizes PX project data into the local Projects.Project resource.

        Fetches all pages from the PX API and upserts changed records,
        keyed by doc_num (the stable unique identifier from PX).

        The PX call explicitly requests `client_id`, `owner`, and `is_time_off` so project-client
        ownership data is always present in the payload, even when PX defaults
        would omit it.
        \"\"\"

        use Oban.Worker, queue: :default, max_attempts: 3

        import Ecto.Query

        alias #{inspect(domain_module)}
        alias #{inspect(project_module)}
        alias #{inspect(repo_module)}

        @impl Oban.Worker
        def perform(job) do
          with {:ok, projects} <- fetch_all_projects() do
            result = execute(projects)
            details = Map.put(result, :completed_at, DateTime.utc_now() |> DateTime.to_iso8601())

            job
            |> Ecto.Changeset.change(%{meta: Map.merge(job.meta, details)})
            |> Repo.update()

            :ok
          end
        end

        @doc \"\"\"
        Syncs a list of PX projects into the projects table.
        \"\"\"
        def execute(projects) when is_list(projects) do
          sync_projects(projects)
        end

        defp fetch_all_projects(page \\\\ 1, acc \\\\ []) do
          case BluetabConnect.Px.Rest.list_projects(
                 page: page,
                 per_page: 100,
                 fields: "client_id,owner,is_time_off,cluster_id"
               ) do
            {:ok, %{"projects" => [], "pagination" => _pagination}} ->
              {:ok, acc}

            {:ok, %{"projects" => projects, "pagination" => _pagination}} ->
              fetch_all_projects(page + 1, acc ++ projects)

            error ->
              error
          end
        end

        defp sync_projects(projects) do
          doc_nums =
            projects
            |> Enum.map(&parse_integer(&1["doc_num"]))
            |> Enum.reject(&is_nil/1)

          existing_by_doc_num =
            from(p in Project, where: p.doc_num in ^doc_nums)
            |> Repo.all()
            |> Map.new(&{&1.doc_num, &1})

          results =
            Enum.reduce(
              projects,
              %{created: [], updated: [], skipped: [], failed: []},
              fn raw_project, acc ->
                attrs = extract_project_attrs(raw_project)
                sync_single_project(existing_by_doc_num, attrs, raw_project, acc)
              end
            )

          %{
            total: length(projects),
            total_projects: length(projects),
            created_count: length(results.created),
            updated_count: length(results.updated),
            skipped_count: length(results.skipped),
            failed_count: length(results.failed),
            created: Enum.reverse(results.created),
            updated: Enum.reverse(results.updated),
            skipped: Enum.reverse(results.skipped),
            failed: Enum.reverse(results.failed)
          }
        end

        defp sync_single_project(existing_by_doc_num, attrs, raw_project, acc) do
          doc_num = Map.get(attrs, :doc_num)
          sap_id = Map.get(attrs, :sap_id)

          case Map.get(existing_by_doc_num, doc_num) do
            nil ->
              case Ash.create(Project, attrs, action: :create, domain: Projects, authorize?: false) do
                {:ok, _project} ->
                  %{acc | created: [%{doc_num: doc_num, sap_id: sap_id, name: attrs[:name]} | acc.created]}

                {:error, error} ->
                  %{
                    acc
                    | failed: [
                        %{doc_num: doc_num, sap_id: sap_id, project: raw_project, error: inspect(error)}
                        | acc.failed
                      ]
                  }
              end

            project ->
              case build_project_changes(project, attrs) do
                %{} = changes when map_size(changes) == 0 ->
                  %{acc | skipped: [%{doc_num: doc_num, sap_id: project.sap_id, name: project.name} | acc.skipped]}

                changes ->
                  case project
                       |> Ash.Changeset.for_update(:sync_from_px, changes)
                       |> Ash.update(authorize?: false) do
                    {:ok, _updated} ->
                      %{
                        acc
                        | updated: [
                            %{doc_num: doc_num, sap_id: sap_id, changes: presentable_changes(changes)}
                            | acc.updated
                          ]
                      }

                    {:error, error} ->
                      %{
                        acc
                        | failed: [
                            %{doc_num: doc_num, sap_id: sap_id, project: raw_project, error: inspect(error)}
                            | acc.failed
                          ]
                      }
                  end
              end
          end
        end

        defp extract_project_attrs(raw) do
          %{
            sap_id: parse_integer(raw["sap_id"]),
            doc_num: parse_integer(raw["doc_num"]),
            name: normalize_string(raw["name"]),
            owner_sap_id: parse_integer(raw["owner"]),
            client_id: parse_integer(raw["client_id"]),
            cluster_id: parse_cluster_id(raw),
            is_time_off: parse_boolean(raw["is_time_off"]),
            start_date: parse_date(raw["start_date"]),
            end_date: parse_date(raw["end_date"]),
            status: normalize_string(raw["status"])
          }
          |> Enum.reject(fn {_key, value} -> is_nil(value) end)
          |> Map.new()
        end

        defp build_project_changes(project, attrs) do
          attrs
          |> Map.drop([:doc_num])
          |> Enum.reduce(%{}, fn {key, value}, acc ->
            if Map.get(project, key) != value do
              Map.put(acc, key, value)
            else
              acc
            end
          end)
        end

        defp presentable_changes(changes) do
          Enum.map(changes, fn {field, value} ->
            %{field: to_string(field), new_value: to_string(value)}
          end)
        end

        defp parse_cluster_id(raw) when is_map(raw) do
          raw["cluster_id"] ||
            raw["cluster"] ||
            get_in(raw, ["cluster", "id"])
            |> parse_integer()
        end

        defp parse_cluster_id(_), do: nil

        defp parse_integer(nil), do: nil
        defp parse_integer(value) when is_integer(value), do: value
        defp parse_integer(value) when is_float(value), do: trunc(value)

        defp parse_integer(value) when is_binary(value) do
          case Integer.parse(value) do
            {number, ""} -> number
            _ -> parse_float_string(value)
          end
        end

        defp parse_integer(_), do: nil

        defp parse_float_string(value) do
          case Float.parse(value) do
            {number, ""} -> trunc(number)
            _ -> nil
          end
        end

        defp parse_boolean(nil), do: nil
        defp parse_boolean(value) when is_boolean(value), do: value
        defp parse_boolean(1), do: true
        defp parse_boolean(0), do: false

        defp parse_boolean(value) when is_binary(value) do
          case String.downcase(String.trim(value)) do
            "true" -> true
            "false" -> false
            "1" -> true
            "0" -> false
            _ -> nil
          end
        end

        defp parse_boolean(_), do: nil

        defp normalize_string(nil), do: nil

        defp normalize_string(value) when is_binary(value) do
          case String.trim(value) do
            "" -> nil
            trimmed -> trimmed
          end
        end

        defp normalize_string(value), do: to_string(value)

        defp parse_date(nil), do: nil
        defp parse_date(%Date{} = date), do: date

        defp parse_date(date) when is_binary(date) do
          case Date.from_iso8601(date) do
            {:ok, parsed_date} -> parsed_date
            {:error, _reason} -> nil
          end
        end

        defp parse_date(_), do: nil
        """

        Igniter.Project.Module.create_module(igniter, module, contents)
      end
    end
  end
end
