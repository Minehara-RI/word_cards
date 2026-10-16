// ignore_for_file: prefer_interpolation_to_compose_strings

import 'dart:math';

import 'card_language.dart';

/// 出题方向：题面给什么、选项选什么。
///
/// 前两个值是真正出题用的方向；[mixed] 只在设置里存在 ——
/// 出每一道题之前先过一遍 [pick]，题目拿到的一定是具体方向。
enum QuizDirection {
  wordToMeaning('word_to_meaning'),
  meaningToWord('meaning_to_word'),
  mixed('mixed');

  const QuizDirection(this.id);

  /// 持久化用的稳定标识，只能加不能改。
  final String id;

  /// 「混合」：每道题随机取前两种之一。
  bool get isMixed => this == QuizDirection.mixed;

  /// 这一题是**反方向**：题面给中文释义、选项给单词。
  ///
  /// 反方向下音标必须藏起来（音标就是答案的读音，写在题面上等于给答案），
  /// 「正确X」里的 X 也变成「单词」。
  bool get isReverse => this == QuizDirection.meaningToWord;

  /// 把设置里的方向掷成一道题的具体方向。
  QuizDirection pick(Random rng) => isMixed
      ? (rng.nextBool()
          ? QuizDirection.wordToMeaning
          : QuizDirection.meaningToWord)
      : this;

  /// 「正确X」里的 X：反方向选的是单词，正方向选的是释义。
  String get answerNoun => isReverse ? '单词' : '释义';

  /// 题面上那行短标签。混合模式下每道题都要标出来，
  /// 否则用户看不出这一题到底该选中文还是选英文。
  String get shortLabel => switch (this) {
        QuizDirection.wordToMeaning => '词 → 义',
        QuizDirection.meaningToWord => '义 → 词',
        QuizDirection.mixed => '混合',
      };

  /// 不带语言的说明：答案 txt 这种不点名语言的地方用。
  String get description => switch (this) {
        QuizDirection.wordToMeaning => '题面给单词，选项是中文释义',
        QuizDirection.meaningToWord => '题面给中文释义，选项是单词',
        QuizDirection.mixed => '每道题随机用上面两种方向，题面上会标出这一题考哪边',
      };

  /// 界面上的名字。按卡片语言来写：英语卡就是「看英文选中文」。
  String labelFor(CardLanguage language) => switch (this) {
        QuizDirection.wordToMeaning => '看' + language.exampleLanguage + '选中文',
        QuizDirection.meaningToWord => '看中文选' + language.exampleLanguage,
        QuizDirection.mixed => '混合',
      };

  /// 作答页上的说明：按当前语言写全。
  String describe(CardLanguage language) => switch (this) {
        QuizDirection.wordToMeaning =>
          '题面给' + language.exampleLanguage + '单词，选项是中文释义。',
        QuizDirection.meaningToWord =>
          '题面给中文释义，选项是' + language.exampleLanguage + '单词。',
        QuizDirection.mixed =>
          '每道题随机用上面两种方向，同一轮里两种都会出现；题面上会标出这一题考哪边。',
      };

  static QuizDirection fromId(Object? value) {
    if (value is String) {
      for (final direction in QuizDirection.values) {
        if (direction.id == value || direction.name == value) return direction;
      }
    }
    return QuizDirection.wordToMeaning;
  }
}
