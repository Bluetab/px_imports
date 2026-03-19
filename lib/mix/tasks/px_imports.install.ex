if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Tasks.PxImports.Install do
    @shortdoc "Adds Oban job admin UI and PX sync workers to an Ash Phoenix project"

    @moduledoc """
    Wires a Phoenix + Ash + Oban project into the PX (Bluetab Connect) ecosystem.

    ## Prerequisites

    - Project created with `ash_authentication_phoenix` and `bluetab_phoenix`
    - `:oban` and `:oban_web` must already be in your `mix.exs` dependencies

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

      * `--org_tree` — generates five Ash resources under `<App>.Projects`
        (BusinessUnit, Cluster, ClientGroup, Client, Initiative) plus
        `SyncOrgTreeWorker` (daily at 03:00)

      * `--projects` — generates `<App>.Projects.Project` Ash resource plus
        `SyncProjectsWorker` (daily at 02:30)

      * `--spend-types` — generates `<App>.Projects.SpendType` Ash resource
        plus `SyncSpendTypesWorker` (daily at 02:45)

      * `--users` — patches `Accounts.User` with employee fields (`sap_id`,
        `join_date`, `hidden_at`) and a `:sync_employee_fields` update action,
        plus `SyncEmployeesWorker` (daily at 02:00)

    ## Usage

        mix px_imports.install --org_tree
        mix px_imports.install --users --projects
        mix px_imports.install --spend-types
        mix px_imports.install --org_tree --users --projects
    """

    use Igniter.Mix.Task

    @impl Igniter.Mix.Task
    def info(_argv, _composing_task) do
      %Igniter.Mix.Task.Info{
        group: :px_imports,
        example: "mix px_imports.install --org_tree --users",
        schema: [
          users: :boolean,
          projects: :boolean,
          org_tree: :boolean,
          spend_types: :boolean
        ]
      }
    end

    @impl Igniter.Mix.Task
    def igniter(igniter) do
      opts = igniter.args.options
      install_org_tree? = Keyword.get(opts, :org_tree, false)
      install_users? = Keyword.get(opts, :users, false)
      install_projects? = Keyword.get(opts, :projects, false)
      install_spend_types? = Keyword.get(opts, :spend_types, false)

      if not (install_org_tree? or install_users? or install_projects? or install_spend_types?) do
        Igniter.add_issue(igniter, """
        At least one of --org_tree, --users, --projects, or --spend-types must be specified.

        Examples:
          mix px_imports.install --org_tree
          mix px_imports.install --users --projects
          mix px_imports.install --spend-types
          mix px_imports.install --org_tree --users --projects
        """)
      else
        prefix = Igniter.Project.Module.module_name_prefix(igniter)

        otp_app =
          prefix |> Module.split() |> List.last() |> Macro.underscore() |> String.to_atom()

        web_module = :"#{prefix}Web"

        router_module = Module.concat(web_module, Router)
        live_user_auth_module = Module.concat(web_module, LiveUserAuth)
        repo_module = Module.concat(prefix, Repo)
        user_resource_module = Module.concat([prefix, Accounts, User])

        jobs_module = Module.concat(prefix, Jobs)
        admin_live_module = Module.concat(web_module, AdminLive)
        jobs_live_module = Module.concat([web_module, Admin, JobsLive])
        job_show_live_module = Module.concat([web_module, Admin, JobShowLive])

        projects_domain_module = Module.concat(prefix, Projects)
        sync_org_tree_worker_module = Module.concat([prefix, Workers, SyncOrgTreeWorker])
        sync_employees_worker_module = Module.concat([prefix, Workers, SyncEmployeesWorker])
        sync_projects_worker_module = Module.concat([prefix, Workers, SyncProjectsWorker])
        sync_spend_types_worker_module = Module.concat([prefix, Workers, SyncSpendTypesWorker])

        cron_entries =
          []
          |> then(fn e ->
            if install_users?,
              do: e ++ [{"0 2 * * *", sync_employees_worker_module}],
              else: e
          end)
          |> then(fn e ->
            if install_projects?,
              do: e ++ [{"30 2 * * *", sync_projects_worker_module}],
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

        org_tree_resources =
          if install_org_tree? do
            [
              Module.concat([prefix, Projects, BusinessUnit]),
              Module.concat([prefix, Projects, Cluster]),
              Module.concat([prefix, Projects, ClientGroup]),
              Module.concat([prefix, Projects, Client]),
              Module.concat([prefix, Projects, Initiative])
            ]
          else
            []
          end

        project_resources =
          []
          |> then(fn resources ->
            if install_projects?,
              do: resources ++ [Module.concat([prefix, Projects, Project])],
              else: resources
          end)
          |> then(fn resources ->
            if install_spend_types?,
              do: resources ++ [Module.concat([prefix, Projects, SpendType])],
              else: resources
          end)

        all_project_resources = org_tree_resources ++ project_resources

        domains_to_add =
          if install_org_tree? or install_projects? or install_spend_types?,
            do: [projects_domain_module],
            else: []

        igniter
        |> check_oban_present()
        |> setup_oban_config(otp_app, repo_module, cron_entries)
        |> update_ash_domains_config(otp_app, domains_to_add)
        |> create_jobs_context(jobs_module, repo_module, otp_app)
        |> create_admin_live(admin_live_module, web_module, live_user_auth_module)
        |> create_jobs_live(jobs_live_module, web_module, live_user_auth_module, jobs_module)
        |> create_job_show_live(
          job_show_live_module,
          web_module,
          live_user_auth_module,
          jobs_module
        )
        |> update_router(router_module, live_user_auth_module)
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
            |> create_initiative(
              Module.concat([prefix, Projects, Initiative]),
              projects_domain_module,
              repo_module
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
          if install_projects? do
            ign
            |> then(fn i ->
              if install_org_tree? do
                i
              else
                create_projects_domain(i, projects_domain_module, all_project_resources, otp_app)
              end
            end)
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
          else
            ign
          end
        end)
        |> then(fn ign ->
          if install_spend_types? do
            spend_type_module = Module.concat([prefix, Projects, SpendType])

            ign
            |> then(fn i ->
              if install_org_tree? or install_projects? do
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

        6. To install spend type sync only:

             mix px_imports.install --spend-types
        """)
      end
    end

    # ──────────────────────────────────────────────
    # Validation & environment checks
    # ──────────────────────────────────────────────

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

          crontab_lines =
            cron_entries
            |> Enum.map(fn {cron, worker} ->
              ~s|       {"#{cron}", #{inspect(worker)}}|
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
                  ~r/\{Oban\.Plugins\.Cron,\s*crontab:\s*\[.*?\]\s*\}/s,
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

    defp create_admin_live(igniter, admin_live_module, web_module, live_user_auth_module) do
      jobs_card = ~S"""
              <.link
                navigate={~p"/admin/jobs"}
                class="rounded-xl border border-base-300 p-5 hover:bg-base-200/40 transition-colors"
              >
                <div class="flex items-center gap-2 font-semibold">
                  <.icon name="hero-cog-6-tooth" class="w-5 h-5" /> Jobs
                </div>
                <p class="mt-2 text-sm text-base-content/70">
                  Manage scheduled Oban jobs and inspect recent runs.
                </p>
              </.link>
      """

      full_contents = """
      use #{inspect(web_module)}, :live_view

      on_mount {#{inspect(live_user_auth_module)}, :live_admin_required}

      @impl true
      def mount(_params, _session, socket) do
        {:ok, socket}
      end

      @impl true
      def render(assigns) do
        ~H\"\"\"
        <Layouts.app flash={@flash} current_user={@current_user}>
          <div class="mx-auto max-w-3xl">
            <h1 class="text-4xl font-bold">Admin Dashboard</h1>
            <p class="mt-3 text-base-content/70">
              Admin-only tools and maintenance views.
            </p>

            <div class="mt-8 grid gap-4 sm:grid-cols-2">
      #{String.trim_trailing(jobs_card)}
            </div>
          </div>
        </Layouts.app>
        \"\"\"
      end
      """

      {exists?, igniter} = Igniter.Project.Module.module_exists(igniter, admin_live_module)

      if exists? do
        # Module already exists (e.g. created by bluetab_phoenix). Inject the jobs card
        # into the render if it isn't there yet.
        case Igniter.Project.Module.find_module(igniter, admin_live_module) do
          {:ok, {igniter, source, _zipper}} ->
            path = Rewrite.Source.get(source, :path)

            Igniter.update_file(igniter, path, fn source ->
              content = Rewrite.Source.get(source, :content)

              if String.contains?(content, ~s|navigate={~p"/admin/jobs"}|) do
                source
              else
                # Replace the render function body with one that includes the jobs card.
                new_content =
                  Regex.replace(
                    ~r/(def render\(assigns\) do\s*~H""")(.*?)("""(\s*)end)/s,
                    content,
                    fn _, open, _old_body, close, _ ->
                      new_body = """

                      <Layouts.app flash={@flash} current_user={@current_user}>
                        <div class="mx-auto max-w-3xl">
                          <h1 class="text-4xl font-bold">Admin Dashboard</h1>
                          <p class="mt-3 text-base-content/70">
                            Admin-only tools and maintenance views.
                          </p>

                          <div class="mt-8 grid gap-4 sm:grid-cols-2">
                      #{String.trim_trailing(jobs_card)}
                          </div>
                        </div>
                      </Layouts.app>
                      """

                      open <> new_body <> close
                    end,
                    global: false
                  )

                Rewrite.Source.update(source, :content, new_content)
              end
            end)

          {:error, igniter} ->
            Igniter.add_warning(
              igniter,
              "Could not find #{inspect(admin_live_module)} to patch. Jobs card not added."
            )
        end
      else
        Igniter.Project.Module.create_module(igniter, admin_live_module, full_contents)
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
        contents = """
        use #{inspect(web_module)}, :live_view

        on_mount {#{inspect(live_user_auth_module)}, :live_admin_required}

        alias #{inspect(jobs_module)}

        @impl true
        def mount(_params, _session, socket) do
          {:ok,
           socket
           |> assign(:page_title, "Jobs")
           |> assign_jobs()}
        end

        @impl true
        def handle_event("run_job", %{"worker" => worker_module_string}, socket) do
          worker_module = String.to_existing_atom("Elixir." <> worker_module_string)

          case Jobs.run_job_now(worker_module) do
            {:ok, _job} ->
              {:noreply,
               socket
               |> put_flash(:info, "Job \#{worker_module_string} enqueued successfully.")
               |> assign_jobs()}

            {:error, _changeset} ->
              {:noreply, put_flash(socket, :error, "Failed to enqueue job.")}
          end
        end

        @impl true
        def handle_event("refresh", _params, socket) do
          {:noreply, assign_jobs(socket)}
        end

        @impl true
        def render(assigns) do
          ~H\"\"\"
          <Layouts.app flash={@flash} current_user={@current_user}>
            <div class="space-y-10">
              <section>
                <.header>
                  Scheduled Jobs
                  <:subtitle>Cron jobs configured to run automatically</:subtitle>
                </.header>

                <div class="mt-6 overflow-hidden rounded-xl border border-base-300">
                  <table class="table w-full">
                    <thead>
                      <tr>
                        <th>Worker</th>
                        <th>Schedule</th>
                        <th class="text-right">Actions</th>
                      </tr>
                    </thead>
                    <tbody>
                      <tr :for={job <- @scheduled_jobs} id={"scheduled-job-\#{job.worker}"}>
                        <td class="font-semibold">{job.worker}</td>
                        <td><code>{job.cron}</code></td>
                        <td class="text-right">
                          <.button
                            phx-click="run_job"
                            phx-value-worker={inspect(job.worker_module) |> String.trim_leading("Elixir.")}
                            data-confirm={"Run \#{job.worker} now?"}
                          >
                            <.icon name="hero-play-solid" class="w-4 h-4 mr-1" /> Run now
                          </.button>
                        </td>
                      </tr>
                    </tbody>
                  </table>
                </div>
              </section>

              <section>
                <.header>
                  Recent Job Runs
                  <:subtitle>History of Oban job executions</:subtitle>
                  <:actions>
                    <.button id="jobs-refresh-button" phx-click="refresh">
                      <.icon name="hero-arrow-path" class="w-4 h-4 mr-1" /> Refresh
                    </.button>
                  </:actions>
                </.header>

                <div class="mt-6 overflow-hidden rounded-xl border border-base-300">
                  <table class="table w-full">
                    <thead>
                      <tr>
                        <th>ID</th>
                        <th>Worker</th>
                        <th>State</th>
                        <th>Queue</th>
                        <th>Attempt</th>
                        <th>Inserted</th>
                        <th>Completed</th>
                      </tr>
                    </thead>
                    <tbody>
                      <tr
                        :for={job <- @recent_jobs}
                        id={"job-row-\#{job.id}"}
                        class="cursor-pointer hover:bg-base-200/40 transition-colors"
                        phx-click={JS.navigate(~p"/admin/jobs/\#{job.id}")}
                      >
                        <td class="font-mono text-xs">{job.id}</td>
                        <td class="font-semibold">{short_worker_name(job.worker)}</td>
                        <td>{job.state}</td>
                        <td>{job.queue}</td>
                        <td>{job.attempt}/{job.max_attempts}</td>
                        <td class="text-xs">{format_datetime(job.inserted_at)}</td>
                        <td class="text-xs">{format_datetime(job.completed_at)}</td>
                      </tr>
                    </tbody>
                  </table>
                  <p :if={@recent_jobs == []} class="text-center text-base-content/70 py-8">
                    No jobs have been executed yet.
                  </p>
                </div>
              </section>
            </div>
          </Layouts.app>
          \"\"\"
        end

        defp assign_jobs(socket) do
          socket
          |> assign(:scheduled_jobs, Jobs.list_scheduled_jobs())
          |> assign(:recent_jobs, Jobs.list_recent_jobs())
        end

        defp short_worker_name(worker) when is_binary(worker) do
          worker
          |> String.split(".")
          |> List.last()
        end

        defp format_datetime(nil), do: "-"

        defp format_datetime(datetime) do
          Calendar.strftime(datetime, "%Y-%m-%d %H:%M:%S")
        end
        """

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
        contents = """
        use #{inspect(web_module)}, :live_view

        on_mount {#{inspect(live_user_auth_module)}, :live_admin_required}

        alias #{inspect(jobs_module)}

        @impl true
        def mount(%{"id" => id}, _session, socket) do
          job = Jobs.get_job!(String.to_integer(id))

          {:ok,
           socket
           |> assign(:page_title, "Job #\#{job.id}")
           |> assign(:job, job)}
        end

        @impl true
        def render(assigns) do
          ~H\"\"\"
          <Layouts.app flash={@flash} current_user={@current_user}>
            <div class="space-y-8">
              <div class="flex items-center justify-between gap-4">
                <div>
                  <h1 class="text-2xl font-bold">Job #{"#\#{@job.id}"}</h1>
                  <p class="text-sm text-base-content/70">{@job.worker}</p>
                </div>
                <.link navigate={~p"/admin/jobs"} class="btn btn-sm btn-ghost">
                  <.icon name="hero-arrow-left" class="w-4 h-4 mr-1" /> Back
                </.link>
              </div>

              <div class="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
                <div class="rounded-xl border border-base-300 p-4">
                  <p class="text-xs uppercase text-base-content/70">State</p>
                  <p class="mt-1 text-lg font-semibold">{@job.state}</p>
                </div>
                <div class="rounded-xl border border-base-300 p-4">
                  <p class="text-xs uppercase text-base-content/70">Queue</p>
                  <p class="mt-1 text-lg font-semibold">{@job.queue}</p>
                </div>
                <div class="rounded-xl border border-base-300 p-4">
                  <p class="text-xs uppercase text-base-content/70">Attempts</p>
                  <p class="mt-1 text-lg font-semibold">{@job.attempt}/{@job.max_attempts}</p>
                </div>
                <div class="rounded-xl border border-base-300 p-4">
                  <p class="text-xs uppercase text-base-content/70">Inserted</p>
                  <p class="mt-1 text-sm font-semibold">{format_datetime(@job.inserted_at)}</p>
                </div>
              </div>

              <div class="rounded-xl border border-base-300 p-4">
                <h2 class="font-semibold">Args</h2>
                <pre class="mt-2 text-xs overflow-x-auto"><%= inspect(@job.args, pretty: true, limit: :infinity) %></pre>
              </div>

              <div class="rounded-xl border border-base-300 p-4">
                <h2 class="font-semibold">Meta</h2>
                <div :if={@job.meta in [%{}, nil]} class="mt-2 text-sm text-base-content/70">
                  No metadata recorded for this job.
                </div>

                <div :if={@job.meta not in [%{}, nil]} class="mt-3 space-y-4">
                  <div class="grid gap-3 sm:grid-cols-2 lg:grid-cols-6">
                    <.meta_stat_card label="Total records" value={meta_total(@job.meta)} />
                    <.meta_stat_card label="Created" value={meta_count(@job.meta, "created_count")} />
                    <.meta_stat_card label="Updated" value={meta_count(@job.meta, "updated_count")} />
                    <.meta_stat_card label="Skipped" value={meta_count(@job.meta, "skipped_count")} />
                    <.meta_stat_card label="Not found" value={meta_count(@job.meta, "not_found_count")} />
                    <.meta_stat_card label="Failed" value={meta_count(@job.meta, "failed_count")} />
                  </div>

                  <p :if={@job.meta["completed_at"]} class="text-xs text-base-content/70">
                    Completed at: {format_iso_datetime(@job.meta["completed_at"])}
                  </p>

                  <details class="rounded-lg border border-base-300 p-3">
                    <summary class="cursor-pointer font-medium">Created records</summary>
                    <div class="mt-3 space-y-1">
                      <p :if={meta_created(@job.meta) == []} class="text-sm text-base-content/70">
                        No created records.
                      </p>
                      <div
                        :for={{item, index} <- Enum.with_index(meta_created(@job.meta), 1)}
                        id={"meta-created-\#{index}"}
                        class="rounded-lg border border-info/30 bg-info/5 p-3 text-sm"
                      >
                        <p class="font-semibold">{item["name"] || item[:name] || "Unnamed"}</p>
                        <p class="text-xs text-base-content/70">
                          SAP ID: {item["sap_id"] || item[:sap_id] || "-"}
                        </p>
                      </div>
                    </div>
                  </details>

                  <details class="rounded-lg border border-base-300 p-3">
                    <summary class="cursor-pointer font-medium">Updated records</summary>
                    <div class="mt-3 space-y-2">
                      <p :if={meta_updated(@job.meta) == []} class="text-sm text-base-content/70">
                        No updated records.
                      </p>
                      <div
                        :for={{item, index} <- Enum.with_index(meta_updated(@job.meta), 1)}
                        id={"meta-updated-\#{index}"}
                        class="rounded-lg border border-success/30 bg-success/5 p-3"
                      >
                        <p class="text-sm font-semibold">{item["email"] || item["name"] || "Unknown"}</p>
                        <ul class="mt-2 space-y-1 text-xs">
                          <li :for={change <- item["changes"] || []}>
                            <span class="font-semibold">{change["field"]}:</span> {change["new_value"]}
                          </li>
                        </ul>
                      </div>
                    </div>
                  </details>

                  <details class="rounded-lg border border-base-300 p-3">
                    <summary class="cursor-pointer font-medium">Skipped records</summary>
                    <div class="mt-3 space-y-1">
                      <p :if={meta_skipped(@job.meta) == []} class="text-sm text-base-content/70">
                        No skipped records.
                      </p>
                      <p :for={item <- meta_skipped(@job.meta)} class="text-sm">
                        {meta_item_label(item)}
                      </p>
                    </div>
                  </details>

                  <details class="rounded-lg border border-base-300 p-3">
                    <summary class="cursor-pointer font-medium">Not found records</summary>
                    <div class="mt-3 space-y-1">
                      <p :if={meta_not_found(@job.meta) == []} class="text-sm text-base-content/70">
                        No not-found records.
                      </p>
                      <p :for={item <- meta_not_found(@job.meta)} class="text-sm">
                        {meta_item_label(item)}
                      </p>
                    </div>
                  </details>

                  <details class="rounded-lg border border-base-300 p-3">
                    <summary class="cursor-pointer font-medium">Failed records</summary>
                    <div class="mt-3 space-y-2">
                      <p :if={meta_failed(@job.meta) == []} class="text-sm text-base-content/70">
                        No failed records.
                      </p>
                      <div
                        :for={{item, index} <- Enum.with_index(meta_failed(@job.meta), 1)}
                        id={"meta-failed-\#{index}"}
                        class="rounded-lg border border-error/30 bg-error/5 p-3"
                      >
                        <p class="text-xs font-semibold">
                          SAP ID: {item["sap_id"] || item[:sap_id] || "-"}
                        </p>
                        <pre class="mt-2 overflow-x-auto whitespace-pre-wrap break-words text-xs leading-5"><%= item["error"] || item[:error] || inspect(item) %></pre>
                      </div>
                    </div>
                  </details>

                  <details class="rounded-lg border border-base-300 p-3">
                    <summary class="cursor-pointer font-medium">Raw metadata</summary>
                    <pre class="mt-3 text-xs overflow-x-auto"><%= inspect(@job.meta, pretty: true, limit: :infinity) %></pre>
                  </details>
                </div>
              </div>

              <div class="rounded-xl border border-base-300 p-4">
                <h2 class="font-semibold">Errors</h2>
                <div :if={@job.errors == []} class="mt-2 text-sm text-base-content/70">
                  No errors recorded for this job.
                </div>
                <div :if={@job.errors != []} class="mt-3 space-y-3">
                  <div
                    :for={{error, index} <- Enum.with_index(@job.errors, 1)}
                    id={"job-error-\#{index}"}
                    class="rounded-lg border border-error/30 bg-error/5 p-4"
                  >
                    <div class="flex flex-wrap items-center gap-x-4 gap-y-1">
                      <p class="text-sm font-semibold text-error">Attempt {error_attempt(error)}</p>
                      <p class="text-xs text-base-content/70">
                        {format_iso_datetime(error["at"])}
                      </p>
                    </div>
                    <pre class="mt-3 overflow-x-auto whitespace-pre-wrap break-words text-xs leading-5"><%= error_message(error) %></pre>
                  </div>
                </div>
              </div>
            </div>
          </Layouts.app>
          \"\"\"
        end

        defp format_datetime(nil), do: "-"

        defp format_datetime(datetime) do
          Calendar.strftime(datetime, "%Y-%m-%d %H:%M:%S")
        end

        defp format_iso_datetime(nil), do: "-"

        defp format_iso_datetime(value) when is_binary(value) do
          case DateTime.from_iso8601(value) do
            {:ok, datetime, _offset} -> format_datetime(datetime)
            _ -> value
          end
        end

        defp format_iso_datetime(value), do: inspect(value)

        defp error_attempt(%{"attempt" => attempt}), do: attempt
        defp error_attempt(_), do: "-"

        defp error_message(%{"error" => error}) when is_binary(error), do: error
        defp error_message(error), do: inspect(error, pretty: true, limit: :infinity)

        attr :label, :string, required: true
        attr :value, :any, required: true

        defp meta_stat_card(assigns) do
          ~H\"\"\"
          <div class="rounded-lg border border-base-300 p-3">
            <p class="text-xs uppercase text-base-content/70">{@label}</p>
            <p class="mt-1 text-xl font-semibold">{@value}</p>
          </div>
          \"\"\"
        end

        defp meta_total(meta) do
          if org_tree_meta?(meta) do
            stage_count(meta, "total")
          else
            meta_get(meta, "total_employees", meta_get(meta, "total_projects", 0))
          end
        end

        defp meta_count(meta, key) do
          if org_tree_meta?(meta) do
            stage_count(meta, key)
          else
            meta_get(meta, key, 0)
          end
        end

        defp meta_created(meta), do: meta_list(meta, "created")
        defp meta_updated(meta), do: meta_list(meta, "updated")
        defp meta_skipped(meta), do: meta_list(meta, "skipped")
        defp meta_not_found(meta), do: meta_list(meta, "not_found")
        defp meta_failed(meta), do: meta_list(meta, "failed")

        defp meta_item_label(item) when is_binary(item), do: item

        defp meta_item_label(item) when is_map(item) do
          item["email"] || item["name"] || item["sap_id"] || inspect(item)
        end

        defp meta_item_label(item), do: to_string(item)

        defp org_tree_meta?(meta) do
          Enum.any?(stage_keys(), fn stage ->
            stage_data = meta_get(meta, stage, %{})
            is_map(stage_data) and stage_data != %{}
          end)
        end

        defp stage_keys do
          ["business_units", "clusters", "client_groups", "clients", "initiatives"]
        end

        defp stage_count(meta, key) do
          Enum.reduce(stage_keys(), 0, fn stage, acc ->
            stage_data = meta_get(meta, stage, %{})
            acc + meta_get(stage_data, key, 0)
          end)
        end

        defp meta_list(meta, key) do
          if org_tree_meta?(meta) do
            Enum.flat_map(stage_keys(), fn stage ->
              stage_data = meta_get(meta, stage, %{})
              Enum.map(meta_get(stage_data, key, []), fn item -> attach_stage(item, stage) end)
            end)
          else
            meta_get(meta, key, [])
          end
        end

        defp attach_stage(item, stage) when is_map(item), do: Map.put_new(item, "stage", stage)
        defp attach_stage(item, _stage), do: item

        defp meta_get(nil, _key, default), do: default

        defp meta_get(map, key, default) when is_map(map) and is_binary(key) do
          atom_key =
            try do
              String.to_existing_atom(key)
            rescue
              ArgumentError -> nil
            end

          case atom_key do
            nil -> Map.get(map, key, default)
            _ -> Map.get(map, key, Map.get(map, atom_key, default))
          end
        end
        """

        Igniter.Project.Module.create_module(igniter, job_show_live_module, contents)
      end
    end

    # ──────────────────────────────────────────────
    # Router: admin routes + oban dashboard
    # ──────────────────────────────────────────────

    defp update_router(igniter, router_module, live_user_auth_module) do
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

    defp create_initiative(igniter, module, domain_module, repo_module) do
      {exists?, igniter} = Igniter.Project.Module.module_exists(igniter, module)

      if exists? do
        igniter
      else
        client_module = Module.concat(domain_module, Client)

        contents = """
        use Ash.Resource,
          domain: #{inspect(domain_module)},
          data_layer: AshPostgres.DataLayer,
          authorizers: [Ash.Policy.Authorizer]

        postgres do
          table "initiatives"
          repo #{inspect(repo_module)}
        end

        actions do
          defaults [:read]

          create :create do
            primary? true
            accept [
              :initiative_key, :summary, :description, :scope, :goals,
              :client_id, :needs_px, :delivery_manager, :delivery_manager_sap_id,
              :sap_project_ids, :start_date, :end_date, :hidden_at
            ]
          end

          update :sync_from_px do
            accept [
              :summary, :description, :scope, :goals, :client_id, :needs_px,
              :delivery_manager, :delivery_manager_sap_id, :sap_project_ids,
              :start_date, :end_date, :hidden_at
            ]
          end
        end

        policies do
          bypass always() do
            authorize_if always()
          end
        end

        attributes do
          attribute :initiative_key, :string do
            primary_key? true
            allow_nil? false
            public? true
          end

          attribute :summary, :string do
            allow_nil? false
            public? true
          end

          attribute :description, :string do
            public? true
          end

          attribute :scope, :string do
            public? true
          end

          attribute :goals, :string do
            public? true
          end

          attribute :client_id, :integer do
            allow_nil? false
            public? true
          end

          attribute :needs_px, :boolean do
            public? true
          end

          attribute :delivery_manager, :string do
            public? true
          end

          attribute :delivery_manager_sap_id, :integer do
            public? true
          end

          attribute :sap_project_ids, {:array, :integer} do
            public? true
          end

          attribute :start_date, :utc_datetime do
            public? true
          end

          attribute :end_date, :utc_datetime do
            public? true
          end

          attribute :hidden_at, :utc_datetime do
            public? true
          end
        end

        relationships do
          belongs_to :client, #{inspect(client_module)} do
            source_attribute :client_id
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
        initiative_module = Module.concat(domain_module, Initiative)

        contents = """
        @moduledoc \"\"\"
        Synchronizes PX organizational tree entities in dependency order.
        \"\"\"

        use Oban.Worker, queue: :default, max_attempts: 3

        alias #{inspect(domain_module)}
        alias #{inspect(bu_module)}
        alias #{inspect(cluster_module)}
        alias #{inspect(cg_module)}
        alias #{inspect(client_module)}
        alias #{inspect(initiative_module)}
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
              initiatives: initiatives
            }) do
          {:ok,
           %{}
           |> Map.put(:business_units, sync_business_units(business_units))
           |> Map.put(:clusters, sync_clusters(clusters))
           |> Map.put(:client_groups, sync_client_groups(client_groups))
           |> Map.put(:clients, sync_clients(clients))
           |> Map.put(:initiatives, sync_initiatives(initiatives))}
        end

        defp run_sync do
          with {:ok, business_units} <- BluetabConnect.Px.Rest.list_business_units(),
               {:ok, clusters} <- BluetabConnect.Px.Rest.list_clusters(),
               {:ok, client_groups} <- BluetabConnect.Px.Rest.list_client_groups(),
               {:ok, clients} <- BluetabConnect.Px.Rest.list_clients(),
               {:ok, initiatives} <- BluetabConnect.Px.Rest.list_initiatives(),
               {:ok, summary} <-
                 execute(%{
                   business_units: business_units,
                   clusters: clusters,
                   client_groups: client_groups,
                   clients: clients,
                   initiatives: initiatives
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

        defp sync_initiatives(items) do
          sync_resource(:initiatives, Initiative, items, :initiative_key, &map_initiative/1)
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

        defp map_initiative(raw) do
          %{
            initiative_key: normalize_string(raw["initiative_key"]),
            summary: normalize_string(raw["summary"]),
            description: normalize_string(raw["description"]),
            scope: normalize_string(raw["scope"]),
            goals: normalize_string(raw["goals"]),
            client_id: parse_integer(raw["client_id"]),
            needs_px: raw["needs_px"],
            delivery_manager: normalize_string(raw["delivery_manager"]),
            delivery_manager_sap_id: parse_integer(raw["delivery_manager_sap_id"]),
            sap_project_ids: parse_integer_list(raw["sap_project_ids"]),
            start_date: parse_datetime(raw["startDate"]),
            end_date: parse_datetime(raw["endDate"])
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

        defp parse_integer_list(nil), do: nil

        defp parse_integer_list(list) when is_list(list) do
          list
          |> Enum.map(&parse_integer/1)
          |> Enum.reject(&is_nil/1)
        end

        defp parse_integer_list(_), do: nil

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
      |> Ash.Resource.Igniter.add_new_action(
        user_module,
        :sync_employee_fields,
        """
        update :sync_employee_fields do
          accept [:join_date, :hidden_at, :sap_id]
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

        contents = """
        @moduledoc \"\"\"
        Synchronizes PX employee data into Accounts.User records.

        Matches employees to existing users by email address and updates
        employee fields (sap_id, join_date, hidden_at from termination_date).
        \"\"\"

        use Oban.Worker, queue: :default, max_attempts: 3

        import Ecto.Query

        alias #{inspect(user_module)}
        alias #{inspect(repo_module)}

        @impl Oban.Worker
        def perform(job) do
          with {:ok, employees} <- BluetabConnect.Px.Rest.list_employees() do
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
          emails = Enum.map(employees, & &1["email"])

          users_by_email =
            from(u in User, where: u.email in ^emails)
            |> Repo.all()
            |> Map.new(&{&1.email, &1})

          results =
            Enum.reduce(employees, %{updated: [], skipped: [], not_found: []}, fn employee, acc ->
              case Map.get(users_by_email, employee["email"]) do
                nil ->
                  %{acc | not_found: [employee["email"] | acc.not_found]}

                user ->
                  case maybe_update_user(user, employee) do
                    {:updated, changes} ->
                      %{acc | updated: [%{email: user.email, changes: changes} | acc.updated]}

                    :no_changes ->
                      %{acc | skipped: [user.email | acc.skipped]}
                  end
              end
            end)

          %{
            total_employees: length(employees),
            updated_count: length(results.updated),
            skipped_count: length(results.skipped),
            not_found_count: length(results.not_found),
            updated: Enum.reverse(results.updated),
            skipped: Enum.reverse(results.skipped),
            not_found: Enum.reverse(results.not_found)
          }
        end

        defp maybe_update_user(user, employee) do
          attrs = build_update_attrs(user, employee)

          if map_size(attrs) > 0 do
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
        end

        defp maybe_put_join_date(attrs, user, employee) do
          case {user.join_date, employee["start_date"]} do
            {nil, start_date} when is_binary(start_date) ->
              Map.put(attrs, :join_date, Date.from_iso8601!(start_date))

            _ ->
              attrs
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
          sap_id = parse_sap_id(employee["sap_employee_number"])

          cond do
            is_nil(sap_id) -> attrs
            user.sap_id != sap_id -> Map.put(attrs, :sap_id, sap_id)
            true -> attrs
          end
        end

        defp parse_termination_date(nil), do: nil

        defp parse_termination_date(date_string) when is_binary(date_string) do
          date_string
          |> Date.from_iso8601!()
          |> DateTime.new!(~T[00:00:00], "Etc/UTC")
        end

        defp parse_sap_id(nil), do: nil
        defp parse_sap_id(value) when is_integer(value), do: value

        defp parse_sap_id(value) when is_binary(value) do
          case Integer.parse(value) do
            {number, ""} -> number
            _ -> nil
          end
        end

        defp parse_sap_id(_), do: nil

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
    # Projects: Project resource + SyncProjectsWorker
    # ──────────────────────────────────────────────

    defp create_project_resource(igniter, module, domain_module, repo_module) do
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
          table "projects"
          repo #{inspect(repo_module)}
        end

        actions do
          defaults [:read]

          create :create do
            primary? true
            accept [:sap_id, :doc_num, :name, :start_date, :end_date, :status]
          end

          update :sync_from_px do
            accept [:sap_id, :name, :start_date, :end_date, :status]
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
          case BluetabConnect.Px.Rest.list_projects(page: page, per_page: 100) do
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
