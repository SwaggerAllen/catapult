defmodule Catapult.Dsl.Grammar do
  @moduledoc """
  Validates a committed draft body against a tier's grammar —
  `draft.root_tag` + XSD (dsl-syntax.md §10) — at commit time. One
  validator source for the commit-time rejection engine's aggregate
  gates on (via generation's command edge, `systems/core_dsl.md`'s
  "engine and generation call it") and any future pre-flight check
  (a CLI, later); both call this module rather than two
  implementations that could drift.

  Built on `:xmerl_scan`/`:xmerl_xsd` — OTP-shipped (`xmerl`), so
  validating a body needs no new dependency; the transport ban
  (`systems/foundation.md`'s `ErlangHttp` policy) is about HTTP
  clients specifically and has no opinion on an XML parser.

  A schema path (`draft.grammar`, or a review tier's own top-level
  `grammar:`) is bundle-relative and resolved across the bundle's
  `extends:` chain the same way `Catapult.Dsl.Extends.resolve_files/2`
  resolves tier/edge/flow globs — specific-first, so a layer's own
  copy of a schema wins over a base layer's, and a schema the leaf
  bundle never copies (the platform-wide review grammar, living only
  in its base layer) still resolves.
  """

  alias Catapult.Dsl.Extends

  @type failure ::
          {:schema_not_found, String.t()}
          | {:malformed_xml, String.t()}
          | {:root_tag_mismatch, expected: String.t(), found: String.t()}
          | {:schema_invalid, term()}

  @doc """
  Validates `body` (an XML-fragmented-markdown draft, dsl-syntax.md
  §10) against the grammar named by `root_tag` + `grammar_path`
  (bundle-relative, e.g. `"schemas/comparch.xsd"`) for the bundle
  `bundle_name` under `bundles_root` (the `bundles/` directory itself,
  matching `Catapult.Dsl.Chain.load/3`'s own first argument).
  """
  @spec validate(String.t(), String.t(), String.t(), String.t(), String.t()) ::
          :ok | {:error, failure()}
  def validate(bundles_root, bundle_name, root_tag, grammar_path, body) do
    with {:ok, schema_path} <- resolve_schema(bundles_root, bundle_name, grammar_path),
         {:ok, element} <- parse(body),
         :ok <- check_root_tag(element, root_tag) do
      validate_against_schema(element, schema_path)
    end
  end

  defp resolve_schema(bundles_root, bundle_name, grammar_path) do
    case Extends.load_layers(bundles_root, bundle_name) do
      {:ok, layers} ->
        case Extends.resolve_content_path(layers, grammar_path) do
          nil -> {:error, {:schema_not_found, grammar_path}}
          path -> {:ok, path}
        end

      {:error, reason} when is_binary(reason) ->
        {:error, {:schema_not_found, reason}}

      {:error, [problem | _]} ->
        {:error, {:schema_not_found, problem}}
    end
  end

  defp parse(body) do
    {element, _rest} = :xmerl_scan.string(String.to_charlist(body))
    {:ok, element}
  rescue
    # `:xmerl_scan` raises on malformed XML rather than returning an
    # error tuple — caught here so a body that isn't well-formed XML
    # is typed feedback (conventions §8), not a crash.
    error -> {:error, {:malformed_xml, Exception.format(:error, error, __STACKTRACE__)}}
  catch
    :exit, reason -> {:error, {:malformed_xml, inspect(reason)}}
  end

  defp check_root_tag(element, root_tag) do
    found = element |> elem(1) |> to_string()

    if found == root_tag do
      :ok
    else
      {:error, {:root_tag_mismatch, expected: root_tag, found: found}}
    end
  end

  defp validate_against_schema(element, schema_path) do
    # `:xmerl_xsd` builds its on-disk cache path via list concatenation
    # (`SchemaPath ++ ".tab2"`), which raises on an Elixir binary — the
    # path must be a charlist.
    case :xmerl_xsd.process_schema(String.to_charlist(schema_path)) do
      {:ok, schema_state} -> do_validate(element, schema_state)
      {:error, reason} -> {:error, {:schema_invalid, reason}}
    end
  rescue
    error -> {:error, {:schema_invalid, Exception.format(:error, error, __STACKTRACE__)}}
  end

  defp do_validate(element, schema_state) do
    case :xmerl_xsd.validate(element, schema_state) do
      {:error, reasons} -> {:error, {:schema_invalid, reasons}}
      {_validated, _final_state} -> :ok
    end
  end
end
