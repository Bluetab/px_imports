defmodule PxImports do
  @moduledoc """
  PxImports is a zero-runtime-dependency Igniter installer that wires a
  Phoenix + Ash + Oban project into the PX (Bluetab Connect) ecosystem.

  ## Usage

      mix igniter.install px_imports

  ## Available flags

    * `--org_tree` — generates Ash resources for the PX organizational tree
      (BusinessUnit, Cluster, ClientGroup, Client, Initiative) under the
      `Projects` domain, plus an `SyncOrgTreeWorker` Oban job.

    * `--projects` — generates an Ash `Project` resource under the `Projects`
      domain, plus a `SyncProjectsWorker` Oban job.

    * `--users` — patches the existing `Accounts.User` resource with employee
      fields (`sap_id`, `join_date`, `hidden_at`) and a `:sync_employee_fields`
      update action, plus a `SyncEmployeesWorker` Oban job.

  At least one flag must be provided. All three may be combined.

  ## What is always generated

  Regardless of the flags chosen, the installer always sets up an Oban job
  admin interface:

    * `<App>.Jobs` context module (wraps Ecto queries on `oban_jobs`)
    * `<App>Web.AdminLive` dashboard page
    * `<App>Web.Admin.JobsLive` scheduled + recent jobs list
    * `<App>Web.Admin.JobShowLive` detailed job inspection view
    * Router entries for `/admin`, `/admin/jobs`, `/admin/jobs/:id`
    * Dev-mode `oban_dashboard("/oban")` route
    * Oban config block in `config/config.exs` (idempotent)

  The target project must already have `:oban` in its dependencies.
  """
end
