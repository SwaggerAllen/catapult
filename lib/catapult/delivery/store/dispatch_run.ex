defmodule Catapult.Delivery.Store.DispatchRun do
  @moduledoc """
  One row per dispatched agent run (`delivery_dispatch_runs`): the
  correlation record between a plane-minted dispatch and the runner's
  OIDC-authenticated context-fetch/result-report calls back
  (`systems/generation.md`, v5 §7.12.1). `id` is the `run_key` handed
  to the runner as a dispatch input — never a secret, since dispatch
  inputs are visible-log territory (v5 §7.12.1) — and is the plane's
  own correlation handle; GitHub's numeric `github_run_id` is recorded
  from the first authenticated call and matched on every call after.

  `flow_id` is ORC-114's own addition — nullable, resolved by the
  dispatching caller the same way `Catapult.Delivery.FeatureLifecycle`
  already resolves a `DraftCommitted`/`RunFailed`'s flow
  (`Catapult.Delivery.Store.current_open_flow_id/1`) — so `ticket` can
  read a flow's own run list (`dispatch_runs_for_flow/2`) beside its
  PR list.

  `outcome` and `credential_used` are ORC-216's own addition — what
  "the plane recorded it" resolves to for the milestone boundary's
  live suite (`systems/delivery.md`'s ORC-216 entry). `outcome` is the
  fine-grained result a result-report actually carried
  (`:success`/`:limit_class_failure`/`:other_failure`), set alongside
  the coarse `status` above by `complete_dispatch_run/4`;
  `credential_used` is the name the harness actually spent, out of the
  ordered pair `credential_sent` offered. Both `nil` until a result is
  reported.
  """

  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: false}

  schema "delivery_dispatch_runs" do
    field :project_id, :string
    field :node_id, :string
    field :flow_id, :string
    field :tier, :string
    field :scope_key, :map, default: %{}
    field :repo_owner, :string
    field :repo_name, :string
    field :root_tag, :string
    field :rendered_prompt, :string
    field :credential_sent, {:array, :string}
    field :github_run_id, :string
    field :status, Ecto.Enum, values: [:dispatched, :context_fetched, :completed, :failed]
    field :outcome, Ecto.Enum, values: [:success, :limit_class_failure, :other_failure]
    field :credential_used, :string

    timestamps(type: :utc_datetime_usec, updated_at: :updated_at)
  end
end
