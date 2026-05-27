use __WEB_MODULE__, :live_view

on_mount {__LIVE_USER_AUTH_MODULE__, :live_admin_required}

alias __JOBS_MODULE__

@impl true
def mount(%{"id" => id}, _session, socket) do
  job = Jobs.get_job!(String.to_integer(id))

  {:ok,
   socket
   |> assign(:page_title, "Job ##{job.id}")
   |> assign(:job, job)}
end

@impl true
def render(assigns) do
  ~H"""
  <Layouts.app
    flash={@flash}
    current_user={@current_user}
    current_path={assigns[:current_path] || "/"}
    impersonator={assigns[:impersonator]}
  >
    <div class="bt-stack" style="gap: var(--bt-space-8);">
      <div class="bt-section__header">
        <div>
          <h1 class="bt-section__title">Job ##{@job.id}</h1>
          <p class="bt-section__description">{@job.worker}</p>
        </div>
        <.bt_button variant="ghost" navigate={~p"/admin/jobs"}>
          <.icon name="hero-arrow-left" class="size-4" /> Back
        </.bt_button>
      </div>

      <.bt_example_grid>
        <.meta_stat_card grid_span="half" label="State" value={@job.state} />
        <.meta_stat_card grid_span="half" label="Queue" value={@job.queue} />
        <.meta_stat_card grid_span="half" label="Attempts" value={"#{@job.attempt}/#{@job.max_attempts}"} />
        <.meta_stat_card grid_span="half" label="Inserted" value={format_datetime(@job.inserted_at)} />
      </.bt_example_grid>

      <.bt_card variant="filled">
        <:title>Args</:title>
        <.bt_code_block>{@job.args |> inspect(pretty: true, limit: :infinity)}</.bt_code_block>
      </.bt_card>

      <.bt_card variant="filled">
        <:title>Meta</:title>
        <p :if={@job.meta in [%{}, nil]} class="bt-muted">No metadata recorded for this job.</p>

        <div :if={@job.meta not in [%{}, nil]} class="bt-stack" style="gap: var(--bt-space-4);">
          <.bt_example_grid>
            <.meta_stat_card grid_span="third" label="Total records" value={meta_total(@job.meta)} />
            <.meta_stat_card grid_span="third" label="Created" value={meta_count(@job.meta, "created_count")} />
            <.meta_stat_card grid_span="third" label="Updated" value={meta_count(@job.meta, "updated_count")} />
            <.meta_stat_card grid_span="third" label="Skipped" value={meta_count(@job.meta, "skipped_count")} />
            <.meta_stat_card grid_span="third" label="Not found" value={meta_count(@job.meta, "not_found_count")} />
            <.meta_stat_card grid_span="third" label="Failed" value={meta_count(@job.meta, "failed_count")} />
          </.bt_example_grid>

          <p :if={@job.meta["completed_at"]} class="bt-muted">
            Completed at: {format_iso_datetime(@job.meta["completed_at"])}
          </p>

          <.bt_expansion title="Created records">
            <p :if={meta_created(@job.meta) == []} class="bt-muted">No created records.</p>
            <div
              :for={{item, index} <- Enum.with_index(meta_created(@job.meta), 1)}
              id={"meta-created-#{index}"}
              class="bt-card bt-card--filled"
              style="margin-top: var(--bt-space-2);"
            >
              <strong>{item["name"] || item[:name] || "Unnamed"}</strong>
              <p class="bt-muted">
                SAP ID: {item["sap_id"] || item[:sap_id] || "-"}
              </p>
            </div>
          </.bt_expansion>

          <.bt_expansion title="Updated records">
            <p :if={meta_updated(@job.meta) == []} class="bt-muted">No updated records.</p>
            <div
              :for={{item, index} <- Enum.with_index(meta_updated(@job.meta), 1)}
              id={"meta-updated-#{index}"}
              class="bt-card bt-card--filled"
              style="margin-top: var(--bt-space-2);"
            >
              <strong>{item["email"] || item["name"] || "Unknown"}</strong>
              <ul class="bt-stack" style="gap: var(--bt-space-1); margin-top: var(--bt-space-2);">
                <li :for={change <- item["changes"] || []}>
                  <strong>{change["field"]}:</strong> {change["new_value"]}
                </li>
              </ul>
            </div>
          </.bt_expansion>

          <.bt_expansion title="Skipped records">
            <p :if={meta_skipped(@job.meta) == []} class="bt-muted">No skipped records.</p>
            <p :for={item <- meta_skipped(@job.meta)}>{meta_item_label(item)}</p>
          </.bt_expansion>

          <.bt_expansion title="Not found records">
            <p :if={meta_not_found(@job.meta) == []} class="bt-muted">No not-found records.</p>
            <p :for={item <- meta_not_found(@job.meta)}>{meta_item_label(item)}</p>
          </.bt_expansion>

          <.bt_expansion title="Failed records">
            <p :if={meta_failed(@job.meta) == []} class="bt-muted">No failed records.</p>
            <div
              :for={{item, index} <- Enum.with_index(meta_failed(@job.meta), 1)}
              id={"meta-failed-#{index}"}
              class="bt-card bt-card--filled"
              style="margin-top: var(--bt-space-2);"
            >
              <p class="bt-muted">
                SAP ID: {item["sap_id"] || item[:sap_id] || "-"}
              </p>
              <.bt_code_block>{item["error"] || item[:error] || inspect(item)}</.bt_code_block>
            </div>
          </.bt_expansion>

          <.bt_expansion title="Raw metadata">
            <.bt_code_block>{@job.meta |> inspect(pretty: true, limit: :infinity)}</.bt_code_block>
          </.bt_expansion>
        </div>
      </.bt_card>

      <.bt_card variant="filled">
        <:title>Errors</:title>
        <p :if={@job.errors == []} class="bt-muted">No errors recorded for this job.</p>
        <div :if={@job.errors != []} class="bt-stack" style="gap: var(--bt-space-3);">
          <div
            :for={{error, index} <- Enum.with_index(@job.errors, 1)}
            id={"job-error-#{index}"}
            class="bt-card"
            style="border-color: var(--bt-color-error);"
          >
            <div class="bt-row" style="flex-wrap: wrap; gap: var(--bt-space-3);">
              <.bt_status variant="error">Attempt {error_attempt(error)}</.bt_status>
              <span class="bt-muted">{format_iso_datetime(error["at"])}</span>
            </div>
            <.bt_code_block>{error_message(error)}</.bt_code_block>
          </div>
        </div>
      </.bt_card>
    </div>
  </Layouts.app>
  """
end

attr :label, :string, required: true
attr :value, :any, required: true
attr :grid_span, :string, default: "half", values: ~w(half third)

defp meta_stat_card(assigns) do
  span_class = if assigns.grid_span == "third", do: "bt-card--third", else: "bt-card--half"

  assigns = assign(assigns, :span_class, span_class)

  ~H"""
  <.bt_card variant="filled" class={@span_class}>
    <p class="bt-muted" style="text-transform: uppercase; font-size: 0.75rem;">{@label}</p>
    <p style="margin-top: var(--bt-space-1); font-size: 1.25rem; font-weight: 600;">{@value}</p>
  </.bt_card>
  """
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
  ["business_units", "clusters", "client_groups", "clients", "projects"]
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
