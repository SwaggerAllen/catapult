defmodule Catapult.Delivery.HostPort.Actions do
  @moduledoc """
  The default execution substrate (`systems/generation.md`, v5
  §7.12.1): triggers a `workflow_dispatch` on the project's bound
  GitHub repo. Nothing outside this module may assume Actions — the
  contract is `Catapult.Delivery.HostPort`'s callback, not this
  adapter's own shape.

  **No failover, deliberately** (ORC-9's design rework): the shipped
  runner harness fails over on any non-zero exit and cannot yet be
  told "limit-class only" (no structured signal from the CLI's JSON
  mode is wired up there yet). Sending the credential pair here would
  let that blind failover fire on an ordinary bug, paying for the same
  failure twice. So this adapter sends the bindings `tunable`'s
  first-ordered credential alone — the second slot is never a dispatch
  input, so there is nothing for the harness's own failover to reach
  for even though it would try. The day the harness exposes a
  structured limit-class signal, this sends the full ordered pair
  instead of its head — a one-line change, not a new decision, because
  the contract was already built for two.

  The dispatch input is the plane-minted `run_key` and the chosen
  credential's *name* only — never a value. Model credentials are
  customer-side secrets the plane never holds (v5 §7.12.1); resolving
  `credential_name` to an actual key is the target repo's own workflow
  file's job, reading its own GitHub Actions secret.

  **ORC-31's branch/PR/comment/label/check operations** talk to
  GitHub's REST API directly, each traced to the protocol clause it
  serves (`HostPort`'s own moduledoc). `read_review_comments/3` and
  `read_check_status/2` page to exhaustion (`paginate/4` below) rather
  than reading one page and assuming the rest doesn't matter
  (`systems/delivery.md`'s pagination entry). `write_marker_comment/4`
  lists existing issue-level comments and parses each with
  `HostPort.Marker` before posting, so a retried decline path doesn't
  post a duplicate bounce.
  """

  @behaviour Catapult.Delivery.HostPort

  alias Catapult.Config
  alias Catapult.Config.Secret
  alias Catapult.Delivery.HostPort.Marker
  alias Catapult.Delivery.Store

  @doc """
  Overwrites `files` (repo-relative path => content) on `project_id`'s
  bound repo via GitHub's Contents API — fixture content only, never a
  generated artifact (`Catapult.Delivery.HostPort`'s own moduledoc).
  Each file is its own request: read the current blob sha if the file
  already exists (a create and an update are different calls under
  this API), then write. One file's failure does not roll back an
  earlier one — a re-run of `reset_repo/2` is the recovery, the same
  idempotent-retry shape `systems/delivery.md`'s "intent → idempotent
  effect" bullet already asks of every outbound act in this system.
  """
  @impl Catapult.Delivery.HostPort
  def reset_repo(project_id, files) do
    with {:ok, binding} <- fetch_binding(project_id) do
      put_all_files(binding, files)
    end
  end

  defp put_all_files(binding, files) do
    Enum.reduce_while(files, :ok, fn {path, content}, :ok ->
      case put_file(binding, path, content) do
        :ok -> {:cont, :ok}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  defp put_file(binding, path, content) do
    url = contents_url(binding, path)
    auth = {:bearer, Secret.unwrap(Config.fetch!(:delivery, :github_token))}
    headers = [{"accept", "application/vnd.github+json"}]

    sha =
      case Req.get(url, auth: auth, headers: headers) do
        {:ok, %{status: 200, body: %{"sha" => sha}}} -> sha
        {:ok, _not_found_or_other} -> nil
        {:error, _reason} -> nil
      end

    body = %{message: "catapult: reset fixture — #{path}", content: Base.encode64(content)}
    body = if sha, do: Map.put(body, :sha, sha), else: body

    case Req.put(url, auth: auth, headers: headers, json: body) do
      {:ok, %{status: status}} when status in 200..299 -> :ok
      {:ok, resp} -> {:error, {:reset_failed, path, resp.status, resp.body}}
      {:error, reason} -> {:error, {:reset_failed, path, reason}}
    end
  end

  defp contents_url(binding, path) do
    "https://api.github.com/repos/#{binding.repo_owner}/#{binding.repo_name}/contents/#{path}"
  end

  @impl Catapult.Delivery.HostPort
  def dispatch_run(request) do
    with {:ok, binding} <- fetch_binding(request.project_id),
         run_key = Ecto.UUID.generate(),
         {:ok, _resp} <- trigger_workflow(binding, run_key, request.credential_name) do
      Store.insert_dispatch_run(%{
        id: run_key,
        project_id: request.project_id,
        node_id: request.node_id,
        flow_id: Store.current_open_flow_id(request.project_id),
        tier: request.tier,
        scope_key: request.scope_key,
        repo_owner: binding.repo_owner,
        repo_name: binding.repo_name,
        root_tag: request.root_tag,
        rendered_prompt: request.rendered_prompt,
        credential_sent: request.credential_name
      })

      {:ok, %{run_key: run_key}}
    end
  end

  defp fetch_binding(project_id) do
    case Store.get_project_binding(project_id) do
      nil -> {:error, {:no_project_binding, project_id}}
      binding -> {:ok, binding}
    end
  end

  defp trigger_workflow(binding, run_key, credential_name) do
    workflow_file = Config.fetch!(:delivery, :dispatch_workflow_file)
    ref = Config.fetch!(:delivery, :dispatch_ref)

    url =
      "https://api.github.com/repos/#{binding.repo_owner}/#{binding.repo_name}" <>
        "/actions/workflows/#{workflow_file}/dispatches"

    response =
      Req.post(url,
        auth: {:bearer, Secret.unwrap(Config.fetch!(:delivery, :github_token))},
        headers: [{"accept", "application/vnd.github+json"}],
        json: %{ref: ref, inputs: %{run_key: run_key, credential_name: credential_name}}
      )

    case response do
      {:ok, %{status: status} = resp} when status in 200..299 -> {:ok, resp}
      {:ok, resp} -> {:error, {:dispatch_failed, resp.status, resp.body}}
      {:error, reason} -> {:error, {:dispatch_failed, reason}}
    end
  end

  ## ORC-31: branch/PR/comment/label/check operations

  @impl Catapult.Delivery.HostPort
  def create_branch(project_id, base_ref, branch_name) do
    with {:ok, binding} <- fetch_binding(project_id),
         {:ok, sha} <- fetch_ref_sha(binding, base_ref) do
      create_ref(binding, branch_name, sha)
    end
  end

  defp fetch_ref_sha(binding, ref) do
    url = "#{repo_url(binding)}/git/ref/heads/#{ref}"

    case Req.get(url, auth: auth(), headers: json_headers()) do
      {:ok, %{status: 200, body: %{"object" => %{"sha" => sha}}}} -> {:ok, sha}
      {:ok, resp} -> {:error, {:ref_not_found, ref, resp.status}}
      {:error, reason} -> {:error, {:ref_not_found, ref, reason}}
    end
  end

  defp create_ref(binding, branch_name, sha) do
    url = "#{repo_url(binding)}/git/refs"
    body = %{ref: "refs/heads/#{branch_name}", sha: sha}

    case Req.post(url, auth: auth(), headers: json_headers(), json: body) do
      {:ok, %{status: 201}} -> :ok
      {:ok, resp} -> {:error, {:create_branch_failed, resp.status, resp.body}}
      {:error, reason} -> {:error, {:create_branch_failed, reason}}
    end
  end

  @impl Catapult.Delivery.HostPort
  def open_pr(project_id, %{head: head, base: base, title: title, body: body}) do
    with {:ok, binding} <- fetch_binding(project_id) do
      url = "#{repo_url(binding)}/pulls"
      payload = %{head: head, base: base, title: title, body: body}

      case Req.post(url, auth: auth(), headers: json_headers(), json: payload) do
        {:ok, %{status: 201, body: %{"number" => number, "head" => %{"sha" => sha}}}} ->
          {:ok, %{number: number, head_sha: sha}}

        {:ok, resp} ->
          {:error, {:open_pr_failed, resp.status, resp.body}}

        {:error, reason} ->
          {:error, {:open_pr_failed, reason}}
      end
    end
  end

  @doc """
  Absorbs `source_branch`'s drift into `target_branch` (v5 §7.5: main
  into open feature branches, feature branches into their children).
  A 409 is a real conflict, surfaced as `{:error, {:conflict, _}}`
  rather than resolved here — the caller routes it to the ticket as
  rework.
  """
  @impl Catapult.Delivery.HostPort
  def merge_forward(project_id, source_branch, target_branch) do
    with {:ok, binding} <- fetch_binding(project_id) do
      url = "#{repo_url(binding)}/merges"

      body = %{
        base: target_branch,
        head: source_branch,
        commit_message: "catapult: merge #{source_branch} into #{target_branch}"
      }

      case Req.post(url, auth: auth(), headers: json_headers(), json: body) do
        {:ok, %{status: status}} when status in [201, 204] -> :ok
        {:ok, %{status: 409} = resp} -> {:error, {:conflict, resp.body}}
        {:ok, resp} -> {:error, {:merge_forward_failed, resp.status, resp.body}}
        {:error, reason} -> {:error, {:merge_forward_failed, reason}}
      end
    end
  end

  @impl Catapult.Delivery.HostPort
  def merge_pr(project_id, pr_number, method) when method in [:merge, :squash] do
    with {:ok, binding} <- fetch_binding(project_id) do
      url = "#{repo_url(binding)}/pulls/#{pr_number}/merge"
      body = %{merge_method: Atom.to_string(method)}

      case Req.put(url, auth: auth(), headers: json_headers(), json: body) do
        {:ok, %{status: status}} when status in 200..299 -> :ok
        {:ok, resp} -> {:error, {:merge_failed, resp.status, resp.body}}
        {:error, reason} -> {:error, {:merge_failed, reason}}
      end
    end
  end

  @doc """
  Line-anchored review comments, filtered to human authorship before
  anything is treated as harvestable (`systems/delivery.md`'s
  author-identity-filter entry, v5 §7.4): `performed_via_github_app`
  excludes GitHub-App-authored comments, `user.type == "Bot"` excludes
  bot accounts. Paged to exhaustion — a contested review on a real
  gate decline is not a handful of comments.
  """
  @impl Catapult.Delivery.HostPort
  def read_review_comments(project_id, pr_number, since) do
    with {:ok, binding} <- fetch_binding(project_id) do
      url = "#{repo_url(binding)}/pulls/#{pr_number}/comments?per_page=100#{since_param(since)}"

      with {:ok, comments} <- paginate(url, auth(), json_headers()) do
        {:ok,
         comments |> Enum.filter(&human_authored?/1) |> Enum.map(&normalize_review_comment/1)}
      end
    end
  end

  defp since_param(nil), do: ""
  defp since_param(%DateTime{} = since), do: "&since=#{DateTime.to_iso8601(since)}"

  defp human_authored?(%{"performed_via_github_app" => via_app}) when not is_nil(via_app),
    do: false

  defp human_authored?(%{"user" => %{"type" => "Bot"}}), do: false
  defp human_authored?(_comment), do: true

  defp normalize_review_comment(comment) do
    %{
      id: comment["id"],
      author_login: get_in(comment, ["user", "login"]),
      body: comment["body"],
      path: comment["path"],
      line: comment["line"],
      updated_at: comment["updated_at"]
    }
  end

  @doc """
  Posts `kind`'s rendered marker (`HostPort.Marker`) as an issue-level
  PR comment — never line-anchored, so this never collides with the
  review-comment surface `read_review_comments/3` harvests from.
  Idempotent: lists the PR's existing issue-level comments first and
  skips the post if this exact marker is already there (`HostPort
  .Marker`'s own moduledoc — the named caller of `parse/1`).
  """
  @impl Catapult.Delivery.HostPort
  def write_marker_comment(project_id, pr_number, kind, payload) do
    with {:ok, binding} <- fetch_binding(project_id),
         {:ok, existing} <- list_issue_comments(binding, pr_number) do
      if Enum.any?(existing, &matches_marker?(&1, kind, payload)) do
        :ok
      else
        post_issue_comment(binding, pr_number, Marker.render(kind, payload))
      end
    end
  end

  defp list_issue_comments(binding, pr_number) do
    url = "#{repo_url(binding)}/issues/#{pr_number}/comments?per_page=100"
    paginate(url, auth(), json_headers())
  end

  defp matches_marker?(%{"body" => body}, kind, payload) do
    case Marker.parse(body || "") do
      {:ok, {^kind, ^payload}} -> true
      _ -> false
    end
  end

  defp post_issue_comment(binding, pr_number, body) do
    url = "#{repo_url(binding)}/issues/#{pr_number}/comments"

    case Req.post(url, auth: auth(), headers: json_headers(), json: %{body: body}) do
      {:ok, %{status: status}} when status in 200..299 -> :ok
      {:ok, resp} -> {:error, {:marker_comment_failed, resp.status, resp.body}}
      {:error, reason} -> {:error, {:marker_comment_failed, reason}}
    end
  end

  @doc "Replaces the PR's full label set — how the plane marks `ci:docs`/`ci:code` for §7.7's job selection."
  @impl Catapult.Delivery.HostPort
  def set_pr_labels(project_id, pr_number, labels) do
    with {:ok, binding} <- fetch_binding(project_id) do
      url = "#{repo_url(binding)}/issues/#{pr_number}/labels"

      case Req.put(url, auth: auth(), headers: json_headers(), json: %{labels: labels}) do
        {:ok, %{status: status}} when status in 200..299 -> :ok
        {:ok, resp} -> {:error, {:set_labels_failed, resp.status, resp.body}}
        {:error, reason} -> {:error, {:set_labels_failed, reason}}
      end
    end
  end

  @doc "Check runs keyed to `head_sha` regardless of base branch, exactly as §7.7 requires. Paged to exhaustion."
  @impl Catapult.Delivery.HostPort
  def read_check_status(project_id, head_sha) do
    with {:ok, binding} <- fetch_binding(project_id) do
      url = "#{repo_url(binding)}/commits/#{head_sha}/check-runs?per_page=100"

      with {:ok, runs} <- paginate(url, auth(), json_headers(), & &1["check_runs"]) do
        {:ok, Enum.map(runs, &normalize_check_run/1)}
      end
    end
  end

  defp normalize_check_run(run) do
    %{name: run["name"], status: run["status"], conclusion: run["conclusion"]}
  end

  @doc """
  Writes `files` (repo-relative path => content) onto `branch` via
  GitHub's Contents API, each under `message` — the same per-file
  shape `reset_repo/2` uses (read the blob sha if the file exists, PUT
  with it if so), generalized with an explicit branch ref instead of
  the implicit default branch `reset_repo/2` always targets, and a
  caller-supplied message instead of `reset_repo/2`'s own fixed one
  (`Catapult.Delivery.HostPort`'s own moduledoc, ORC-33). One file's
  failure does not roll back an earlier one, the same idempotent-retry
  shape `reset_repo/2` already follows.
  """
  @impl Catapult.Delivery.HostPort
  def commit_files(project_id, branch, files, message) do
    with {:ok, binding} <- fetch_binding(project_id) do
      put_all_branch_files(binding, branch, files, message)
    end
  end

  defp put_all_branch_files(binding, branch, files, message) do
    Enum.reduce_while(files, :ok, fn {path, content}, :ok ->
      case put_branch_file(binding, branch, path, content, message) do
        :ok -> {:cont, :ok}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  defp put_branch_file(binding, branch, path, content, message) do
    url = contents_url(binding, path)

    sha =
      case Req.get(url, auth: auth(), headers: json_headers(), params: [ref: branch]) do
        {:ok, %{status: 200, body: %{"sha" => sha}}} -> sha
        {:ok, _not_found_or_other} -> nil
        {:error, _reason} -> nil
      end

    body = %{message: message, content: Base.encode64(content), branch: branch}
    body = if sha, do: Map.put(body, :sha, sha), else: body

    case Req.put(url, auth: auth(), headers: json_headers(), json: body) do
      {:ok, %{status: status}} when status in 200..299 -> :ok
      {:ok, resp} -> {:error, {:commit_files_failed, path, resp.status, resp.body}}
      {:error, reason} -> {:error, {:commit_files_failed, path, reason}}
    end
  end

  @doc "Replaces the PR's body wholesale — regenerated on every push, never appended to (`systems/delivery.md`'s ORC-33 entry)."
  @impl Catapult.Delivery.HostPort
  def update_pr_body(project_id, pr_number, body) do
    with {:ok, binding} <- fetch_binding(project_id) do
      url = "#{repo_url(binding)}/pulls/#{pr_number}"

      case Req.patch(url, auth: auth(), headers: json_headers(), json: %{body: body}) do
        {:ok, %{status: status}} when status in 200..299 -> :ok
        {:ok, resp} -> {:error, {:update_pr_body_failed, resp.status, resp.body}}
        {:error, reason} -> {:error, {:update_pr_body_failed, reason}}
      end
    end
  end

  @doc "The PR's diff, for reconciliation — the port moves refs and reads diffs, it never checks out (conventions §11)."
  @impl Catapult.Delivery.HostPort
  def read_diff(project_id, pr_number) do
    with {:ok, binding} <- fetch_binding(project_id) do
      url = "#{repo_url(binding)}/pulls/#{pr_number}"
      headers = [{"accept", "application/vnd.github.v3.diff"}]

      case Req.get(url, auth: auth(), headers: headers) do
        {:ok, %{status: 200, body: diff}} when is_binary(diff) -> {:ok, diff}
        {:ok, resp} -> {:error, {:read_diff_failed, resp.status}}
        {:error, reason} -> {:error, {:read_diff_failed, reason}}
      end
    end
  end

  # Follows GitHub's own `Link: <url>; rel="next"` header to exhaustion
  # rather than reading one page and assuming the rest doesn't matter
  # (`systems/delivery.md`'s pagination entry — ORC-101 found the
  # single-page version of this defect once already, in the Go
  # pipeline's own adapter). `extract` unwraps a page's body into the
  # list of items it carries — bare for `pulls/*/comments` and
  # `issues/*/comments`, `body["check_runs"]` for check-runs.
  defp paginate(url, auth, headers, extract \\ & &1) do
    do_paginate(url, auth, headers, extract, [])
  end

  defp do_paginate(url, auth, headers, extract, acc) do
    case Req.get(url, auth: auth, headers: headers) do
      {:ok, %{status: 200, body: body} = resp} ->
        acc = acc ++ extract.(body)

        case next_link(resp.headers) do
          nil -> {:ok, acc}
          next_url -> do_paginate(next_url, auth, headers, extract, acc)
        end

      {:ok, resp} ->
        {:error, {:list_failed, resp.status, resp.body}}

      {:error, reason} ->
        {:error, {:list_failed, reason}}
    end
  end

  defp next_link(%{"link" => [link_header | _]}) do
    link_header
    |> String.split(",")
    |> Enum.find_value(fn part ->
      case Regex.run(~r/<([^>]+)>;\s*rel="next"/, part) do
        [_, url] -> url
        nil -> nil
      end
    end)
  end

  defp next_link(_headers), do: nil

  defp auth, do: {:bearer, Secret.unwrap(Config.fetch!(:delivery, :github_token))}
  defp json_headers, do: [{"accept", "application/vnd.github+json"}]

  defp repo_url(binding),
    do: "https://api.github.com/repos/#{binding.repo_owner}/#{binding.repo_name}"
end
