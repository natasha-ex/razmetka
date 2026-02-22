# Razmetka

Priority-dispatch sentence classifier with pluggable ML fallback for Russian NLP.

Part of the [natasha-ex](https://github.com/natasha-ex) ecosystem. Extends [yargy](https://github.com/natasha-ex/yargy)'s `defmatch` bag-of-features matchers with ordered dispatch and ML classifier fallback.

- Grammar-first: bag-of-features rules checked in priority order
- ML fallback: pluggable classifier (`Razmetka.Classifier` behaviour) for unmatched sentences
- Zero coupling: works with FRIDA, fastText, or any embedding model
- Reuses yargy's terminal predicates (`lemma`, `gram`, `token`, etc.)

## Installation

```elixir
def deps do
  [
    {:razmetka, "~> 0.1"}
  ]
end
```

## Usage

```elixir
defmodule MyApp.SentenceClassifier do
  use Yargy.Grammar
  use Razmetka

  # Bag-of-features matchers (from yargy)
  defmatch :demand, any_token(all([
    lemma(~w[требовать просить взыскать]),
    gram("VERB")
  ]))

  defmatch :norm_framing, any_token(lemma(~w[соответствие согласно основание]))

  defmatch :evidence, all_of([
    any_token(lemma(~w[подтверждаться подтвердить])),
    any_token(lemma(~w[акт квитанция чек выписка]))
  ])

  # Priority dispatch + ML fallback
  defclassify priority: [
    {:demand,   when: :demand},
    {:norm,     when: :norm_framing},
    {:evidence, when: :evidence},
  ],
  classifier: MyApp.FridaClassifier,
  default: :fact,
  threshold: 0.40
end
```

### Classify text

```elixir
MyApp.SentenceClassifier.classify_text("Истец требует возмещения убытков")
#=> {:demand, %{confidence: :grammar}}

MyApp.SentenceClassifier.classify_text("Товар был поставлен 20 октября")
#=> {:fact, %{confidence: :classifier, score: 0.72}}
```

### Pre-tokenized input

```elixir
tokens = Yargy.Pipeline.morph_tokenize("Истец требует возмещения")
MyApp.SentenceClassifier.classify(tokens, "Истец требует возмещения")
#=> {:demand, %{confidence: :grammar}}
```

## Pluggable classifiers

Implement the `Razmetka.Classifier` behaviour:

```elixir
defmodule MyApp.FridaClassifier do
  @behaviour Razmetka.Classifier

  @impl true
  def classify(text, _opts) do
    clf = MyApp.ClassifierServer.get()
    {type, score} = MyApp.NLP.Classifier.classify_one(clf, text)
    {type, score}
  end
end
```

The callback returns `{type, score}` where score is 0.0–1.0. Razmetka
compares against `:threshold` — below it, the `:default` type is used.

## How it works

```
classify_text("В соответствии со ст. 309 ГК РФ...")
│
├─ tokenize + morph-tag (once, via yargy)
│
├─ Try :demand      → no conjugated demand verb → skip
├─ Try :norm        → has "соответствие" ✓ → MATCH
│   → {:norm, %{confidence: :grammar}}
│
└─ (never reaches :evidence or classifier)
```

```
classify_text("Товар был поставлен 20 октября.")
│
├─ tokenize + morph-tag
│
├─ Try :demand   → skip
├─ Try :norm     → skip
├─ Try :evidence → skip
├─ Classifier fallback → FRIDA → {:fact, 0.72}
│   → {:fact, %{confidence: :classifier, score: 0.72}}
```

## Without classifier

```elixir
defmodule MyApp.SimpleClassifier do
  use Yargy.Grammar
  use Razmetka

  defmatch :greeting, any_token(lemma("привет"))

  defclassify priority: [
    {:greeting, when: :greeting},
  ],
  default: :unknown
end

MyApp.SimpleClassifier.classify_text("Привет мир")
#=> {:greeting, %{confidence: :grammar}}

MyApp.SimpleClassifier.classify_text("Какой-то текст")
#=> {:unknown, %{confidence: :low}}
```

## License

MIT © Danila Poyarkov
