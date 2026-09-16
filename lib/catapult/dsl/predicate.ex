defmodule Catapult.Dsl.Predicate do
  @moduledoc """
  The predicate language (`chain.md` #37): six operator families —
  comparison, boolean, edge counting, existential, universal,
  reachability — over exactly four slots (`scope_filter`,
  `cardinality.when`, an edge `constraint`, a flow `completion`).
  Deliberately not Turing-complete: no arithmetic, no strings, no
  regex, no variables beyond the walked path a form binds.

  Parses a predicate expression into a plain-data AST. What a path
  segment or edge name actually resolves to is a cross-reference the
  loader checks with the rest of the bundle in view (`chain.md`
  §13); this module only rejects what the grammar itself forbids.

  ## Grammar

      predicate  := or_expr
      or_expr    := and_expr ("OR" and_expr)*
      and_expr   := not_expr ("AND" not_expr)*
      not_expr   := "NOT" not_expr | atom
      atom       := "(" predicate ")"
                  | operand comparator operand
                  | "has_edge" "(" ident ")"
                  | "count" "(" ident ")" comparator number
                  | "exists" "(" path "where" predicate ")"
                  | ("all" | "any") "(" path "->" ident ")"
                  | "reaches" "(" ident "," ident ["," "via" "=" "[" ident_list "]"] ")"
                  | ident                                  # bare boolean field
      operand    := path | number | "true" | "false" | ident
      comparator := "==" | "!=" | "<" | ">" | "<=" | ">="
      path       := ident ("." ident)*

  `predicates.yaml` composes these under a name (`chain.md` #37); a
  named reference (`scope_filter: is_domain`) is not itself predicate
  syntax and is resolved by the loader against that file, not by this
  parser.
  """

  @type path :: [String.t()]
  @type operand :: {:path, path()} | {:literal, boolean() | number() | String.t()}
  @type comparator :: :eq | :neq | :lt | :gt | :lte | :gte

  @type t ::
          {:and, t(), t()}
          | {:or, t(), t()}
          | {:not, t()}
          | {:compare, comparator(), operand(), operand()}
          | {:field, path()}
          | {:has_edge, String.t()}
          | {:count, String.t(), comparator(), integer()}
          | {:exists, path(), t()}
          | {:all, path(), String.t()}
          | {:any, path(), String.t()}
          | {:reaches, String.t(), String.t(), via: [String.t()]}

  @keywords ~w(AND OR NOT where via has_edge count exists all any reaches true false)

  @doc "Parses a predicate expression, or reports where it stopped being one."
  @spec parse(String.t()) :: {:ok, t()} | {:error, String.t()}
  def parse(source) when is_binary(source) do
    with {:ok, tokens} <- tokenize(source),
         {:ok, ast, []} <- or_expr(tokens) do
      {:ok, ast}
    else
      {:ok, _ast, leftover} ->
        {:error, "predicate #{inspect(source)} has trailing input: #{inspect(join(leftover))}"}

      {:error, reason} ->
        {:error, "predicate #{inspect(source)} #{reason}"}
    end
  end

  ## Tokenizer

  @token_regex ~r/\A\s*(==|!=|<=|>=|->|[()<>,\[\]=.]|[A-Za-z_][A-Za-z0-9_]*|-?\d+(?:\.\d+)?)/

  defp tokenize(source), do: tokenize(source, [])

  defp tokenize(rest, acc) do
    trimmed = String.trim_leading(rest)

    cond do
      trimmed == "" ->
        {:ok, Enum.reverse(acc)}

      match = Regex.run(@token_regex, trimmed) ->
        [whole, token] = match
        remainder = String.slice(trimmed, String.length(whole)..-1//1)
        tokenize(remainder, [classify(token) | acc])

      true ->
        {:error, "has unrecognized syntax at #{inspect(trimmed)}"}
    end
  end

  defp classify(token) when token in @keywords, do: {:kw, token}
  defp classify(token) when token in ~w(== != <= >=), do: {:cmp, comparator(token)}
  defp classify(token) when token in ~w(< >), do: {:cmp, comparator(token)}
  defp classify("("), do: {:punct, "("}
  defp classify(")"), do: {:punct, ")"}
  defp classify("["), do: {:punct, "["}
  defp classify("]"), do: {:punct, "]"}
  defp classify(","), do: {:punct, ","}
  defp classify("."), do: {:punct, "."}
  defp classify("="), do: {:punct, "="}
  defp classify("->"), do: {:punct, "->"}

  defp classify(token) do
    if Regex.match?(~r/\A-?\d+(\.\d+)?\z/, token) do
      {:num, parse_number(token)}
    else
      {:ident, token}
    end
  end

  defp parse_number(token) do
    if String.contains?(token, "."), do: String.to_float(token), else: String.to_integer(token)
  end

  defp comparator("=="), do: :eq
  defp comparator("!="), do: :neq
  defp comparator("<"), do: :lt
  defp comparator(">"), do: :gt
  defp comparator("<="), do: :lte
  defp comparator(">="), do: :gte

  defp join(tokens), do: Enum.map_join(tokens, " ", &render_token/1)
  defp render_token({_kind, value}), do: to_string(value)

  ## Recursive descent

  defp or_expr(tokens) do
    with {:ok, left, rest} <- and_expr(tokens) do
      or_expr_rest(left, rest)
    end
  end

  defp or_expr_rest(left, [{:kw, "OR"} | rest]) do
    with {:ok, right, rest} <- and_expr(rest) do
      or_expr_rest({:or, left, right}, rest)
    end
  end

  defp or_expr_rest(left, rest), do: {:ok, left, rest}

  defp and_expr(tokens) do
    with {:ok, left, rest} <- not_expr(tokens) do
      and_expr_rest(left, rest)
    end
  end

  defp and_expr_rest(left, [{:kw, "AND"} | rest]) do
    with {:ok, right, rest} <- not_expr(rest) do
      and_expr_rest({:and, left, right}, rest)
    end
  end

  defp and_expr_rest(left, rest), do: {:ok, left, rest}

  defp not_expr([{:kw, "NOT"} | rest]) do
    with {:ok, inner, rest} <- not_expr(rest), do: {:ok, {:not, inner}, rest}
  end

  defp not_expr(tokens), do: atom(tokens)

  defp atom([{:punct, "("} | rest]) do
    with {:ok, inner, rest} <- or_expr(rest),
         {:ok, rest} <- expect(rest, {:punct, ")"}) do
      {:ok, inner, rest}
    end
  end

  defp atom([{:kw, "has_edge"} | rest]) do
    with {:ok, rest} <- expect(rest, {:punct, "("}),
         {:ok, edge, rest} <- ident(rest),
         {:ok, rest} <- expect(rest, {:punct, ")"}) do
      {:ok, {:has_edge, edge}, rest}
    end
  end

  defp atom([{:kw, "count"} | rest]) do
    with {:ok, rest} <- expect(rest, {:punct, "("}),
         {:ok, edge, rest} <- ident(rest),
         {:ok, rest} <- expect(rest, {:punct, ")"}),
         {:ok, cmp, rest} <- comparator_token(rest),
         {:ok, n, rest} <- integer_token(rest) do
      {:ok, {:count, edge, cmp, n}, rest}
    end
  end

  defp atom([{:kw, "exists"} | rest]) do
    with {:ok, rest} <- expect(rest, {:punct, "("}),
         {:ok, path, rest} <- path(rest),
         {:ok, rest} <- expect(rest, {:kw, "where"}),
         {:ok, predicate, rest} <- or_expr(rest),
         {:ok, rest} <- expect(rest, {:punct, ")"}) do
      {:ok, {:exists, path, predicate}, rest}
    end
  end

  defp atom([{:kw, quantifier} | rest]) when quantifier in ["all", "any"] do
    with {:ok, rest} <- expect(rest, {:punct, "("}),
         {:ok, path, rest} <- path(rest),
         {:ok, rest} <- expect(rest, {:punct, "->"}),
         {:ok, field, rest} <- ident(rest),
         {:ok, rest} <- expect(rest, {:punct, ")"}) do
      {:ok, {String.to_existing_atom(quantifier), path, field}, rest}
    end
  end

  defp atom([{:kw, "reaches"} | rest]) do
    with {:ok, rest} <- expect(rest, {:punct, "("}),
         {:ok, a, rest} <- ident(rest),
         {:ok, rest} <- expect(rest, {:punct, ","}),
         {:ok, b, rest} <- ident(rest),
         {:ok, via, rest} <- reaches_via(rest),
         {:ok, rest} <- expect(rest, {:punct, ")"}) do
      {:ok, {:reaches, a, b, via: via}, rest}
    end
  end

  defp atom(tokens) do
    with {:ok, left, rest} <- operand(tokens) do
      comparison_or_bare(left, rest)
    end
  end

  defp comparison_or_bare({:path, path}, [{:cmp, _} | _] = rest) do
    with {:ok, cmp, rest} <- comparator_token(rest),
         {:ok, right, rest} <- operand(rest) do
      {:ok, {:compare, cmp, {:path, path}, right}, rest}
    end
  end

  defp comparison_or_bare({:literal, _} = left, [{:cmp, _} | _] = rest) do
    with {:ok, cmp, rest} <- comparator_token(rest),
         {:ok, right, rest} <- operand(rest) do
      {:ok, {:compare, cmp, left, right}, rest}
    end
  end

  defp comparison_or_bare({:path, path}, rest), do: {:ok, {:field, path}, rest}

  defp comparison_or_bare({:literal, value}, _rest) do
    {:error, "has a bare literal #{inspect(value)} where a predicate was expected"}
  end

  defp reaches_via([{:punct, ","}, {:kw, "via"}, {:punct, "="}, {:punct, "["} | rest]) do
    with {:ok, names, rest} <- ident_list(rest),
         {:ok, rest} <- expect(rest, {:punct, "]"}) do
      {:ok, names, rest}
    end
  end

  defp reaches_via(rest), do: {:ok, [], rest}

  defp ident_list(rest) do
    with {:ok, first, rest} <- ident(rest) do
      ident_list_rest([first], rest)
    end
  end

  defp ident_list_rest(acc, [{:punct, ","} | rest]) do
    with {:ok, next, rest} <- ident(rest), do: ident_list_rest([next | acc], rest)
  end

  defp ident_list_rest(acc, rest), do: {:ok, Enum.reverse(acc), rest}

  ## Operands and paths

  defp operand([{:kw, "true"} | rest]), do: {:ok, {:literal, true}, rest}
  defp operand([{:kw, "false"} | rest]), do: {:ok, {:literal, false}, rest}
  defp operand([{:num, n} | rest]), do: {:ok, {:literal, n}, rest}

  defp operand([{:ident, _} | _] = tokens) do
    with {:ok, path, rest} <- path(tokens) do
      case {path, rest} do
        {[single], _} -> {:ok, single_operand(single), rest}
        {_many, _} -> {:ok, {:path, path}, rest}
      end
    end
  end

  defp operand(tokens), do: {:error, "expected a value at #{inspect(join(tokens))}"}

  # A single bare word with no dot could be either a path segment (a
  # boolean field, `is_domain`) or an enum literal (`presentational`).
  # Both are legal without arithmetic or strings to tell them apart, so
  # it carries as a one-segment path and the loader resolves it against
  # the field it is compared to.
  defp single_operand(word), do: {:path, [word]}

  defp path(tokens) do
    with {:ok, first, rest} <- ident(tokens) do
      path_rest([first], rest)
    end
  end

  defp path_rest(acc, [{:punct, "."}, {:ident, next} | rest]), do: path_rest([next | acc], rest)
  defp path_rest(acc, rest), do: {:ok, Enum.reverse(acc), rest}

  defp ident([{:ident, name} | rest]), do: {:ok, name, rest}
  defp ident([{:kw, name} | rest]), do: {:ok, name, rest}
  defp ident(tokens), do: {:error, "expected a name at #{inspect(join(tokens))}"}

  defp comparator_token([{:cmp, cmp} | rest]), do: {:ok, cmp, rest}
  defp comparator_token(tokens), do: {:error, "expected a comparator at #{inspect(join(tokens))}"}

  defp integer_token([{:num, n} | rest]) when is_integer(n), do: {:ok, n, rest}
  defp integer_token(tokens), do: {:error, "expected an integer at #{inspect(join(tokens))}"}

  defp expect([token | rest], token), do: {:ok, rest}

  defp expect(tokens, {_kind, value}) do
    {:error, "expected #{inspect(value)} at #{inspect(join(tokens))}"}
  end
end
