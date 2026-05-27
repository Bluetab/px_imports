use __WEB_MODULE__, :live_view

require Ash.Query
require Ash.Expr

alias __ACCOUNTS_MODULE__, as: Accounts
alias __USER_MODULE__, as: User

on_mount {__LIVE_USER_AUTH_MODULE__, :live_admin_required}

@per_page 25

@impl true
def mount(_params, _session, socket) do
  {:ok, socket}
end

@impl true
def handle_params(params, _uri, socket) do
  page = parse_page(Map.get(params, "page"))
  q = params |> Map.get("q", "") |> to_string() |> String.trim()
  show_inactive = parse_bool(Map.get(params, "show_inactive"))
  filter_form = to_form(%{"q" => q, "show_inactive" => show_inactive}, as: :filter)

  socket =
    socket
    |> assign(
      page: page,
      search_q: q,
      show_inactive: show_inactive,
      filter_form: filter_form
    )
    |> load_users_page()

  {:noreply, socket}
end

@impl true
def handle_event("search", %{"filter" => filter_params}, socket) do
  q = filter_params |> Map.get("q", "") |> to_string() |> String.trim()
  show_inactive = parse_bool(Map.get(filter_params, "show_inactive"))

  {:noreply, push_patch(socket, to: users_patch_path(1, q, show_inactive))}
end

def handle_event("search", _params, socket) do
  {:noreply, push_patch(socket, to: users_patch_path(1, socket.assigns.search_q, false))}
end

@impl true
def handle_event("ignore_search_submit", _params, socket) do
  {:noreply, socket}
end

@impl true
def handle_event("toggle_admin", %{"id" => id}, socket) do
  user = Enum.find(socket.assigns.users, &(to_string(&1.id) == id))

  case user do
    nil ->
      {:noreply, put_flash(socket, :error, "User not found on this page")}

    user ->
      user
      |> Ash.Changeset.for_update(:set_admin, %{is_admin: !user.is_admin},
        actor: socket.assigns.current_user
      )
      |> Ash.update(domain: Accounts, actor: socket.assigns.current_user, authorize?: false)
      |> case do
        {:ok, _updated_user} ->
          {:noreply, socket |> put_flash(:info, "Admin flag updated") |> load_users_page()}

        {:error, reason} ->
          {:noreply, put_flash(socket, :error, "Failed to update admin flag: #{inspect(reason)}")}
      end
  end
end

defp load_users_page(socket) do
  page = socket.assigns.page
  q = socket.assigns.search_q
  show_inactive = socket.assigns.show_inactive

  query =
    User
    |> Ash.Query.for_read(:list_for_admin)
    |> maybe_filter_active(show_inactive)
    |> maybe_filter_search(q)
    |> Ash.Query.sort(:email)
    |> Ash.Query.page(limit: @per_page, offset: (page - 1) * @per_page, count: true)

  %Ash.Page.Offset{
    results: users,
    count: total,
    limit: limit,
    offset: offset
  } = Ash.read!(query, domain: Accounts, authorize?: false)

  more? = offset + length(users) < total

  assign(socket,
    users: users,
    users_total: total,
    users_limit: limit,
    users_offset: offset,
    users_more?: more?
  )
end

defp maybe_filter_search(query, ""), do: query

defp maybe_filter_search(query, term) do
  Ash.Query.filter(
    query,
    Ash.Expr.expr(
      contains(email, ^term) or
        (not is_nil(given_name) and contains(given_name, ^term)) or
        (not is_nil(family_name) and contains(family_name, ^term))
    )
  )
end

defp maybe_filter_active(query, true), do: query

defp maybe_filter_active(query, false) do
  Ash.Query.filter(query, Ash.Expr.expr(is_nil(hidden_at)))
end

defp parse_page(nil), do: 1
defp parse_page(""), do: 1

defp parse_page(str) do
  case Integer.parse(to_string(str)) do
    {n, _} when n > 0 -> n
    _ -> 1
  end
end

defp parse_bool(value), do: value in [true, "true", "on", "1", 1]

defp users_patch_path(page, q, show_inactive) do
  pairs =
    []
    |> then(fn acc -> if page > 1, do: [{"page", Integer.to_string(page)} | acc], else: acc end)
    |> then(fn acc -> if q != "", do: [{"q", q} | acc], else: acc end)
    |> then(fn acc ->
      if show_inactive, do: [{"show_inactive", "true"} | acc], else: acc
    end)

  base = ~p"/admin/users"

  case pairs do
    [] -> base
    _ -> base <> "?" <> URI.encode_query(pairs)
  end
end

defp range_label(offset, total, shown) do
  start_i = offset + 1
  end_i = offset + shown

  cond do
    total == 0 ->
      "No users"

    shown == 0 ->
      "No users on this page"

    true ->
      "#{start_i}-#{end_i} of #{total}"
  end
end

defp join_date_label(nil), do: "—"
defp join_date_label(%Date{} = date), do: Date.to_iso8601(date)

defp hidden_at_title(nil), do: ""
defp hidden_at_title(%DateTime{} = datetime), do: DateTime.to_iso8601(datetime)
defp hidden_at_title(%NaiveDateTime{} = datetime), do: NaiveDateTime.to_iso8601(datetime)
defp hidden_at_title(%Date{} = date), do: Date.to_iso8601(date)
defp hidden_at_title(value), do: to_string(value)

@impl true
def render(assigns) do
  assigns =
    assign(
      assigns,
      :range_label,
      range_label(assigns.users_offset, assigns.users_total, length(assigns.users))
    )

  ~H"""
  <Layouts.app
    flash={@flash}
    current_user={@current_user}
    current_path={assigns[:current_path] || "/"}
    impersonator={assigns[:impersonator]}
  >
    <.bt_header>
      Users
      <:subtitle>Manage admin access and impersonation.</:subtitle>
    </.bt_header>

    <div class="bt-stack" style="gap: var(--bt-space-4); margin-top: var(--bt-space-4);">
      <.form
        for={@filter_form}
        phx-change="search"
        phx-submit="ignore_search_submit"
        class="bt-row"
        style="flex-wrap: wrap; align-items: flex-end; gap: var(--bt-space-3);"
      >
        <div style="flex: 1; min-width: 12rem; max-width: 24rem;">
          <.bt_input
            field={@filter_form[:q]}
            type="search"
            label="Search"
            placeholder="Email or name..."
            phx-debounce="300"
          />
        </div>
        <.bt_input field={@filter_form[:show_inactive]} type="checkbox" label="Show inactive users" />
        <.bt_button
          :if={@search_q != ""}
          variant="ghost"
          patch={users_patch_path(1, "", @show_inactive)}
        >
          Clear
        </.bt_button>
      </.form>

      <div class="bt-row" style="justify-content: space-between; flex-wrap: wrap; gap: var(--bt-space-2);">
        <span class="bt-muted">{@range_label}</span>
        <div class="bt-row" style="gap: var(--bt-space-2);">
          <%= if @page <= 1 do %>
            <span class="bt-button bt-button--ghost" aria-disabled="true" style="opacity: 0.5;">Previous</span>
          <% else %>
            <.bt_button variant="outline" patch={users_patch_path(@page - 1, @search_q, @show_inactive)}>
              Previous
            </.bt_button>
          <% end %>
          <span class="bt-muted" style="align-self: center;">Page {@page}</span>
          <%= if @users_more? do %>
            <.bt_button variant="outline" patch={users_patch_path(@page + 1, @search_q, @show_inactive)}>
              Next
            </.bt_button>
          <% else %>
            <span class="bt-button bt-button--ghost" aria-disabled="true" style="opacity: 0.5;">Next</span>
          <% end %>
        </div>
      </div>
    </div>

    <p :if={@users == []} class="bt-muted" style="margin-top: var(--bt-space-6); text-align: center;">
      <%= if @search_q != "" do %>
        No users match this search.
      <% else %>
        No users yet.
      <% end %>
    </p>

    <div :if={@users != []} style="margin-top: var(--bt-space-4);">
      <.bt_table id="admin-users" rows={@users} row_id={fn user -> "user-#{user.id}" end}>
        <:col :let={user} label="Email">
          <strong>{user.email}</strong>
        </:col>
        <:col :let={user} label="Name">{user.given_name} {user.family_name}</:col>
        <:col :let={user} label="Admin">
          <div class="bt-row" style="flex-wrap: wrap; gap: var(--bt-space-2);">
            <.bt_badge :if={user.is_admin} variant="primary">Admin</.bt_badge>
            <span :if={!user.is_admin} class="bt-muted">—</span>
            <.bt_button
              :if={!user.is_admin}
              variant="ghost"
              phx-click="toggle_admin"
              phx-value-id={user.id}
              class="bt-button--sm"
            >
              Grant admin
            </.bt_button>
            <.bt_button
              :if={user.is_admin and user.id != @current_user.id}
              variant="danger"
              phx-click="toggle_admin"
              phx-value-id={user.id}
              class="bt-button--sm"
            >
              Revoke admin
            </.bt_button>
          </div>
        </:col>
        <:col :let={user} label="Category">{user.category_name || user.category || "—"}</:col>
        <:col :let={user} label="Join date">
          <div class="bt-stack" style="gap: var(--bt-space-1);">
            <span>{join_date_label(user.join_date)}</span>
            <span :if={!is_nil(user.hidden_at)} title={hidden_at_title(user.hidden_at)}>
              <.bt_status variant="warning">Inactive</.bt_status>
            </span>
          </div>
        </:col>
        <:action :let={user}>
          <.form for={%{}} action={~p"/admin/impersonation/start/#{user.id}"} method="post">
            <input type="hidden" name="_csrf_token" value={Plug.CSRFProtection.get_csrf_token()} />
            <.bt_button type="submit" variant="outline" class="bt-button--sm">Impersonate</.bt_button>
          </.form>
        </:action>
      </.bt_table>
    </div>
  </Layouts.app>
  """
end
