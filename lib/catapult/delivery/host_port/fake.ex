defmodule Catapult.Delivery.HostPort.Fake do
  @moduledoc """
  The in-process fake (conventions §9 — ships with the port, never
  disposable relative to `Actions`): opens a dispatch-run record like
  the real adapter, then synchronously drives
  `Catapult.Delivery.Dispatch.simulate_result/2` with a canned result
  — no HTTP, no OIDC round trip, the same commit path a real inbound
  call would reach (`systems/generation.md`'s own standing decision
  that the fake is scope, not scaffolding).

  The canned result comes from `Application.get_env(:catapult,
  :fake_dispatch_result)`, a 1-arity function `request -> result_map`
  a test sets before dispatching — the same seam
  `Catapult.Config.Static`'s seed map already is for the config
  source, applied to a port instead. There is no sane platform
  default (a canned body has to match the tier's own grammar), so an
  unconfigured call raises loudly rather than returning a
  quietly-wrong success.

  **ORC-31's branch/PR/comment/label/check operations** talk to
  `Fake.Forge`, a per-test supervised process (`systems/delivery.md`'s
  fake-process correction) reached under the fixed name
  `Catapult.Delivery.HostPort.Fake.Forge` — a test starts one with
  `start_supervised({Fake.Forge, name: Fake.Forge})` before driving
  these, and runs `async: false` for the same reason
  `dispatch_worker_test.exs` already does for `fake_dispatch_result`
  above: a single well-known name, not one scoped per test. Each
  operation here duplicates the *protocol* logic `HostPort.Actions`
  runs — author-identity filtering on review comments, the marker
  idempotency check — against `Forge`'s plain storage, rather than
  sharing a helper that would let a bug in the shared logic hide from
  both adapters at once.
  """

  require Logger

  @behaviour Catapult.Delivery.HostPort

  alias Catapult.Delivery.Dispatch
  alias Catapult.Delivery.HostPort.Fake.Forge
  alias Catapult.Delivery.HostPort.Marker
  alias Catapult.Delivery.Store

  @impl Catapult.Delivery.HostPort
  def dispatch_run(request) do
    run_key = Ecto.UUID.generate()

    Store.insert_dispatch_run(%{
      id: run_key,
      project_id: request.project_id,
      node_id: request.node_id,
      flow_id: Store.current_open_flow_id(request.project_id),
      tier: request.tier,
      scope_key: request.scope_key,
      repo_owner: "fake",
      repo_name: "fake",
      root_tag: request.root_tag,
      rendered_prompt: request.rendered_prompt,
      credential_sent: request.credential_names
    })

    # Mirrors the Actions adapter's own contract: `{:ok, run_key}`
    # means dispatch was accepted, not that the (here, simulated) run
    # eventually succeeded — a real dispatch can't know that either.
    # A caller that cares inspects `Store.get_dispatch_run/1`.
    case Dispatch.simulate_result(run_key, canned_result_fun().(request)) do
      :ok ->
        :ok

      {:error, reason} ->
        Logger.warning("fake host port's canned result was rejected: #{inspect(reason)}",
          component: :delivery
        )
    end

    {:ok, %{run_key: run_key}}
  end

  defp canned_result_fun do
    Application.get_env(:catapult, :fake_dispatch_result) ||
      raise """
      Catapult.Delivery.HostPort.Fake needs a canned result — set
      Application.put_env(:catapult, :fake_dispatch_result, fn request -> %{...} end)
      before dispatching (conventions §9's fake, driven by the caller's own fixture).
      """
  end

  # There is no in-process bound repo for the fake to overwrite — the
  # whole point of the fake is that nothing here reaches the network
  # (`systems/delivery.md`'s ORC-10 entry). What the offline chain test
  # actually exercises by calling this is the *shape*: both adapters
  # answer to the same two-callback port, so a caller driving the reset
  # step ahead of dispatch — the sequence a live run needs — takes the
  # identical path through the fake, with nothing conditioned on which
  # adapter is configured.
  @impl Catapult.Delivery.HostPort
  def reset_repo(project_id, files) do
    Logger.info(
      "fake host port reset (no-op): project_id=#{project_id} files=#{inspect(Map.keys(files))}",
      component: :delivery
    )

    :ok
  end

  ## ORC-31: branch/PR/comment/label/check operations, against `Forge`

  @impl Catapult.Delivery.HostPort
  def create_branch(_project_id, base_ref, branch_name) do
    Forge.create_branch(forge!(), base_ref, branch_name)
  end

  @impl Catapult.Delivery.HostPort
  def open_pr(_project_id, request), do: Forge.open_pr(forge!(), request)

  @impl Catapult.Delivery.HostPort
  def merge_forward(_project_id, source_branch, target_branch) do
    Forge.merge_forward(forge!(), source_branch, target_branch)
  end

  @impl Catapult.Delivery.HostPort
  def merge_pr(_project_id, pr_number, method), do: Forge.merge_pr(forge!(), pr_number, method)

  @doc """
  Same author-identity filter `HostPort.Actions` applies
  (`systems/delivery.md`'s ORC-31 harvest-filter entry), run against
  `Forge`'s seeded comments rather than GitHub's API response —
  duplicated on purpose rather than shared, so a bug in the filter
  itself would show up here too.
  """
  @impl Catapult.Delivery.HostPort
  def read_review_comments(_project_id, pr_number, since) do
    comments =
      forge!()
      |> Forge.list_review_comments(pr_number)
      |> Enum.filter(&(human_authored?(&1) and posted_since?(&1, since)))
      |> Enum.map(&normalize_review_comment/1)

    {:ok, comments}
  end

  @doc "Same idempotency check as `HostPort.Actions`: skip the post if this exact marker is already there."
  @impl Catapult.Delivery.HostPort
  def write_marker_comment(_project_id, pr_number, kind, payload) do
    forge = forge!()
    existing = Forge.list_issue_comments(forge, pr_number)

    if Enum.any?(existing, &matches_marker?(&1, kind, payload)) do
      :ok
    else
      Forge.add_issue_comment(forge, pr_number, Marker.render(kind, payload))
    end
  end

  @impl Catapult.Delivery.HostPort
  def set_pr_labels(_project_id, pr_number, labels),
    do: Forge.set_labels(forge!(), pr_number, labels)

  @impl Catapult.Delivery.HostPort
  def read_check_status(_project_id, head_sha) do
    runs =
      forge!()
      |> Forge.list_check_runs(head_sha)
      |> Enum.map(&normalize_check_run/1)

    {:ok, runs}
  end

  @doc "Writes `files` onto `branch`'s in-memory content (`Fake.Forge`) — the fake's own answer to `commit_files/4`."
  @impl Catapult.Delivery.HostPort
  def commit_files(_project_id, branch, files, message) do
    Forge.commit_files(forge!(), branch, files, message)
  end

  @doc "Replaces the fake PR's stored body — the fake's own answer to `update_pr_body/3`."
  @impl Catapult.Delivery.HostPort
  def update_pr_body(_project_id, pr_number, body),
    do: Forge.update_pr_body(forge!(), pr_number, body)

  @doc """
  Every file directly under `path` at `ref` — read against `Forge`'s
  same branch/ref-keyed file storage `commit_files/4` and
  `read_diff/2` already share (`ref` and `branch` are the same kind of
  string to `Forge`, which does not model commits). A `ref` `Forge`
  has never seen answers `{:ok, %{}}`, the intake raft's own "no raft
  yet" shape (`HostPort.Actions.read_directory/3`'s own doc).
  """
  @impl Catapult.Delivery.HostPort
  def read_directory(_project_id, ref, path) do
    case Forge.branch_files(forge!(), ref) do
      {:ok, files} -> {:ok, directory_entries(files, path)}
      {:error, :no_such_branch} -> {:ok, %{}}
    end
  end

  defp directory_entries(files, path) do
    prefix = String.trim_trailing(path, "/") <> "/"

    for {file_path, content} <- files,
        String.starts_with?(file_path, prefix),
        filename = String.trim_leading(file_path, prefix),
        filename != "" and not String.contains?(filename, "/"),
        into: %{} do
      {filename, content}
    end
  end

  @doc "Synthesizes a file-level diff between the PR's base and head branch snapshots — there is no real git object for a fake to read."
  @impl Catapult.Delivery.HostPort
  def read_diff(_project_id, pr_number) do
    forge = forge!()

    case Forge.get_pr(forge, pr_number) do
      nil -> {:error, {:no_such_pr, pr_number}}
      pr -> {:ok, synthesize_diff(forge, pr)}
    end
  end

  defp forge! do
    case Process.whereis(Forge) do
      nil ->
        raise """
        Catapult.Delivery.HostPort.Fake needs Fake.Forge started — set:
          {:ok, _pid} = start_supervised({Catapult.Delivery.HostPort.Fake.Forge, name: Catapult.Delivery.HostPort.Fake.Forge})
        before calling a branch/PR/comment/label/check operation on the fake, and run the test `async: false`
        (systems/delivery.md's fake-process correction — one well-known name, like `fake_dispatch_result` above).
        """

      _pid ->
        Forge
    end
  end

  defp human_authored?(%{performed_via_github_app: via_app}) when not is_nil(via_app), do: false
  defp human_authored?(%{author_type: "Bot"}), do: false
  defp human_authored?(_comment), do: true

  defp posted_since?(_comment, nil), do: true
  defp posted_since?(%{updated_at: nil}, _since), do: true

  defp posted_since?(%{updated_at: %DateTime{} = updated_at}, since),
    do: DateTime.compare(updated_at, since) != :lt

  defp normalize_review_comment(comment),
    do: Map.take(comment, [:id, :author_login, :body, :path, :line, :updated_at])

  defp normalize_check_run(run) do
    %{
      name: Map.fetch!(run, :name),
      status: Map.fetch!(run, :status),
      conclusion: Map.get(run, :conclusion)
    }
  end

  defp matches_marker?(%{body: body}, kind, payload) do
    case Marker.parse(body) do
      {:ok, {^kind, ^payload}} -> true
      _ -> false
    end
  end

  defp synthesize_diff(forge, pr) do
    {:ok, base_files} = Forge.branch_files(forge, pr.base)
    {:ok, head_files} = Forge.branch_files(forge, pr.head)

    base_files
    |> Map.keys()
    |> Kernel.++(Map.keys(head_files))
    |> Enum.uniq()
    |> Enum.sort()
    |> Enum.map(&diff_line(&1, base_files, head_files))
    |> Enum.reject(&is_nil/1)
    |> Enum.join("\n")
  end

  defp diff_line(path, base_files, head_files) do
    case {Map.get(base_files, path), Map.get(head_files, path)} do
      {nil, content} -> "+++ #{path}\n#{content}"
      {content, nil} -> "--- #{path}\n#{content}"
      {same, same} -> nil
      {_old, new} -> "~~~ #{path}\n#{new}"
    end
  end
end
