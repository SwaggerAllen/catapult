defmodule Catapult.Delivery.HostPort.Fake.Forge do
  @moduledoc """
  In-memory forge state for `HostPort.Fake` (`systems/delivery.md`'s
  ORC-31 fake-process correction): branches, PRs, review/issue
  comments, labels and check runs, held by a GenServer a test starts
  and stops itself — never a `Catapult.Delivery.Store` table, because
  production writes none of this; GitHub holds it and the real adapter
  only ever reads it back.

  No process identity of its own is registered here (conventions §5's
  registry is for production processes); a caller starts this under
  whatever name it likes, the same way `test/catapult/engine
  /sweeper_test.exs` starts a throwaway `Sweeper`:

      {:ok, _pid} = start_supervised({Forge, name: Forge})

  `HostPort.Fake` talks to the fixed name `Catapult.Delivery.HostPort
  .Fake.Forge` (mirroring `fake_dispatch_result`'s use of a single
  well-known config key), so a test suite exercising the fake runs
  `async: false` — the same accommodation `dispatch_worker_test.exs`
  already makes for that config key.

  This module is deliberately dumb: it stores what callers hand it and
  answers what they ask for. Protocol logic — author-identity
  filtering, harvesting, marker idempotency — lives in `HostPort
  .Actions` and `HostPort.Fake` themselves, each independently, so the
  fake actually exercises the same logic the real adapter runs rather
  than asserting it away in a shared helper.
  """

  use GenServer

  defstruct branches: %{},
            prs: %{},
            next_pr_number: 1,
            review_comments: %{},
            issue_comments: %{},
            next_comment_id: 1,
            labels: %{},
            check_runs: %{},
            armed_conflicts: MapSet.new()

  @type files :: %{String.t() => String.t()}

  ## Client API — production-path shape (mirrors what HostPort.Fake needs)

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts), do: GenServer.start_link(__MODULE__, %__MODULE__{}, opts)

  @doc "Seeds `branch` directly with `files`, as if some prior commit had already landed — there is no port operation for authoring content, so tests/scenarios set it here."
  @spec seed_branch(GenServer.server(), String.t(), files()) :: :ok
  def seed_branch(server, branch, files \\ %{}) do
    GenServer.call(server, {:seed_branch, branch, files})
  end

  @spec branch_files(GenServer.server(), String.t()) :: {:ok, files()} | {:error, :no_such_branch}
  def branch_files(server, branch), do: GenServer.call(server, {:branch_files, branch})

  @spec create_branch(GenServer.server(), String.t(), String.t()) :: :ok
  def create_branch(server, base_ref, branch_name) do
    GenServer.call(server, {:create_branch, base_ref, branch_name})
  end

  @spec open_pr(GenServer.server(), Catapult.Delivery.HostPort.pr_request()) ::
          {:ok, Catapult.Delivery.HostPort.pr_ref()} | {:error, :no_such_branch}
  def open_pr(server, request), do: GenServer.call(server, {:open_pr, request})

  @spec get_pr(GenServer.server(), pos_integer()) :: map() | nil
  def get_pr(server, number), do: GenServer.call(server, {:get_pr, number})

  @doc "Arms the next `merge_forward/3` between `source` and `target` to return a conflict, once."
  @spec arm_merge_conflict(GenServer.server(), String.t(), String.t()) :: :ok
  def arm_merge_conflict(server, source, target) do
    GenServer.call(server, {:arm_merge_conflict, source, target})
  end

  @spec merge_forward(GenServer.server(), String.t(), String.t()) ::
          :ok | {:error, {:conflict, map()}} | {:error, :no_such_branch}
  def merge_forward(server, source, target) do
    GenServer.call(server, {:merge_forward, source, target})
  end

  @spec merge_pr(GenServer.server(), pos_integer(), Catapult.Delivery.HostPort.merge_method()) ::
          :ok | {:error, :no_such_pr} | {:error, :already_merged}
  def merge_pr(server, number, method), do: GenServer.call(server, {:merge_pr, number, method})

  @doc "Test/scenario setup: appends a review comment as if a human (or bot) had posted it."
  @spec seed_review_comment(GenServer.server(), pos_integer(), map()) :: :ok
  def seed_review_comment(server, pr_number, attrs) do
    GenServer.call(server, {:seed_review_comment, pr_number, attrs})
  end

  @spec list_review_comments(GenServer.server(), pos_integer()) :: [map()]
  def list_review_comments(server, pr_number) do
    GenServer.call(server, {:list_review_comments, pr_number})
  end

  @spec list_issue_comments(GenServer.server(), pos_integer()) :: [map()]
  def list_issue_comments(server, pr_number) do
    GenServer.call(server, {:list_issue_comments, pr_number})
  end

  @spec add_issue_comment(GenServer.server(), pos_integer(), String.t()) :: :ok
  def add_issue_comment(server, pr_number, body) do
    GenServer.call(server, {:add_issue_comment, pr_number, body})
  end

  @spec set_labels(GenServer.server(), pos_integer(), [String.t()]) :: :ok
  def set_labels(server, pr_number, labels),
    do: GenServer.call(server, {:set_labels, pr_number, labels})

  @spec get_labels(GenServer.server(), pos_integer()) :: [String.t()]
  def get_labels(server, pr_number), do: GenServer.call(server, {:get_labels, pr_number})

  @doc "Test/scenario setup: simulates CI reporting check runs against `sha`."
  @spec set_check_runs(GenServer.server(), String.t(), [map()]) :: :ok
  def set_check_runs(server, sha, runs), do: GenServer.call(server, {:set_check_runs, sha, runs})

  @spec list_check_runs(GenServer.server(), String.t()) :: [map()]
  def list_check_runs(server, sha), do: GenServer.call(server, {:list_check_runs, sha})

  ## Server

  @impl GenServer
  def init(state), do: {:ok, state}

  @impl GenServer
  def handle_call({:seed_branch, branch, files}, _from, state) do
    {:reply, :ok, %{state | branches: Map.put(state.branches, branch, files)}}
  end

  def handle_call({:branch_files, branch}, _from, state) do
    case Map.fetch(state.branches, branch) do
      {:ok, files} -> {:reply, {:ok, files}, state}
      :error -> {:reply, {:error, :no_such_branch}, state}
    end
  end

  def handle_call({:create_branch, base_ref, branch_name}, _from, state) do
    # No prior branch/commit has to have touched `base_ref` for this
    # to succeed — an unseeded ref (a repo's own default branch, most
    # commonly) is simply empty, the same way it exists in a real repo
    # before this port ever writes to it.
    base_files = Map.get(state.branches, base_ref, %{})

    branches =
      state.branches
      |> Map.put_new(base_ref, base_files)
      |> Map.put(branch_name, base_files)

    {:reply, :ok, %{state | branches: branches}}
  end

  def handle_call({:open_pr, request}, _from, state) do
    if Map.has_key?(state.branches, request.head) do
      number = state.next_pr_number

      pr = %{
        number: number,
        head: request.head,
        base: request.base,
        title: request.title,
        body: request.body,
        state: :open,
        merged_via: nil,
        head_sha: head_sha(request.head)
      }

      state = %{state | prs: Map.put(state.prs, number, pr), next_pr_number: number + 1}
      {:reply, {:ok, %{number: number, head_sha: pr.head_sha}}, state}
    else
      {:reply, {:error, :no_such_branch}, state}
    end
  end

  def handle_call({:get_pr, number}, _from, state) do
    {:reply, Map.get(state.prs, number), state}
  end

  def handle_call({:arm_merge_conflict, source, target}, _from, state) do
    {:reply, :ok, %{state | armed_conflicts: MapSet.put(state.armed_conflicts, {source, target})}}
  end

  def handle_call({:merge_forward, source, target}, _from, state) do
    cond do
      not Map.has_key?(state.branches, source) or not Map.has_key?(state.branches, target) ->
        {:reply, {:error, :no_such_branch}, state}

      MapSet.member?(state.armed_conflicts, {source, target}) ->
        state = %{state | armed_conflicts: MapSet.delete(state.armed_conflicts, {source, target})}
        {:reply, {:error, {:conflict, %{source: source, target: target}}}, state}

      true ->
        merged = Map.merge(state.branches[target], state.branches[source])
        {:reply, :ok, %{state | branches: Map.put(state.branches, target, merged)}}
    end
  end

  def handle_call({:merge_pr, number, method}, _from, state) do
    case Map.fetch(state.prs, number) do
      {:ok, %{state: :open} = pr} ->
        merged_base =
          Map.merge(Map.get(state.branches, pr.base, %{}), Map.get(state.branches, pr.head, %{}))

        state = %{
          state
          | branches: Map.put(state.branches, pr.base, merged_base),
            prs: Map.put(state.prs, number, %{pr | state: :merged, merged_via: method})
        }

        {:reply, :ok, state}

      {:ok, %{state: :merged}} ->
        {:reply, {:error, :already_merged}, state}

      :error ->
        {:reply, {:error, :no_such_pr}, state}
    end
  end

  def handle_call({:seed_review_comment, pr_number, attrs}, _from, state) do
    comment =
      Map.merge(
        %{
          id: state.next_comment_id,
          author_login: "octocat",
          author_type: "User",
          performed_via_github_app: nil,
          body: "",
          path: nil,
          line: nil,
          updated_at: nil
        },
        attrs
      )

    existing = Map.get(state.review_comments, pr_number, [])

    state = %{
      state
      | review_comments: Map.put(state.review_comments, pr_number, existing ++ [comment]),
        next_comment_id: state.next_comment_id + 1
    }

    {:reply, :ok, state}
  end

  def handle_call({:list_review_comments, pr_number}, _from, state) do
    {:reply, Map.get(state.review_comments, pr_number, []), state}
  end

  def handle_call({:list_issue_comments, pr_number}, _from, state) do
    {:reply, Map.get(state.issue_comments, pr_number, []), state}
  end

  def handle_call({:add_issue_comment, pr_number, body}, _from, state) do
    comment = %{id: state.next_comment_id, body: body}
    existing = Map.get(state.issue_comments, pr_number, [])

    state = %{
      state
      | issue_comments: Map.put(state.issue_comments, pr_number, existing ++ [comment]),
        next_comment_id: state.next_comment_id + 1
    }

    {:reply, :ok, state}
  end

  def handle_call({:set_labels, pr_number, labels}, _from, state) do
    {:reply, :ok, %{state | labels: Map.put(state.labels, pr_number, labels)}}
  end

  def handle_call({:get_labels, pr_number}, _from, state) do
    {:reply, Map.get(state.labels, pr_number, []), state}
  end

  def handle_call({:set_check_runs, sha, runs}, _from, state) do
    {:reply, :ok, %{state | check_runs: Map.put(state.check_runs, sha, runs)}}
  end

  def handle_call({:list_check_runs, sha}, _from, state) do
    {:reply, Map.get(state.check_runs, sha, []), state}
  end

  defp head_sha(branch), do: "fake-sha-#{branch}-#{System.unique_integer([:positive])}"
end
