defmodule SymphonyElixir.Server.Dashboard do
  @moduledoc """
  Server-rendered HTML dashboard for the Symphony orchestrator.

  Renders a human-readable view of current running sessions, retry queue,
  token totals, and rate limits.
  """

  import SymphonyElixir.Server.UIHelpers, only: [esc: 1]

  @doc "Render the dashboard HTML from a snapshot map."
  @spec render(map()) :: String.t()
  def render(snapshot) do
    """
    <!DOCTYPE html>
    <html lang="en">
    <head>
      <meta charset="utf-8">
      <meta name="viewport" content="width=device-width, initial-scale=1">
      <title>Symphony Dashboard</title>
      <meta http-equiv="refresh" content="10">
      <style>
        #{SymphonyElixir.Server.UIHelpers.base_css()}
        #{SymphonyElixir.Server.UIHelpers.topbar_css()}
        #{SymphonyElixir.Server.UIHelpers.nav_active_css()}
        #{SymphonyElixir.Server.UIHelpers.button_css()}
        #{SymphonyElixir.Server.UIHelpers.badge_css()}
        .dash-subtitle { padding: 8px 24px; font-size: 0.8rem; color: var(--text-muted); border-bottom: 1px solid var(--border); }
        .dash-content { padding: 20px 24px; max-width: 1200px; }
        h1 { color: var(--accent); margin-bottom: 8px; font-size: 1.5rem; }
        h2 { color: var(--text-muted); margin: 16px 0 8px; font-size: 1rem; border-bottom: 1px solid var(--border-light); padding-bottom: 4px; }
        .meta { color: var(--text-muted); font-size: 0.85rem; margin-bottom: 16px; }
        .counts { display: flex; gap: 16px; margin-bottom: 16px; flex-wrap: wrap; }
        .count-card { background: var(--bg-secondary); border: 1px solid var(--border); border-radius: var(--radius-sm); padding: 12px 20px; text-align: center; min-width: 100px; }
        .count-card .number { font-size: 1.8rem; font-weight: bold; }
        .count-card .label { font-size: 0.8rem; color: var(--text-muted); }
        .running .number { color: var(--green); }
        .retrying .number { color: var(--yellow); }
        table { width: 100%; border-collapse: collapse; margin-bottom: 16px; }
        th, td { text-align: left; padding: 8px 12px; border-bottom: 1px solid var(--border-light); }
        th { color: var(--text-muted); font-size: 0.8rem; text-transform: uppercase; }
        td { font-size: 0.85rem; }
        .badge-running { background: rgba(63,185,80,0.15); color: var(--green); }
        .badge-retry { background: rgba(210,153,34,0.15); color: var(--yellow); }
        .totals { background: var(--bg-secondary); border: 1px solid var(--border); border-radius: var(--radius-sm); padding: 16px; display: grid; grid-template-columns: repeat(auto-fit, minmax(120px, 1fr)); gap: 12px; }
        .total-item .value { font-size: 1.2rem; font-weight: bold; color: var(--accent); }
        .total-item .label { font-size: 0.8rem; color: var(--text-muted); }
        .empty { color: var(--text-muted); font-style: italic; padding: 16px; opacity: 0.6; }
        .budget-banner { background: rgba(248,81,73,0.12); border: 1px solid var(--red, #f85149); color: var(--red, #f85149); padding: 12px 20px; border-radius: var(--radius-sm); margin-bottom: 16px; font-weight: 600; display: flex; align-items: center; gap: 8px; }
        .budget-banner svg { flex-shrink: 0; }
        footer { margin-top: 24px; color: var(--text-muted); font-size: 0.72rem; text-align: center; opacity: 0.5; }
        @media (max-width: 768px) {
          .dash-topbar { padding: 8px 12px; flex-wrap: wrap; gap: 8px; }
          .counts { flex-direction: column; }
          .dash-content { padding: 12px; }
          table { font-size: 0.8rem; }
        }
      </style>
    </head>
    <body>
    #{SymphonyElixir.Server.UIHelpers.nav_topbar("dashboard")}
      <div class="dash-subtitle">
        <span class="meta">Generated at #{format_datetime(snapshot[:generated_at])} &middot; Auto-refreshes every 10s</span>
      </div>

      <div class="dash-content">
      #{render_budget_banner(snapshot)}
      <div class="counts">
        <div class="count-card running">
          <div class="number">#{snapshot[:counts][:running] || 0}</div>
          <div class="label">Running</div>
        </div>
        <div class="count-card retrying">
          <div class="number">#{snapshot[:counts][:retrying] || 0}</div>
          <div class="label">Retrying</div>
        </div>
      </div>

      #{render_totals(snapshot[:agent_totals])}

      <h2>Running Sessions</h2>
      #{render_running_table(snapshot[:running] || [])}

      <h2>Retry Queue</h2>
      #{render_retry_table(snapshot[:retrying] || [])}

      #{render_rate_limits(snapshot[:rate_limits])}

      <footer>Symphony Orchestrator &middot; Elixir #{System.version()}</footer>
      </div>
    </body>
    </html>
    """
  end

  defp render_budget_banner(snapshot) do
    if snapshot[:token_budget_exceeded] do
      total = get_in(snapshot, [:agent_totals, :total_tokens]) || 0

      """
      <div class="budget-banner">
        <svg viewBox="0 0 24 24" width="18" height="18" fill="none" stroke="currentColor" stroke-width="2"><path d="M10.29 3.86L1.82 18a2 2 0 001.71 3h16.94a2 2 0 001.71-3L13.71 3.86a2 2 0 00-3.42 0z"/><line x1="12" y1="9" x2="12" y2="13"/><line x1="12" y1="17" x2="12.01" y2="17"/></svg>
        Token budget exhausted &mdash; auto-polling deactivated, in-progress issues moved to Backlog (#{format_number(total)} tokens used this session)
      </div>
      """
    else
      ""
    end
  end

  defp render_totals(nil), do: ""

  defp render_totals(totals) do
    """
    <h2>Aggregate Totals</h2>
    <div class="totals">
      <div class="total-item">
        <div class="value">#{format_number(totals[:input_tokens] || 0)}</div>
        <div class="label">Input Tokens</div>
      </div>
      <div class="total-item">
        <div class="value">#{format_number(totals[:output_tokens] || 0)}</div>
        <div class="label">Output Tokens</div>
      </div>
      <div class="total-item">
        <div class="value">#{format_number(totals[:total_tokens] || 0)}</div>
        <div class="label">Total Tokens</div>
      </div>
      <div class="total-item">
        <div class="value">#{format_duration(totals[:seconds_running] || 0)}</div>
        <div class="label">Runtime</div>
      </div>
    </div>
    """
  end

  defp render_running_table([]) do
    ~s(<div class="empty">No running sessions</div>)
  end

  defp render_running_table(running) do
    rows =
      Enum.map_join(running, "\n", fn r ->
        """
        <tr>
          <td><strong>#{esc(r[:issue_identifier])}</strong></td>
          <td><span class="badge badge-running">#{esc(r[:state])}</span></td>
          <td>#{r[:turn_count] || 0}</td>
          <td>#{esc(r[:last_event])}</td>
          <td>#{esc(truncate(r[:last_message], 60))}</td>
          <td>#{format_tokens(r[:tokens])}</td>
          <td>#{format_datetime(r[:started_at])}</td>
        </tr>
        """
      end)

    """
    <table>
      <thead>
        <tr>
          <th>Issue</th>
          <th>State</th>
          <th>Turns</th>
          <th>Last Event</th>
          <th>Message</th>
          <th>Tokens</th>
          <th>Started</th>
        </tr>
      </thead>
      <tbody>
        #{rows}
      </tbody>
    </table>
    """
  end

  defp render_retry_table([]) do
    ~s(<div class="empty">No retries queued</div>)
  end

  defp render_retry_table(retrying) do
    rows =
      Enum.map_join(retrying, "\n", fn r ->
        """
        <tr>
          <td><strong>#{esc(r[:issue_identifier])}</strong></td>
          <td>#{r[:attempt]}</td>
          <td>#{format_datetime(r[:due_at])}</td>
          <td>#{esc(truncate(r[:error], 80))}</td>
        </tr>
        """
      end)

    """
    <table>
      <thead>
        <tr>
          <th>Issue</th>
          <th>Attempt</th>
          <th>Due At</th>
          <th>Error</th>
        </tr>
      </thead>
      <tbody>
        #{rows}
      </tbody>
    </table>
    """
  end

  defp render_rate_limits(nil), do: ""

  defp render_rate_limits(rl) when map_size(rl) == 0, do: ""

  defp render_rate_limits(rl) do
    """
    <h2>Rate Limits</h2>
    <pre>#{esc(Jason.encode!(rl, pretty: true))}</pre>
    """
  end

  # --- Formatting Helpers ---

  defp format_datetime(nil), do: "-"
  defp format_datetime(%DateTime{} = dt), do: Calendar.strftime(dt, "%Y-%m-%d %H:%M:%S UTC")
  defp format_datetime(other), do: to_string(other)

  defp format_number(n) when is_number(n) do
    n
    |> round()
    |> Integer.to_string()
    |> String.replace(~r/\B(?=(\d{3})+(?!\d))/, ",")
  end

  defp format_number(_), do: "0"

  defp format_duration(seconds) when is_number(seconds) do
    total_seconds = round(seconds)
    hours = div(total_seconds, 3600)
    minutes = div(rem(total_seconds, 3600), 60)
    secs = rem(total_seconds, 60)

    cond do
      hours > 0 -> "#{hours}h #{minutes}m"
      minutes > 0 -> "#{minutes}m #{secs}s"
      true -> "#{secs}s"
    end
  end

  defp format_duration(_), do: "0s"

  defp format_tokens(nil), do: "-"

  defp format_tokens(tokens) do
    total = tokens[:total_tokens] || 0
    format_number(total)
  end

  defp truncate(nil, _), do: ""
  defp truncate(str, max) when is_binary(str) and byte_size(str) <= max, do: str
  defp truncate(str, max) when is_binary(str), do: String.slice(str, 0, max) <> "..."
  defp truncate(val, max), do: truncate(to_string(val), max)
end
