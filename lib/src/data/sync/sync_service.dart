// 私有字段用不了 this._x 形式的具名参数（Dart 不允许私有具名参数），
// 和 card_completion.dart 一样关掉这条。
// ignore_for_file: prefer_initializing_formals

import '../../core/ids.dart';
import '../../domain/models/answer_record.dart';
import '../../domain/models/deck.dart';
import '../../domain/models/sync_snapshot.dart';
import '../../domain/models/word_card.dart';
import '../../domain/repositories.dart';
import '../../logic/sync_merge.dart';

/// 一次「把合并结果落库」都动了什么，界面直接显示这几个数。
class SyncApplyResult {
  const SyncApplyResult({
    this.addedCards = 0,
    this.updatedCards = 0,
    this.removedCards = 0,
    this.addedDecks = 0,
    this.updatedDecks = 0,
    this.addedAnswers = 0,
  });

  final int addedCards;
  final int updatedCards;
  final int removedCards;
  final int addedDecks;
  final int updatedDecks;
  final int addedAnswers;

  bool get isEmpty =>
      addedCards == 0 &&
      updatedCards == 0 &&
      removedCards == 0 &&
      addedDecks == 0 &&
      updatedDecks == 0 &&
      addedAnswers == 0;

  String get summary {
    if (isEmpty) return '两边本来就一样，没有要改的';
    final List<String> parts = <String>[
      if (addedCards > 0) '新增 $addedCards 张',
      if (updatedCards > 0) '更新 $updatedCards 张',
      if (removedCards > 0) '删除 $removedCards 张',
      if (addedAnswers > 0) '合并 $addedAnswers 条答题记录',
      if (addedDecks > 0) '新增 $addedDecks 个卡组',
      if (updatedDecks > 0) '更新 $updatedDecks 个卡组',
    ];
    return parts.join('，');
  }
}

/// 一次同步交换的结果。
class SyncExchangeResult {
  const SyncExchangeResult({
    required this.merged,
    required this.applied,
  });

  /// 合并之后的全量数据。对方拿它落库，两端就一样了。
  final SyncSnapshot merged;

  /// 这一端把合并结果写进本地库时动了什么。
  final SyncApplyResult applied;
}

/// 同步的核心：把本地数据打包、把对方的数据合进来、把结果写回本地。
///
/// 传输层（HTTP）与界面都不在这层：这里只认三个仓库和一个纯函数合并器，
/// 所以可以在单元测试里用两个内存库直接对跑。
class SyncService {
  SyncService({
    required CardRepository cards,
    required DeckRepository decks,
    required AnswerRecordRepository records,
    required SyncRepository sync,
    Clock clock = systemClock,
  })  : _cards = cards,
        _decks = decks,
        _records = records,
        _sync = sync,
        _clock = clock;

  final CardRepository _cards;
  final DeckRepository _decks;
  final AnswerRecordRepository _records;
  final SyncRepository _sync;
  final Clock _clock;

  /// 打包本地全部数据。[deviceName] 只是给对方看的名字。
  Future<SyncSnapshot> buildSnapshot({String deviceName = ''}) async {
    final String deviceId = await _sync.deviceId();
    final List<Deck> decks = await _decks.getAll();
    final List<WordCard> cards = await _cards.getAll();
    final List<AnswerRecord> answers = await _records.getAll();
    final List<SyncTombstone> tombstones = await _sync.tombstones();
    return SyncSnapshot(
      deviceId: deviceId,
      deviceName: deviceName,
      generatedAt: _clock(),
      decks: decks,
      cards: cards,
      answers: answers,
      tombstones: tombstones,
    );
  }

  /// 收到对方的包：和本地合一份，写回本地，再把合并结果交回去。
  ///
  /// 写回本地是为了让这一端立刻看到对方的词；把合并结果交回去，
  /// 是为了让对方也看到这一端的词 —— 一次往返，两端就一样了。
  Future<SyncExchangeResult> acceptRemote(
    SyncSnapshot remote, {
    String deviceName = '',
  }) async {
    final SyncSnapshot mine = await buildSnapshot(deviceName: deviceName);
    final SyncSnapshot merged = mergeSnapshots(mine, remote);
    final SyncApplyResult applied = await applyMerged(merged);
    return SyncExchangeResult(merged: merged, applied: applied);
  }

  /// 把一份「已经合并好」的全量数据写成本地状态。
  ///
  /// 顺序是有讲究的：先落删除，再写卡组，最后写卡片。
  /// 删除会把卡从卡组里挪出来，反过来做就会把已经删掉的卡又写回去。
  Future<SyncApplyResult> applyMerged(SyncSnapshot merged) async {
    int addedCards = 0;
    int updatedCards = 0;
    int removedCards = 0;
    int addedDecks = 0;
    int updatedDecks = 0;
    int addedAnswers = 0;

    final Map<String, WordCard> before = <String, WordCard>{
      for (final WordCard card in await _cards.getAll()) card.id: card,
    };
    final Map<String, Deck> decksBefore = <String, Deck>{
      for (final Deck deck in await _decks.getAll()) deck.id: deck,
    };
    final Set<String> knownAnswers = <String>{
      for (final AnswerRecord record in await _records.getAll()) record.id,
    };

    for (final SyncTombstone stone in merged.tombstones) {
      await _sync.applyTombstone(stone);
      if (!stone.isDeck && before.containsKey(stone.uid)) removedCards++;
    }

    for (final Deck deck in merged.decks) {
      final Deck? existing = decksBefore[deck.id];
      if (existing == null) {
        await _decks.upsert(deck);
        addedDecks++;
      } else if (existing.name != deck.name ||
          existing.suspended != deck.suspended) {
        await _decks.upsert(deck);
        updatedDecks++;
      }
    }

    final List<WordCard> toWrite = <WordCard>[];
    for (final WordCard card in merged.cards) {
      final WordCard? existing = before[card.id];
      if (existing == null) {
        toWrite.add(card);
        addedCards++;
      } else if (!_sameCard(existing, card)) {
        toWrite.add(card);
        updatedCards++;
      }
    }
    // 一次事务写一批：外部写入可能一次来几十张，逐张 upsert 会明显卡界面。
    await _cards.upsertAll(toWrite);

    final List<AnswerRecord> newAnswers = <AnswerRecord>[
      for (final AnswerRecord record in merged.answers)
        if (!knownAnswers.contains(record.id)) record,
    ];
    if (newAnswers.isNotEmpty) {
      await _records.addAll(newAnswers);
      addedAnswers = newAnswers.length;
    }

    return SyncApplyResult(
      addedCards: addedCards,
      updatedCards: updatedCards,
      removedCards: removedCards,
      addedDecks: addedDecks,
      updatedDecks: updatedDecks,
      addedAnswers: addedAnswers,
    );
  }

  /// 内容的逐字段比较。答题进度也算在内：只错一个字不算「变了」，
  /// 但复习次数变了必须写回去，否则同步完概览数字还是旧的。
  static bool _sameCard(WordCard a, WordCard b) {
    if (a.updatedAt != b.updatedAt) return false;
    if (a.word != b.word || a.definition != b.definition) return false;
    if (a.phonetic != b.phonetic || a.example != b.example) return false;
    if (a.partOfSpeech != b.partOfSpeech || a.note != b.note) return false;
    if (a.deckId != b.deckId) return false;
    if (a.language != b.language || a.source != b.source) return false;
    if (a.tags.join('|') != b.tags.join('|')) return false;
    if (a.distractors.join('|') != b.distractors.join('|')) return false;
    if (a.reviewCount != b.reviewCount) return false;
    if (a.correctCount != b.correctCount) return false;
    if (a.wrongCount != b.wrongCount) return false;
    if (a.totalReactionMs != b.totalReactionMs) return false;
    if (a.mastery != b.mastery) return false;
    if (a.lastReviewedAt != b.lastReviewedAt) return false;
    if (a.nextReviewAt != b.nextReviewAt) return false;
    if (a.intervalDays != b.intervalDays) return false;
    if (a.easeFactor != b.easeFactor) return false;
    if (a.fsrs?.stability != b.fsrs?.stability) return false;
    if (a.fsrs?.difficulty != b.fsrs?.difficulty) return false;
    if (a.fsrs?.reps != b.fsrs?.reps) return false;
    if (a.fsrs?.dueAt != b.fsrs?.dueAt) return false;
    return true;
  }
}
