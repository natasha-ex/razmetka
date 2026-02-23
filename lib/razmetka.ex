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

        defmatch :demand, any_token(all([
          lemma(~w[требовать просить взыскать]),
          gram("VERB")
        ]))

        defmatch :norm_framing, any_token(lemma(~w[соответствие согласно основание]))

        defmatch :evidence, all_of([
          any_token(lemma(~w[подтверждаться подтвердить])),
          any_token(lemma(~w[акт квитанция чек выписка]))
        ])

        defclassify priority: [
          {:demand,   when: :demand},
          {:norm,     when: :norm_framing},
          {:evidence, when: :evidence},
        ],
        classifier: MyApp.FridaClassifier,
        default: :fact
      end

      MyApp.SentenceClassifier.classify(tokens)
      #=> {:demand, %{confidence: :grammar}}

      MyApp.SentenceClassifier.classify_text("Какой-то факт.")
      #=> {:fact, %{confidence: :classifier, score: 0.72}}

  ## Pluggable classifiers

  Any module implementing `Razmetka.Classifier` can serve as the fallback:

      defmodule MyApp.FridaClassifier do
        @behaviour Razmetka.Classifier

        @impl true
        def classify(text, _opts) do
          # ... FRIDA / fastText / whatever
          {:fact, 0.72}
        end
      end
  """

  defmacro __using__(_opts) do
    quote do
      import Razmetka, only: [defclassify: 1]
      Module.register_attribute(__MODULE__, :razmetka_classify, accumulate: false)
      @before_compile Razmetka
    end
  end

  @doc """
  Defines the classification pipeline.

  ## Options

  - `:priority` — list of `{type, when: condition}` tuples, checked in order.

    Conditions can be:
    - A matcher name (atom): `when: :demand` — calls `demand?(tokens)`
    - A list with boolean combinators: `when: all([:title_base, any([:pretrial, :short])])`
    - A function name (atom): `when: {:fn, :my_check}` — calls `my_check(tokens, text)`

  - `:classifier` — module implementing `Razmetka.Classifier` (optional)
  - `:default` — type when nothing matches and no classifier (default: `:unknown`)
  - `:threshold` — minimum classifier confidence (default: `0.40`)
  """
  defmacro defclassify(opts) do
    quote do
      @razmetka_classify unquote(opts)
    end
  end

  defmacro __before_compile__(env) do
    classify_opts = Module.get_attribute(env.module, :razmetka_classify)

    if classify_opts do
      priority = Keyword.fetch!(classify_opts, :priority)
      classifier_mod = Keyword.get(classify_opts, :classifier)
      default = Keyword.get(classify_opts, :default, :unknown)
      threshold = Keyword.get(classify_opts, :threshold, 0.40)

      branches =
        Enum.map(priority, fn {type, opts} ->
          condition = Keyword.fetch!(opts, :when)
          cond_ast = compile_condition_ast(condition)

          {:->, [],
           [
             [cond_ast],
             quote(do: {unquote(type), %{confidence: :grammar}})
           ]}
        end)

      fallback_branch =
        if classifier_mod do
          {:->, [],
           [
             [true],
             quote do
               case unquote(classifier_mod).classify(text, []) do
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
          {:->, [], [[true], quote(do: {unquote(default), %{confidence: :low}})]}
        end

      all_branches = branches ++ [fallback_branch]

      quote do
        @doc """
        Classifies morph-tagged tokens through the priority chain.
        Returns `{type, metadata}`.
        """
        def classify(tokens, text \\ "") when is_list(tokens) do
          cond do
            unquote(all_branches)
          end
        end

        @doc "Classifies raw text (tokenizes and morph-tags first)."
        def classify_text(text) when is_binary(text) do
          tokens = Yargy.Pipeline.morph_tokenize(text)
          classify(tokens, text)
        end
      end
    else
      quote do
      end
    end
  end

  defp compile_condition_ast(condition) do
    case condition do
      {:all, conditions} ->
        conditions
        |> Enum.map(&compile_condition_ast/1)
        |> Enum.reduce(fn right, left ->
          quote(do: unquote(left) and unquote(right))
        end)

      {:any, conditions} ->
        inner =
          conditions
          |> Enum.map(&compile_condition_ast/1)
          |> Enum.reduce(fn right, left ->
            quote(do: unquote(left) or unquote(right))
          end)

        quote(do: unquote(inner))

      {:not, condition} ->
        inner = compile_condition_ast(condition)
        quote(do: not unquote(inner))

      {:fn, func_name} when is_atom(func_name) ->
        quote(do: unquote(func_name)(tokens, text))

      name when is_atom(name) ->
        matcher_fn = :"#{name}?"
        quote(do: unquote(matcher_fn)(tokens))
    end
  end
end
