defmodule PxImports do
  @moduledoc """
  PxImports is a zero-runtime-dependency Igniter installer that wires a
  Phoenix + Ash + Oban project into the PX (Bluetab Connect) ecosystem.

  ## Usage

      mix igniter.install px_imports

  ## Available flags

    * `--org-tree` — generates Ash resources for the PX commercial tree
      (BusinessUnit, Cluster, ClientGroup, Client, Project) under the
      `Projects` domain, `SyncProjectsWorker` (used by the org sync), and
      `SyncOrgTreeWorker` (daily Oban job).

    * `--spend-types` — generates `Projects.SpendType` and
      `SyncSpendTypesWorker` (daily Oban job).

    * `--month_close` — generates `Projects.MonthEndClose` and
      `SyncMonthEndCloseWorker` (daily Oban job).

    * `--positions` — generates `Projects.Position`,
      `Projects.PositionRelationship`, and `SyncPositionsWorker` (daily Oban job).

    * `--users` — patches the existing `Accounts.User` resource for PX employees
      (`sap_id`, `join_date`, `hidden_at`, `category`, `category_name` from PX as
      strings), `:provision_from_employee_sync` and `:sync_employee_fields`, plus
      `SyncEmployeesWorker`. Reporting structure comes from the Positions API
      (`--positions`), not employee records. Re-running on an already-patched app
      may skip changes; merge manually if needed.

  At least one flag must be provided. All flags may be combined.

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
