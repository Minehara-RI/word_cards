import '../domain/models/answer_record.dart';
import '../domain/models/deck.dart';
import '../domain/models/fsrs_memory.dart';
import '../domain/models/sync_snapshot.dart';
import '../domain/models/word_card.dart';

/// 两台设备的数据怎么合成一份。
///
/// 这份代码必须是**可交换、可重复、可结合**的（纯函数，不碰数据库）：
/// 同一批设备不管以什么顺序、同步几次，最后都要收敛到同一份数据。
/// 所以每处「谁赢」都写成了带稳定次序的比较，而不是「后来的覆盖先来的」。
///
/// 内容与进度分开合，是因为它们的时间尺度不同：
/// - 内容（单词、释义、干扰项…）改了会更新 updatedAt，取更晚的那次编辑；
/// - 进度（复习次数、掌握度、FSRS）每次作答都在变，但刻意不碰 updatedAt
///   （否则改一次答案就算「内容变了」），所以按「最后复习时间」取。
SyncSnapshot mergeSnapshots(SyncSnapshot local, SyncSnapshot remote) {
  final List<SyncTombstone> tombstones = _mergeTombstones(local, remote);
  final Map<String, DateTime> cardDeletions = <String, DateTime>{
    for (final SyncTombstone stone in tombstones)
      if (!stone.isDeck) stone.uid: stone.deletedAt,
  };
  final Map<String, DateTime> deckDeletions = <String, DateTime>{
    for (final SyncTombstone stone in tombstones)
      if (stone.isDeck) stone.uid: stone.deletedAt,
  };

  // ---- 卡组 ----
  final Map<String, Deck> decks = <String, Deck>{};
  for (final Deck deck in <Deck>[...local.decks, ...remote.decks]) {
    final Deck? existing = decks[deck.id];
    if (existing == null || _compareDecks(deck, existing) > 0) {
      decks[deck.id] = deck;
    }
  }
  decks.removeWhere((String id, Deck deck) {
    final DateTime? deletedAt = deckDeletions[id];
    // 「后删的就删了，后改的就留着」：删除时间不早于最后修改时间才算数。
    return deletedAt != null && !deletedAt.isBefore(deck.createdAt);
  });
  // 默认卡组是兜底，任何时候都不能没有它。
  decks.putIfAbsent(
    Deck.defaultDeckId,
    () => Deck(
      id: Deck.defaultDeckId,
      name: Deck.defaultDeckName,
      createdAt: DateTime.fromMillisecondsSinceEpoch(0),
    ),
  );

  // ---- 卡片 ----
  final Map<String, WordCard> cards = <String, WordCard>{};
  for (final WordCard card in <WordCard>[...local.cards, ...remote.cards]) {
    final DateTime? deletedAt = cardDeletions[card.id];
    if (deletedAt != null && !deletedAt.isBefore(card.updatedAt)) {
      continue; // 删得比改得晚：这张卡确实被删了
    }
    final WordCard? existing = cards[card.id];
    cards[card.id] = existing == null ? card : _mergeCard(existing, card);
  }

  // 卡组被删了，里面的卡不会跟着消失（和界面上「删除卡组」一致），
  // 统一退回默认卡组。两边算出来是同一个结果，不会来回搬。
  final List<WordCard> mergedCards = <WordCard>[
    for (final WordCard card in cards.values)
      decks.containsKey(card.deckId)
          ? card
          : card.copyWith(deckId: Deck.defaultDeckId),
  ]..sort((WordCard a, WordCard b) => a.id.compareTo(b.id));

  // ---- 答题记录 ----
  final Map<String, AnswerRecord> answers = <String, AnswerRecord>{};
  for (final AnswerRecord record in <AnswerRecord>[
    ...local.answers,
    ...remote.answers,
  ]) {
    answers.putIfAbsent(record.id, () => record);
  }

  return SyncSnapshot(
    deviceId: local.deviceId,
    deviceName: local.deviceName,
    generatedAt: local.generatedAt.isAfter(remote.generatedAt)
        ? local.generatedAt
        : remote.generatedAt,
    decks: decks.values.toList(growable: false)
      ..sort((Deck a, Deck b) => a.id.compareTo(b.id)),
    cards: mergedCards,
    answers: answers.values.toList(growable: false)
      ..sort((AnswerRecord a, AnswerRecord b) => a.id.compareTo(b.id)),
    tombstones: tombstones,
  );
}

/// 两张同一 uid 的卡合成一张：内容取更晚的编辑，进度取更晚的复习。
WordCard _mergeCard(WordCard a, WordCard b) {
  final WordCard content = _compareContent(a, b) >= 0 ? a : b;
  final WordCard progress = _compareProgress(a, b) >= 0 ? a : b;
  final FsrsMemory? fsrs =
      _compareProgress(a, b) >= 0 ? a.fsrs : b.fsrs;

  // 用构造函数而不是 copyWith：进度里的「清空」语义（nextReviewAt 置空）
  // copyWith 表达不出来，直接拼一个新的最省事。
  return WordCard(
    id: content.id,
    word: content.word,
    definition: content.definition,
    distractors: content.distractors,
    phonetic: content.phonetic,
    example: content.example,
    partOfSpeech: content.partOfSpeech,
    note: content.note,
    deckId: content.deckId,
    language: content.language,
    tags: content.tags,
    fsrs: fsrs,
    source: content.source,
    createdAt: content.createdAt,
    updatedAt: content.updatedAt,
    reviewCount: progress.reviewCount,
    correctCount: progress.correctCount,
    wrongCount: progress.wrongCount,
    totalReactionMs: progress.totalReactionMs,
    mastery: progress.mastery,
    lastReviewedAt: progress.lastReviewedAt,
    nextReviewAt: progress.nextReviewAt,
    intervalDays: progress.intervalDays,
    easeFactor: progress.easeFactor,
  );
}

/// 内容的先后：先比 updatedAt，相同再按内容本身排序。
///
/// 第二级比较不是为了「更正确」，而是为了**确定性**：
/// 两台设备在同一秒改了同一个词时，必须挑出同一份，否则永远收敛不了。
int _compareContent(WordCard a, WordCard b) {
  final int byTime = a.updatedAt.compareTo(b.updatedAt);
  if (byTime != 0) return byTime;
  return _contentSignature(a).compareTo(_contentSignature(b));
}

String _contentSignature(WordCard card) => <String>[
      card.word,
      card.definition,
      card.phonetic ?? '',
      card.example ?? '',
      card.partOfSpeech ?? '',
      card.note ?? '',
      card.distractors.join('|'),
      card.deckId,
      card.language.id,
      card.tags.join('|'),
      card.source.id,
      card.createdAt.millisecondsSinceEpoch.toString(),
    ].join('\u0001');

/// 进度的先后：谁最后复习过谁说了算；同一时刻再按累计次数排，
/// 保证「两台设备都答过同一张卡」时也能算出同一个结果。
int _compareProgress(WordCard a, WordCard b) {
  final int byReview =
      (a.lastReviewedAt?.millisecondsSinceEpoch ?? 0)
          .compareTo(b.lastReviewedAt?.millisecondsSinceEpoch ?? 0);
  if (byReview != 0) return byReview;
  final int byCount = a.reviewCount.compareTo(b.reviewCount);
  if (byCount != 0) return byCount;
  final int byCorrect = a.correctCount.compareTo(b.correctCount);
  if (byCorrect != 0) return byCorrect;
  final int byReaction = a.totalReactionMs.compareTo(b.totalReactionMs);
  if (byReaction != 0) return byReaction;
  return a.mastery.compareTo(b.mastery);
}

int _compareDecks(Deck a, Deck b) {
  final int byTime = a.createdAt.compareTo(b.createdAt);
  if (byTime != 0) return byTime;
  final int byName = a.name.compareTo(b.name);
  if (byName != 0) return byName;
  return (a.suspended ? 1 : 0).compareTo(b.suspended ? 1 : 0);
}

List<SyncTombstone> _mergeTombstones(SyncSnapshot local, SyncSnapshot remote) {
  final Map<String, SyncTombstone> merged = <String, SyncTombstone>{};
  for (final SyncTombstone stone in <SyncTombstone>[
    ...local.tombstones,
    ...remote.tombstones,
  ]) {
    final String key = '${stone.kind}\u0001${stone.uid}';
    final SyncTombstone? existing = merged[key];
    if (existing == null || stone.deletedAt.isAfter(existing.deletedAt)) {
      merged[key] = stone;
    }
  }
  final List<SyncTombstone> result = merged.values.toList(growable: false)
    ..sort((SyncTombstone a, SyncTombstone b) {
      final int byKind = a.kind.compareTo(b.kind);
      return byKind != 0 ? byKind : a.uid.compareTo(b.uid);
    });
  return result;
}
