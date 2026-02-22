defmodule RazmetkaTest do
  use ExUnit.Case, async: true

  defmodule StubClassifier do
    @behaviour Razmetka.Classifier

    @impl true
    def classify(text, _opts) do
      cond do
        String.contains?(text, "факт") -> {:fact, 0.85}
        String.contains?(text, "квалификация") -> {:qualification, 0.60}
        true -> {:fact, 0.20}
      end
    end
  end

  defmodule LegalClassifier do
    use Yargy.Grammar
    use Razmetka

    defmatch(
      :demand,
      any_token(
        all([
          lemma(~w[требовать просить взыскать обязать вернуть]),
          gram("VERB")
        ])
      )
    )

    defmatch(:norm_framing, any_token(lemma(~w[соответствие согласно основание])))

    defmatch(
      :evidence,
      all_of([
        any_token(lemma(~w[подтверждаться подтвердить подтверждать])),
        any_token(lemma(~w[акт квитанция чек выписка]))
      ])
    )

    defmatch(
      :threat,
      all_of([
        any_token(lemma("вынудить")),
        any_token(caseless("суд"))
      ])
    )

    defclassify(
      priority: [
        {:demand, when: :demand},
        {:norm, when: :norm_framing},
        {:evidence, when: :evidence},
        {:threat, when: :threat}
      ],
      classifier: RazmetkaTest.StubClassifier,
      default: :fact,
      threshold: 0.40
    )
  end

  defmodule NoClassifierModule do
    use Yargy.Grammar
    use Razmetka

    defmatch(:greeting, any_token(lemma("привет")))

    defclassify(
      priority: [
        {:greeting, when: :greeting}
      ],
      default: :unknown
    )
  end

  describe "classify_text/1" do
    test "demand verb matches grammar" do
      {type, meta} = LegalClassifier.classify_text("Истец требует возмещения убытков")
      assert type == :demand
      assert meta.confidence == :grammar
    end

    test "norm framing matches grammar" do
      {type, meta} = LegalClassifier.classify_text("В соответствии с договором поставки")
      assert type == :norm
      assert meta.confidence == :grammar
    end

    test "evidence pattern matches grammar" do
      {type, meta} =
        LegalClassifier.classify_text("Оплата подтверждается актом выполненных работ")

      assert type == :evidence
      assert meta.confidence == :grammar
    end

    test "threat matches grammar" do
      {type, meta} = LegalClassifier.classify_text("Будем вынуждены обратиться в суд")
      assert type == :threat
      assert meta.confidence == :grammar
    end

    test "falls back to classifier above threshold" do
      {type, meta} = LegalClassifier.classify_text("Это просто факт из дела")
      assert type == :fact
      assert meta.confidence == :classifier
      assert meta.score >= 0.40
    end

    test "falls back to classifier with qualification" do
      {type, meta} = LegalClassifier.classify_text("Это квалификация действий ответчика")
      assert type == :qualification
      assert meta.confidence == :classifier
    end

    test "falls back to default when classifier below threshold" do
      {type, meta} = LegalClassifier.classify_text("Какой-то непонятный текст")
      assert type == :fact
      assert meta.confidence == :low
    end
  end

  describe "priority order" do
    test "first matching rule wins" do
      {type, _} = LegalClassifier.classify_text("Требуем в соответствии с законом")
      assert type == :demand
    end
  end

  describe "no classifier" do
    test "matches grammar" do
      {type, meta} = NoClassifierModule.classify_text("Привет мир")
      assert type == :greeting
      assert meta.confidence == :grammar
    end

    test "returns default when no match" do
      {type, meta} = NoClassifierModule.classify_text("Какой-то текст")
      assert type == :unknown
      assert meta.confidence == :low
    end
  end

  describe "classify/2 with pre-tokenized" do
    test "works with morph-tagged tokens" do
      tokens = Yargy.Pipeline.morph_tokenize("Истец требует возмещения")
      {type, _} = LegalClassifier.classify(tokens, "Истец требует возмещения")
      assert type == :demand
    end
  end
end
