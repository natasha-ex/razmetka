defmodule Razmetka do
  @moduledoc """
  Priority-dispatch sentence classifier with pluggable ML fallback.

  Extends Yargy's `defmatch` bag-of-features matchers with:

  - **`defclassify`** — dispatches morph-tagged tokens through named matchers
    in priority order; when no grammar matches, delegates to a pluggable
    classifier (FRIDA, fastText, or any module implementing `Razmetka.Classifier`)
  - Reuses `defmatch` from `Yargy.Grammar` — same terminal predicates,
    same bag-of-features combinators

  ## Example

      defmodule MyApp.SentenceClassifier do
        use Yargy.Grammar
        use Razmetka

        defmatch(:demand, any_token(all([lemma(~w[требовать просить]), gram("VERB")])))
        defmatch(:norm_framing, any_token(lemma(~w[соответствие согласно])))

        defclassify classifier: MyApp.FridaClassifier, default: :fact do
          :demand -> demand?()
          :norm   -> norm_framing?()
        end
      end

      MyApp.SentenceClassifier.classify_text("Истец требует возмещения")
      #=> {:demand, %{confidence: :grammar}}

  ## Pluggable classifiers

  Any module implementing `Razmetka.Classifier` can serve as the fallback:

      defmodule MyApp.FridaClassifier do
        @behaviour Razmetka.Classifier

        @impl true
        def classify(text, _opts) do
          {:fact, 0.72}
        end
      end
  """

  defmacro __using__(_opts) do
    quote do
      import Razmetka, only: [defclassify: 1, defclassify: 2]
      Module.register_attribute(__MODULE__, :razmetka_rules, accumulate: false)
      Module.register_attribute(__MODULE__, :razmetka_opts, accumulate: false)
      @before_compile Razmetka
    end
  end

  @doc ~S"""
  Defines the classification pipeline using idiomatic Elixir syntax.

  Each clause maps a type atom to a boolean expression over `defmatch` matchers.
  Zero-arity `name?()` calls are rewritten to receive the `tokens` argument.
  Standard `and`, `or`, `not`, and parentheses work naturally.

  Two variables are in scope: `tokens` (morph-tagged list) and `text` (raw string).

  ## Options

  - `:classifier` — module implementing `Razmetka.Classifier` (optional)
  - `:default` — type when nothing matches and no classifier (default: `:unknown`)
  - `:threshold` — minimum classifier confidence (default: `0.40`)

  ## Example

      defclassify classifier: MyApp.FridaClassifier, default: :fact do
        :procedural_title -> title_base?() and (pretrial?() or short?())
        :norm             -> has_law_ref?(tokens, text) and norm_framing?()
        :demand           -> demand_verb?()
      end
  """
  defmacro defclassify(opts \\ [], do: block) do
    rules = parse_clauses(block)

    quote do
      @razmetka_rules unquote(Macro.escape(rules))
      @razmetka_opts unquote(opts)
    end
  end

  defp parse_clauses({:->, _, _} = single), do: [parse_clause(single)]
  defp parse_clauses({:__block__, _, clauses}), do: Enum.map(clauses, &parse_clause/1)
  defp parse_clauses(clauses) when is_list(clauses), do: Enum.map(clauses, &parse_clause/1)

  defp parse_clause({:->, _, [[type], condition]}), do: {type, condition}

  defmacro __before_compile__(env) do
    rules = Module.get_attribute(env.module, :razmetka_rules)
    opts = Module.get_attribute(env.module, :razmetka_opts) || []

    if rules do
      generate_classify_fns(rules, opts)
    else
      nil
    end
  end

  defp generate_classify_fns(rules, opts) do
    classifier_mod = Keyword.get(opts, :classifier)
    default = Keyword.get(opts, :default, :unknown)
    threshold = Keyword.get(opts, :threshold, 0.40)

    tokens_var = Macro.var(:tokens, __MODULE__)
    text_var = Macro.var(:text, __MODULE__)

    branches =
      Enum.map(rules, fn {type, condition_ast} ->
        rewritten = rewrite_matchers(condition_ast, tokens_var, text_var)

        {:->, [], [[rewritten], {:{}, [], [type, {:%{}, [], [confidence: :grammar]}]}]}
      end)

    fallback =
      if classifier_mod do
        {:->, [],
         [
           [true],
           quote do
             case unquote(classifier_mod).classify(unquote(text_var), []) do
               {pred_type, score} when score >= unquote(threshold) ->
                 {pred_type, %{confidence: :classifier, score: score}}

               {_pred_type, score} ->
                 {unquote(default), %{confidence: :low, score: score}}

               nil ->
                 {unquote(default), %{confidence: :low}}
             end
           end
         ]}
      else
        {:->, [], [[true], {:{}, [], [default, {:%{}, [], [confidence: :low]}]}]}
      end

    all_branches = branches ++ [fallback]

    quote do
      @doc "Classifies morph-tagged tokens. Returns `{type, metadata}`."
      def classify(unquote(tokens_var), unquote(text_var) \\ "")
          when is_list(unquote(tokens_var)) do
        cond do
          unquote(all_branches)
        end
      end

      @doc "Classifies raw text (tokenizes and morph-tags first)."
      def classify_text(unquote(text_var)) when is_binary(unquote(text_var)) do
        unquote(tokens_var) = Yargy.Pipeline.morph_tokenize(unquote(text_var))
        classify(unquote(tokens_var), unquote(text_var))
      end
    end
  end

  # Rewrites condition AST:
  # - Zero-arity `name?()` → `name?(tokens_var)` (inject tokens)
  # - `tokens` / `text` variable refs → bound to generated function scope
  # - `and`, `or`, `not` — standard Elixir, left as-is by prewalk
  defp rewrite_matchers(ast, tokens_var, text_var) do
    Macro.prewalk(ast, fn
      {name, meta, []} when is_atom(name) ->
        {name, meta, [tokens_var]}

      {var_name, _meta, context} when var_name == :tokens and is_atom(context) ->
        tokens_var

      {var_name, _meta, context} when var_name == :text and is_atom(context) ->
        text_var

      other ->
        other
    end)
  end
end
