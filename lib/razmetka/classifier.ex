defmodule Razmetka.Classifier do
  @moduledoc """
  Behaviour for pluggable sentence classifiers.

  Implement this to provide ML-based fallback when grammar rules don't match.

  ## Example

      defmodule MyApp.FridaClassifier do
        @behaviour Razmetka.Classifier

        @impl true
        def classify(text, _opts) do
          clf = MyApp.ClassifierServer.get()
          {type, score} = MyApp.NLP.Classifier.classify_one(clf, text)
          {type, score}
        end
      end
  """

  @doc """
  Classifies a text string, returning `{type, confidence_score}` or `nil`.

  The score should be a float between 0.0 and 1.0. Razmetka compares it
  against the configured `:threshold` to decide whether to accept the
  prediction or fall back to `:default`.
  """
  @callback classify(text :: String.t(), opts :: keyword()) ::
              {atom(), float()} | nil
end
