// 私有字段用不了 this._x 形式的具名参数（Dart 不允许私有具名参数）。
// ignore_for_file: prefer_initializing_formals

import '../../domain/models/app_settings.dart';
import '../../domain/models/word_card.dart';
import 'api_client.dart';
import 'card_completion.dart';

/// 一次「给已有卡片补全」的结果。
class CardFillOutcome {
  const CardFillOutcome({
    required this.card,
    this.filled = const <String>[],
    this.failure,
    this.promptTokens = 0,
    this.completionTokens = 0,
    this.fromCache = false,
  });

  /// 补完之后（或原样返回）的卡片。只有 [changed] 为真时才需要落库。
  final WordCard card;

  /// 补上了哪几项，例如 ['音标', '例句']。
  final List<String> filled;

  final AiApiFailure? failure;
  final int promptTokens;
  final int completionTokens;
  final bool fromCache;

  bool get changed => filled.isNotEmpty;
  bool get ok => failure == null;

  /// 给界面用的一句话；失败时带上「下一步」。
  String get message {
    if (failure != null) {
      final String message = failure!.message;
      return failure!.hint == null ? message : '$message：${failure!.hint}';
    }
    if (!changed) return '这张卡没有要补的项';
    return '已补全：${filled.join('、')}';
  }
}

/// 这张卡还缺东西吗（音标 / 词性 / 例句 / 备注 / 干扰项任意一项）。
///
/// 只用来判断「要不要显示补全入口」，不参与补全本身 —— 补全只填空格，
/// 已经填过的字段一个字节都不动。
bool needsAiFill(WordCard card) =>
    (card.phonetic ?? '').trim().isEmpty ||
    (card.partOfSpeech ?? '').trim().isEmpty ||
    (card.example ?? '').trim().isEmpty ||
    (card.note ?? '').trim().isEmpty ||
    card.distractors.length < WordCard.targetDistractorCount;

/// 缺音标（批量补全里最常用的那一档）。
bool missingPhonetic(WordCard card) => (card.phonetic ?? '').trim().isEmpty;

/// 干扰项不够五个选项用。
bool missingDistractors(WordCard card) =>
    card.distractors.length < WordCard.targetDistractorCount;

/// 用 AI 给一张**已经存在**的卡片补全非必填项。
///
/// 和「加入」页那个补全是同一套服务、同一份 Prompt；区别只是结果直接落成
/// [WordCard]，而不是填进输入框。规则也一样：**只补空着的字段**，
/// 用户写过的音标、例句不会被模型改掉。
Future<CardFillOutcome> fillCardWithAi({
  required CardCompletionService service,
  required AppSettings settings,
  required WordCard card,
  DateTime? now,
}) async {
  final CardCompletionOutcome outcome = await service.complete(
    word: card.word,
    definition: card.definition,
    language: card.language,
    settings: settings,
    existingPhonetic: _blankToNull(card.phonetic),
    existingPartOfSpeech: _blankToNull(card.partOfSpeech),
    existingExample: _blankToNull(card.example),
    existingNote: _blankToNull(card.note),
    existingDistractors: card.distractors,
  );

  final CardCompletion? completion = outcome.completion;
  if (completion == null) {
    return CardFillOutcome(
      card: card,
      failure: outcome.failure,
      promptTokens: outcome.promptTokens,
      completionTokens: outcome.completionTokens,
      fromCache: outcome.fromCache,
    );
  }

  WordCard next = card;
  final List<String> filled = <String>[];
  if (completion.phonetic != null && (next.phonetic ?? '').trim().isEmpty) {
    next = next.copyWith(phonetic: completion.phonetic);
    filled.add('音标');
  }
  if (completion.partOfSpeech != null &&
      (next.partOfSpeech ?? '').trim().isEmpty) {
    next = next.copyWith(partOfSpeech: completion.partOfSpeech);
    filled.add('词性');
  }
  if (completion.example != null && (next.example ?? '').trim().isEmpty) {
    next = next.copyWith(example: completion.example);
    filled.add('例句');
  }
  if (completion.note != null && (next.note ?? '').trim().isEmpty) {
    next = next.copyWith(note: completion.note);
    filled.add('备注');
  }

  // 顺手清掉「干扰项 == 正确释义」这种废项：它在五选一里会被去重掉，
  // 等于白占一个位置，让题目真的只剩四个选项。
  final List<String> base = next.distractors
      .where((String item) => item.trim() != next.definition.trim())
      .toList();
  if (base.length != next.distractors.length) {
    next = next.copyWith(distractors: base);
    if (!filled.contains('干扰项')) filled.add('干扰项');
  }

  if (completion.distractors.isNotEmpty &&
      next.distractors.length < WordCard.targetDistractorCount) {
    final List<String> merged = <String>[...next.distractors];
    for (final String item in completion.distractors) {
      if (merged.length >= WordCard.targetDistractorCount) break;
      final String candidate = item.trim();
      if (candidate.isEmpty) continue;
      if (candidate == next.definition.trim()) continue;
      if (merged.any(
        (String have) => have.toLowerCase() == candidate.toLowerCase(),
      )) {
        continue;
      }
      merged.add(candidate);
    }
    if (merged.length != next.distractors.length) {
      next = next.copyWith(distractors: merged);
      if (!filled.contains('干扰项')) filled.add('干扰项');
    }
  }

  if (filled.isEmpty) {
    return CardFillOutcome(
      card: card,
      promptTokens: outcome.promptTokens,
      completionTokens: outcome.completionTokens,
      fromCache: outcome.fromCache,
    );
  }

  // 干扰项够了就把「待补全」摘掉；这是外部写入留下的记号。
  final List<String> tags = <String>[...next.tags];
  if (next.distractors.length >= WordCard.targetDistractorCount) {
    tags.remove(WordCard.incompleteTag);
  }
  next = next.copyWith(tags: tags);

  // 改了内容就推进 updatedAt：同步时「谁最后改的谁说了算」，
  // 不推进的话补全的结果会被对面更早的版本盖回去。
  next = next.copyWith(updatedAt: now ?? DateTime.now());

  return CardFillOutcome(
    card: next,
    filled: filled,
    promptTokens: outcome.promptTokens,
    completionTokens: outcome.completionTokens,
    fromCache: outcome.fromCache,
  );
}

String? _blankToNull(String? value) {
  final String text = (value ?? '').trim();
  return text.isEmpty ? null : text;
}
