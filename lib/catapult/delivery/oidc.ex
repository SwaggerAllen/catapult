defmodule Catapult.Delivery.Oidc do
  @moduledoc """
  Validates a GitHub Actions OIDC bearer (v5 §7.12.1): signature and
  freshness via `joken_jwks` against GitHub's published JWKS
  (`Catapult.Delivery.Oidc.Token`), then audience + `repository` +
  `run_id` matched to the plane's own dispatch record. Stock
  joken/joken_jwks machinery — no custom crypto.

  `run_id` is checked two ways depending on whether the dispatch
  record has already recorded GitHub's numeric run id: **unset**
  (this is the run's first authenticated call) accepts any claimed
  `run_id` and the caller is expected to bind it;  **set** requires
  the claim to match exactly — a second run cannot hijack a `run_key`
  a first run already claimed.
  """

  alias Catapult.Delivery.Oidc.Token

  @type failure ::
          Joken.error_reason()
          | {:repository_mismatch, expected: String.t(), found: term()}
          | {:run_id_mismatch, expected: String.t(), found: term()}

  @doc """
  Verifies `token` and that it names `repo_owner/repo_name` as its
  `repository` claim; `expected_run_id` (nil if not yet bound) is
  matched as described above.
  """
  @spec verify(String.t(), String.t(), String.t(), String.t() | nil) ::
          {:ok, map()} | {:error, failure()}
  def verify(token, repo_owner, repo_name, expected_run_id) do
    with {:ok, claims} <- Token.verify_and_validate(token) do
      claims
      |> check_repository(repo_owner, repo_name)
      |> check_run_id(expected_run_id)
    end
  end

  defp check_repository(claims, repo_owner, repo_name) do
    expected = "#{repo_owner}/#{repo_name}"

    if Map.get(claims, "repository") == expected do
      {:ok, claims}
    else
      {:error, {:repository_mismatch, expected: expected, found: Map.get(claims, "repository")}}
    end
  end

  defp check_run_id({:error, _} = error, _expected_run_id), do: error
  defp check_run_id({:ok, claims}, nil), do: {:ok, claims}

  defp check_run_id({:ok, claims}, expected_run_id) do
    if Map.get(claims, "run_id") == expected_run_id do
      {:ok, claims}
    else
      {:error, {:run_id_mismatch, expected: expected_run_id, found: Map.get(claims, "run_id")}}
    end
  end
end
