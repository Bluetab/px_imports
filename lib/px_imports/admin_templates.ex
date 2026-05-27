defmodule PxImports.AdminTemplates do
  @moduledoc false

  @doc """
  HEEx body for `AdminLive` (inside `<Layouts.app>`).
  Requires `import Bds.Components` and `import Bds.Components.CatalogUi` in the host app.
  """
  def admin_live_render(include_users?) do
    users_card =
      if include_users? do
        """
              <.admin_nav_card
                navigate={~p"/admin/users"}
                icon="hero-users"
                title="Users"
                description="Manage admin access and impersonation."
              />
        """
      else
        ""
      end

    """
          <.bt_header>
            Admin Dashboard
            <:subtitle>Admin-only tools and maintenance views.</:subtitle>
          </.bt_header>

          <div style="margin-top: var(--bt-space-6); max-width: 52rem;">
            <.bt_example_grid>
              <.admin_nav_card
                navigate={~p"/admin/jobs"}
                icon="hero-cog-6-tooth"
                title="Jobs"
                description="Manage scheduled Oban jobs and inspect recent runs."
              />
    #{users_card}
            </.bt_example_grid>
          </div>
    """
  end

  def admin_live_module(web_module, live_user_auth_module, include_users?) do
    """
    use #{inspect(web_module)}, :live_view

    on_mount {#{inspect(live_user_auth_module)}, :live_admin_required}

    @impl true
    def mount(_params, _session, socket) do
      {:ok, socket}
    end

    @impl true
    def render(assigns) do
      ~H\"\"\"
      <Layouts.app
        flash={@flash}
        current_user={@current_user}
        current_path={assigns[:current_path] || "/"}
        impersonator={assigns[:impersonator]}
      >
    #{admin_live_render(include_users?)}
      </Layouts.app>
      \"\"\"
    end

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
  end

  def jobs_live_module(web_module, live_user_auth_module, jobs_module) do
    """
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
      <Layouts.app
        flash={@flash}
        current_user={@current_user}
        current_path={assigns[:current_path] || "/"}
        impersonator={assigns[:impersonator]}
      >
        <div class="bt-stack" style="gap: var(--bt-space-10);">
          <.bt_section title="Scheduled Jobs" description="Cron jobs configured to run automatically">
            <.bt_table id="scheduled-jobs" rows={@scheduled_jobs} row_id={fn job -> "scheduled-job-\#{job.worker}" end}>
              <:col :let={job} label="Worker">
                <strong>{job.worker}</strong>
              </:col>
              <:col :let={job} label="Schedule">
                <.bt_code>{job.cron}</.bt_code>
              </:col>
              <:action :let={job}>
                <.bt_button
                  class="bt-button--sm"
                  phx-click="run_job"
                  phx-value-worker={inspect(job.worker_module) |> String.trim_leading("Elixir.")}
                  data-confirm={"Run \#{job.worker} now?"}
                >
                  <.icon name="hero-play-solid" class="size-4" /> Run
                </.bt_button>
              </:action>
            </.bt_table>
          </.bt_section>

          <.bt_section title="Recent Job Runs" description="History of Oban job executions">
            <:actions>
              <.bt_button id="jobs-refresh-button" variant="secondary" phx-click="refresh">
                <.icon name="hero-arrow-path" class="size-4" /> Refresh
              </.bt_button>
            </:actions>
            <p :if={@recent_jobs == []} class="bt-muted">No jobs have been executed yet.</p>
            <.bt_table
              :if={@recent_jobs != []}
              id="recent-jobs"
              rows={@recent_jobs}
              row_id={fn job -> "job-row-\#{job.id}" end}
              row_click={fn job -> JS.navigate(~p"/admin/jobs/\#{job.id}") end}
            >
              <:col :let={job} label="ID">
                <.bt_code>{job.id}</.bt_code>
              </:col>
              <:col :let={job} label="Worker">
                <strong>{short_worker_name(job.worker)}</strong>
              </:col>
              <:col :let={job} label="State">{job.state}</:col>
              <:col :let={job} label="Queue">{job.queue}</:col>
              <:col :let={job} label="Attempt">{job.attempt}/{job.max_attempts}</:col>
              <:col :let={job} label="Inserted">{format_datetime(job.inserted_at)}</:col>
              <:col :let={job} label="Completed">{format_datetime(job.completed_at)}</:col>
            </.bt_table>
          </.bt_section>
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
  end

  def job_show_live_module(web_module, live_user_auth_module, jobs_module) do
    File.read!(job_show_template_path())
    |> String.replace("__WEB_MODULE__", inspect(web_module))
    |> String.replace("__LIVE_USER_AUTH_MODULE__", inspect(live_user_auth_module))
    |> String.replace("__JOBS_MODULE__", inspect(jobs_module))
  end

  def users_live_module(web_module, live_user_auth_module, accounts_module, user_module) do
    File.read!(users_live_template_path())
    |> String.replace("__WEB_MODULE__", inspect(web_module))
    |> String.replace("__LIVE_USER_AUTH_MODULE__", inspect(live_user_auth_module))
    |> String.replace("__ACCOUNTS_MODULE__", inspect(accounts_module))
    |> String.replace("__USER_MODULE__", inspect(user_module))
  end

  def impersonation_banner_fn do
    """
      attr :impersonator, :map, required: true
      attr :current_user, :map, required: true
      attr :current_path, :string, default: "/"

      defp impersonation_banner(assigns) do
        ~H\"\"\"
        <div
          class="bt-row"
          style="justify-content: space-between; gap: var(--bt-space-3); padding: var(--bt-space-2) var(--bt-space-4); border-bottom: 1px solid var(--bt-color-warning); background: color-mix(in srgb, var(--bt-color-warning) 12%, transparent);"
        >
          <span>
            Impersonating <strong>{@current_user.email}</strong>
            as <strong>{@impersonator.email}</strong>
          </span>
          <.bt_button
            variant="outline"
            class="bt-button--sm"
            href={~p"/admin/impersonation/stop?\#{[return_to: @current_path]}"}
          >
            Stop impersonating
          </.bt_button>
        </div>
        \"\"\"
      end

    """
  end

  defp job_show_template_path do
    template_path("job_show_live.ex")
  end

  defp users_live_template_path do
    template_path("users_live.ex")
  end

  defp template_path(name) do
    priv = Path.join(:code.priv_dir(:px_imports), "templates/admin/#{name}")

    if File.exists?(priv) do
      priv
    else
      Path.join([__DIR__, "..", "..", "priv", "templates", "admin", name])
    end
  end
end
