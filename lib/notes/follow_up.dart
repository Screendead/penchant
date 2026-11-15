import 'package:tracker/data/limits.dart';

// The follow-up question Claude asked about a note, and the person's answer.
// Sealed only (inside an entry's or a day note's envelope), stored only when
// an answer was typed, and absent on everything written before it existed.

const String followUpQuestionField = 'followUpQuestion';
const String followUpQuoteField = 'followUpQuote';
const String followUpAnswerField = 'followUpAnswer';

const List<String> followUpFields = <String>[
  followUpQuestionField,
  followUpQuoteField,
  followUpAnswerField,
];

/// A question the note reader asked about a note: [question] as the model
/// wrote it, without the lead the app puts before it, and [quote], the words
/// of the note it picks up, copied exactly.
typedef NoteQuestion = ({String question, String quote});

/// What the panels show above the question: the quoted words, then it.
String askedLine(String question, String? quote) =>
    quote == null ? question : 'You wrote “$quote”. $question';

class FollowUp {
  const FollowUp({required this.question, this.quote, required this.answer});

  final String question;

  /// The words of the note the question picked up; absent if mistyped.
  final String? quote;
  final String answer;

  /// The stored pair, or null: a question without an answer, or an answer
  /// without a question, reads as none. Never throws.
  static FollowUp? read(Map<String, Object?> content) {
    final Object? question = content[followUpQuestionField];
    final Object? answer = content[followUpAnswerField];
    final Object? quote = content[followUpQuoteField];
    if (question is! String || question.trim().isEmpty) return null;
    if (answer is! String || answer.trim().isEmpty) return null;
    return FollowUp(
      question: question,
      quote: quote is String && quote.isNotEmpty ? quote : null,
      answer: answer,
    );
  }

  /// Saved only with an answer: [answer] blank gives null.
  static FollowUp? answered(NoteQuestion? asked, String answer) {
    final String trimmed = answer.trim();
    if (asked == null || trimmed.isEmpty) return null;
    return FollowUp(
      question: asked.question,
      quote: asked.quote,
      answer: trimmed,
    );
  }

  Map<String, Object?> toMap() => <String, Object?>{
    followUpQuestionField: question,
    followUpQuoteField: ?quote,
    followUpAnswerField: answer,
  };

  /// Why this cannot be saved, or null. Sealed, so this is its only guard.
  String? get error =>
      question.length > maxFollowUpQuestionLength ||
          (quote?.length ?? 0) > maxFollowUpQuoteLength
      ? 'The question is too long to save.'
      : followUpAnswerError(answer);

  @override
  bool operator ==(Object other) =>
      other is FollowUp &&
      other.question == question &&
      other.quote == quote &&
      other.answer == answer;

  @override
  int get hashCode => Object.hash(question, quote, answer);
}
