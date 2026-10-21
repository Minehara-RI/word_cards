/// Anki 原生数据库（collection.anki2 / schema 11）的结构定义。
///
/// 这里写死的都是 Anki 官方的约定值，改动前先确认 Anki 那边能接受：
/// - 表结构来自 Anki 2.1 的 schema 11（也就是 .apkg 里 collection.anki2 的样子）
/// - 字段名、模板、牌组配置都用 Anki 自己的格式，Anki 打开后能直接看到卡片
library;

/// Anki 集合文件名。用这个名字，Anki 才能直接打开这个文件。
const String kAnkiFileName = 'collection.anki2';

/// Anki schema 版本。11 = 用 JSON 文本存 model/deck 配置的那一套。
const int kAnkiSchemaVersion = 11;

/// Anki 内置的默认牌组 id，固定是 1。
const int kDefaultAnkiDeckId = 1;

/// 笔记类型 id。用毫秒时间戳当固定值，避免和别的集合撞车。
const int kAnkiNotetypeId = 1700000000001;

/// 笔记类型（卡片模板）名字。
const String kAnkiNotetypeName = '单词卡';

/// 模板名字。
const String kAnkiTemplateName = '单词 - 释义';

/// 笔记的字段顺序。Anki 的 flds 是按这个顺序用 \x1f 拼起来的。
const List<String> kNoteFields = <String>[
  '单词',
  '释义',
  '音标',
  '例句',
  '词性',
  '备注',
  '干扰项',
];

const int kFieldWord = 0;
const int kFieldDefinition = 1;
const int kFieldPhonetic = 2;
const int kFieldExample = 3;
const int kFieldPartOfSpeech = 4;
const int kFieldNote = 5;
const int kFieldDistractors = 6;

/// Anki 用 \x1f 作为字段分隔符。
const String kFieldSeparator = '\u001f';

/// 干扰项在字段里用换行分隔，这样在 Anki 里显示的是一列，而不是一坨 JSON。
const String kDistractorSeparator = '\n';

/// Anki schema 11 的建表语句。
const List<String> kAnkiSchema = <String>[
  'create table if not exists col ('
      'id integer primary key, '
      'crt integer not null, '
      'mod integer not null, '
      'scm integer not null, '
      'ver integer not null, '
      'dty integer not null, '
      'usn integer not null, '
      'ls integer not null, '
      'conf text not null, '
      'models text not null, '
      'decks text not null, '
      'dconf text not null, '
      'tags text not null)',
  'create table if not exists notes ('
      'id integer primary key, '
      'guid text not null, '
      'mid integer not null, '
      'mod integer not null, '
      'usn integer not null, '
      'tags text not null, '
      'flds text not null, '
      'sfld integer not null, '
      'csum integer not null, '
      'flags integer not null, '
      'data text not null)',
  'create table if not exists cards ('
      'id integer primary key, '
      'nid integer not null, '
      'did integer not null, '
      'ord integer not null, '
      'mod integer not null, '
      'usn integer not null, '
      'type integer not null, '
      'queue integer not null, '
      'due integer not null, '
      'ivl integer not null, '
      'factor integer not null, '
      'reps integer not null, '
      'lapses integer not null, '
      'left integer not null, '
      'odue integer not null, '
      'odid integer not null, '
      'flags integer not null, '
      'data text not null)',
  'create table if not exists revlog ('
      'id integer primary key, '
      'cid integer not null, '
      'usn integer not null, '
      'ease integer not null, '
      'ivl integer not null, '
      'lastIvl integer not null, '
      'factor integer not null, '
      'time integer not null, '
      'type integer not null)',
  'create table if not exists graves ('
      'usn integer not null, '
      'oid integer not null, '
      'type integer not null)',
  'create index if not exists ix_notes_usn on notes (usn)',
  'create index if not exists ix_cards_usn on cards (usn)',
  'create index if not exists ix_revlog_usn on revlog (usn)',
  'create index if not exists ix_cards_nid on cards (nid)',
  'create index if not exists ix_cards_sched on cards (did, queue, due)',
  'create index if not exists ix_revlog_cid on revlog (cid)',
  'create index if not exists ix_notes_csum on notes (csum)',
];

/// 本应用自己的扩展表。Anki 会忽略不认识的表，所以可以和安全地放在同一个文件里。
///
/// - wc_card_ids：把应用内的字符串 id 映射到 Anki 的整数 id
/// - wc_card_stats：Anki 表里放不下的学习数据（答对/答错次数、反应时间等）
/// - wc_card_fsrs：FSRS 的记忆状态。单独一张表，开不开 FSRS 都不影响上面那张
/// - wc_settings：应用自己的配置（API Key、主题、限时等）
/// - wc_api_cache：模式 B 的生成缓存（同一个 Prompt 在缓存期内只请求一次）
const List<String> kAppSchema = <String>[
  'create table if not exists wc_card_ids ('
      'uid text primary key, '
      'note_id integer not null unique, '
      'card_id integer not null unique)',
  'create table if not exists wc_deck_ids ('
      'uid text primary key, '
      'deck_id integer not null unique)',
  'create table if not exists wc_card_stats ('
      'uid text primary key, '
      'review_count integer not null default 0, '
      'correct_count integer not null default 0, '
      'wrong_count integer not null default 0, '
      'total_reaction_ms integer not null default 0, '
      'mastery real not null default 0, '
      'last_reviewed_at integer, '
      'next_review_at integer, '
      'interval_days integer not null default 0, '
      'ease_factor real not null default 2.5, '
      'created_at integer, '
      'updated_at integer)',
  'create table if not exists wc_card_fsrs ('
      'uid text primary key, '
      'stability real not null default 0, '
      'difficulty real not null default 0, '
      'reps integer not null default 0, '
      'lapses integer not null default 0, '
      'state text not null default "new", '
      'last_review_at integer, '
      'due_at integer)',
  'create table if not exists wc_answer_log ('
      'id text primary key, '
      'card_uid text not null, '
      'selected text not null, '
      'expected text not null, '
      'correct integer not null, '
      'reaction_ms integer not null, '
      'answered_at integer not null, '
      'session_id text, '
      'deck_uid text, '
      'mode text not null, '
      'timed_out integer not null, '
      'revlog_id integer)',
  'create index if not exists ix_wc_answer_at on wc_answer_log (answered_at)',
  'create index if not exists ix_wc_answer_card on wc_answer_log (card_uid)',
  'create table if not exists wc_settings ('
      'key text primary key, '
      'value text not null)',
  'create table if not exists wc_api_cache ('
      'key text primary key, '
      'response text not null, '
      'model text not null default "", '
      'prompt_tokens integer not null default 0, '
      'completion_tokens integer not null default 0, '
      'created_at integer not null)',
];

/// 卡片模板的样式表。
const String kAnkiCss = '.card {\n'
    '  font-family: Arial, "Microsoft YaHei", sans-serif;\n'
    '  font-size: 22px;\n'
    '  text-align: center;\n'
    '  color: #1f2430;\n'
    '  background-color: #ffffff;\n'
    '}\n'
    '.wc-def { font-size: 26px; font-weight: 600; margin: 8px 0; }\n'
    '.wc-ph { color: #6b7280; font-size: 18px; }\n'
    '.wc-pos { color: #2563eb; font-size: 18px; }\n'
    '.wc-ex { color: #374151; font-size: 18px; margin-top: 10px; }\n'
    '.wc-note { color: #9ca3af; font-size: 16px; margin-top: 8px; }';

/// LaTeX 前言，Anki 需要这两个字段，内容用官方的默认值。
const String kAnkiLatexPre =
    '\\documentclass[12pt]{article}\n'
    '\\special{papersize=3in,5in}\n'
    '\\usepackage[utf8]{inputenc}\n'
    '\\usepackage{amssymb,amsmath}\n'
    '\\pagestyle{empty}\n'
    '\\setlength{\\parindent}{0in}\n'
    '\\begin{document}';

const String kAnkiLatexPost = '\\end{document}';

/// col.conf 的默认值。
Map<String, Object?> ankiDefaultConf(int modelId) => <String, Object?>{
      'nextPos': 1,
      'estTimes': true,
      'activeDecks': <Object?>[kDefaultAnkiDeckId],
      'sortType': 'noteFld',
      'timeLim': 0,
      'sortBackwards': false,
      'addToCur': true,
      'curDeck': kDefaultAnkiDeckId,
      'newBury': true,
      'newSpread': 0,
      'dueCounts': true,
      'curModel': modelId,
      'collapseTime': 1200,
    };

/// col.dconf 的默认牌组配置（Anki 的 Default preset）。
Map<String, Object?> ankiDefaultDeckConfig() => <String, Object?>{
      'id': 1,
      'mod': 0,
      'name': 'Default',
      'usn': 0,
      'maxTaken': 60,
      'autoplay': true,
      'timer': 0,
      'replayq': true,
      'new': <String, Object?>{
        'bury': true,
        'delays': <Object?>[1, 10],
        'initialFactor': 2500,
        'ints': <Object?>[1, 4, 7],
        'order': 1,
        'perDay': 20,
        'separate': true,
      },
      'rev': <String, Object?>{
        'bury': true,
        'ease4': 1.3,
        'fuzz': 0.05,
        'ivlFct': 1,
        'maxIvl': 36500,
        'minSpace': 1,
        'perDay': 200,
      },
      'lapse': <String, Object?>{
        'delays': <Object?>[10],
        'leechAction': 0,
        'leechFails': 8,
        'minInt': 1,
        'mult': 0,
      },
      'dyn': false,
    };

/// col.decks 里的单个牌组。
///
/// [suspended] 是应用自己的扩展键（[kAnkiSuspendedKey]），Anki 不认识，
/// 但会原样保留在 JSON 里；写成 1 而不是 true，和这里的其它布尔字段一致。
Map<String, Object?> ankiDeck(
  int id,
  String name,
  int nowSec, {
  bool suspended = false,
}) =>
    <String, Object?>{
      'id': id,
      'mod': nowSec,
      'name': name,
      'usn': 0,
      'lrnToday': <Object?>[0, 0],
      'revToday': <Object?>[0, 0],
      'newToday': <Object?>[0, 0],
      'timeToday': <Object?>[0, 0],
      'conf': 1,
      'desc': '',
      'dyn': 0,
      'collapsed': false,
      'browserCollapsed': false,
      'extendNew': 10,
      'extendRev': 50,
      if (suspended) kAnkiSuspendedKey: 1,
    };

/// 牌组 JSON 里表示「已挂起」的扩展键。
const String kAnkiSuspendedKey = 'wcSuspended';

/// col.models 里的笔记类型。
Map<String, Object?> ankiNotetype(int nowSec) {
  Map<String, Object?> field(String name, int ord) => <String, Object?>{
        'name': name,
        'ord': ord,
        'sticky': false,
        'rtl': false,
        'font': 'Arial',
        'size': 20,
        'media': <Object?>[],
      };

  const String qfmt = '{{单词}}';
  const String afmt = '{{FrontSide}}\n'
      '\n'
      '<hr id=answer>\n'
      '\n'
      '<div class="wc-def">{{释义}}</div>\n'
      '{{#音标}}<div class="wc-ph">{{音标}}</div>{{/音标}}\n'
      '{{#词性}}<div class="wc-pos">{{词性}}</div>{{/词性}}\n'
      '{{#例句}}<div class="wc-ex">{{例句}}</div>{{/例句}}\n'
      '{{#备注}}<div class="wc-note">{{备注}}</div>{{/备注}}';

  return <String, Object?>{
    'id': kAnkiNotetypeId,
    'name': kAnkiNotetypeName,
    'type': 0,
    'mod': nowSec,
    'usn': 0,
    'sortf': kFieldWord,
    'did': kDefaultAnkiDeckId,
    'tmpls': <Object?>[
      <String, Object?>{
        'name': kAnkiTemplateName,
        'ord': 0,
        'qfmt': qfmt,
        'afmt': afmt,
        'did': null,
        'bqfmt': '',
        'bafmt': '',
      },
    ],
    'flds': <Object?>[
      for (int i = 0; i < kNoteFields.length; i++) field(kNoteFields[i], i),
    ],
    'css': kAnkiCss,
    'latexPre': kAnkiLatexPre,
    'latexPost': kAnkiLatexPost,
    'req': <Object?>[
      <Object?>[0, 'all', <Object?>[kFieldWord]],
    ],
    'tags': <Object?>[],
    'vers': <Object?>[],
  };
}
