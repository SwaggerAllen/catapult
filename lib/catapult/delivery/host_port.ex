defmodule Catapult.Delivery.HostPort do
  @moduledoc """
  The host port (`systems/generation.md`, `systems/delivery.md`; v5
  §7.12.1, §7.17): outbound GitHub actions with two adapters, exactly
  the "ports with fakes" shape every external system in this codebase
  follows (conventions §9). `Catapult.Delivery.HostPort.Actions` is
  the only adapter built here; nothing outside it may assume Actions
  (`systems/generation.md` — the execution substrate is an adapter
  behind this port, not the port itself).

  The rest of the protocol — serving the rendered context back and
  accepting the result — is inbound (the runner calls the plane), so
  it is not a port callback; `Catapult.Delivery.Dispatch` carries it,
  identically for both adapters (the fake's synchronous loop calls the
  exact same result path a real inbound HTTP call would).

  **Second operation, ORC-10:** `reset_repo/2` resets a bound repo's
  *fixture* content — never generated artifacts, which still land only
  through `Dispatch`'s result-report path into the plane's own store
  (`systems/delivery.md`'s ORC-10 entry). A bound repo has to carry a
  `workflow_dispatch` file before GitHub accepts a dispatch to it at
  all, and no role in this pipeline has a route to author a file
  inside a *different* repository, so the plane writes it there
  instead: the caller hands over the exact repo-relative paths and
  content to write (never read off this module's own disk — a fixture
  is the caller's fact, not the port's), and this operation overwrites
  each one. `HostPort.Fake` implements this too, so the offline chain
  test exercises the same reset path a live run does rather than a
  live-only mechanism.

  **ORC-216: `reset_repo/2` reports the ref it produced.** It returns
  `{:ok, ref}` rather than bare `:ok` — the default branch's head
  commit SHA once `files` lands, in `HostPort.Actions`, and a
  synthesized one in `HostPort.Fake` (`systems/delivery.md`'s ORC-216
  entry). Provisioning a test project is the first caller with
  anywhere to put a ref: `Catapult.Delivery.intake_raft/2` takes one
  explicitly rather than defaulting to whatever the default branch
  happens to be, and the fixture files `reset_repo/2` just wrote are
  the only source of a ref guaranteed to postdate them. ORC-228
  (`systems/delivery.md`'s ORC-228 entry) changes what produces
  `HostPort.Actions`' sha — a single Git Data commit rather than a
  head re-read after the last per-file PUT — without touching this
  contract: `{:ok, ref}` in, `{:ok, ref}` out, either way.

  **ORC-31: the rest of Phase 4's operation vocabulary** —
  feature-lifecycle PR management and decline harvesting
  (`systems/delivery.md`'s ORC-31 entry). Each callback traces to the
  protocol clause it serves rather than to what GitHub happens to
  expose:

  - `create_branch/3`, `open_pr/2`, `merge_forward/3`, `merge_pr/3` —
    v5 §7.5's topology (child PR → feature branch, feature PR → main;
    merge-forward absorbs drift continuously and surfaces a conflict
    as a real signal, `{:error, {:conflict, _}}`, never a silent
    resolution).
  - `set_pr_labels/3` — how the plane marks `ci:docs`/`ci:code` for
    §7.7's job selection.
  - `read_check_status/2` — answers back keyed to head SHA regardless
    of base branch, exactly as §7.7 requires.
  - `read_review_comments/3`, `write_marker_comment/4` — §7.4's
    harvesting split, two different GitHub comment kinds by design:
    `read_review_comments/3` pulls line-anchored review comments (the
    harvesting source, filtered to human authorship — see
    `systems/delivery.md`'s author-identity-filter entry),
    `write_marker_comment/4` posts plane-authored, issue-level PR
    comments (bounces, findings) rendered by `HostPort.Marker`.
  - `read_diff/2` — this system's own restated invariant (conventions
    §11): the port moves refs and reads diffs, it never checks out.

  `read_review_comments/3` and `read_check_status/2` page to
  exhaustion in both adapters — neither asserts an unmeasured bound
  (`systems/delivery.md`'s pagination entry; ORC-101 found the
  single-page version of this defect once already, in the Go
  pipeline's own adapter).

  **ORC-33: the shape ORC-31 left short** — `reset_repo/2` looks
  adjacent to a content-write operation and isn't: it takes no branch
  argument and always resolves against the repo's default branch,
  which is wrong for pushing a committed draft's body onto a feature
  branch (`systems/delivery.md`'s ORC-33 entry).

  - `commit_files/4` — a per-file Contents-API shape (read the blob
    sha if the file exists, PUT with it if so): `reset_repo/2`'s own
    shape too, until ORC-228 moved that operation onto a single Git
    Data commit (`systems/delivery.md`'s ORC-228 entry).
    `commit_files/4` keeps the per-file shape — its calls never grow
    with a fixture set the way `reset_repo/2`'s did — generalized with
    an explicit `branch:` ref and a caller-supplied commit message.
  - `update_pr_body/3` — a PATCH `HostPort` has never needed before
    now because nothing before ORC-33 edits a PR after opening it. The
    PR body is regenerated whole on every push, never appended to
    (`systems/delivery.md`'s ORC-33 entry).

  As with `dispatch_run/1` and `reset_repo/2`, every operation here
  lands in `HostPort.Actions` and `HostPort.Fake` in the same change —
  never one ahead of the other.

  **ORC-107: `read_directory/3`, the intake raft's own read.** Every
  file directly under `path` at `ref`, `filename => content`
  (`systems/delivery.md`'s Discovery/Reading-it entries) — a missing
  or empty directory answers `{:ok, %{}}` rather than an error, the
  same "a role with no documents" shape dsl-syntax.md §7 gives the
  walk this feeds. Unlike `reset_repo/2`'s implicit default-branch
  read, `ref` is explicit: intake pins against a commit a caller
  names, never whatever the default branch happens to be the moment
  it runs.
  """

  alias Catapult.Delivery.HostPort.Marker

  @type request :: %{
          project_id: binary(),
          node_id: binary(),
          tier: String.t(),
          scope_key: map(),
          root_tag: String.t(),
          rendered_prompt: String.t(),
          credential_names: [String.t()],
          stub_mode: boolean()
        }

  @type files :: %{String.t() => String.t()}

  @type pr_number :: pos_integer()

  @type pr_request :: %{
          head: String.t(),
          base: String.t(),
          title: String.t(),
          body: String.t()
        }

  @type pr_ref :: %{number: pr_number(), head_sha: String.t()}

  @type merge_method :: :merge | :squash

  @type review_comment :: %{
          id: term(),
          author_login: String.t(),
          body: String.t(),
          path: String.t() | nil,
          line: integer() | nil,
          updated_at: String.t() | nil
        }

  @type check_run :: %{
          name: String.t(),
          status: String.t(),
          conclusion: String.t() | nil
        }

  @callback dispatch_run(request()) :: {:ok, %{run_key: binary()}} | {:error, term()}
  @callback reset_repo(project_id :: binary(), files()) ::
              {:ok, ref :: String.t()} | {:error, term()}

  @callback create_branch(
              project_id :: binary(),
              base_ref :: String.t(),
              branch_name :: String.t()
            ) ::
              :ok | {:error, term()}

  @callback open_pr(project_id :: binary(), pr_request()) :: {:ok, pr_ref()} | {:error, term()}

  @callback merge_forward(
              project_id :: binary(),
              source_branch :: String.t(),
              target_branch :: String.t()
            ) ::
              :ok | {:error, {:conflict, term()}} | {:error, term()}

  @callback merge_pr(project_id :: binary(), pr_number(), merge_method()) ::
              :ok | {:error, term()}

  @callback read_review_comments(project_id :: binary(), pr_number(), since :: DateTime.t() | nil) ::
              {:ok, [review_comment()]} | {:error, term()}

  @callback write_marker_comment(
              project_id :: binary(),
              pr_number(),
              Marker.kind(),
              Marker.payload()
            ) ::
              :ok | {:error, term()}

  @callback set_pr_labels(project_id :: binary(), pr_number(), labels :: [String.t()]) ::
              :ok | {:error, term()}

  @callback read_check_status(project_id :: binary(), head_sha :: String.t()) ::
              {:ok, [check_run()]} | {:error, term()}

  @callback read_diff(project_id :: binary(), pr_number()) ::
              {:ok, String.t()} | {:error, term()}

  @callback commit_files(
              project_id :: binary(),
              branch :: String.t(),
              files(),
              message :: String.t()
            ) :: :ok | {:error, term()}

  @callback update_pr_body(project_id :: binary(), pr_number(), body :: String.t()) ::
              :ok | {:error, term()}

  @callback read_directory(project_id :: binary(), ref :: String.t(), path :: String.t()) ::
              {:ok, files()} | {:error, term()}
end
