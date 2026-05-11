/// TTS 服务商。
enum TtsProvider {
  volc, // 火山引擎豆包语音合成 2.0（主路径）
  xunfei; // 讯飞超拟人（fallback / 备用）

  static TtsProvider fromVoiceCode(String code) {
    // 讯飞音色 code 形如 x6_*/x5_*；火山音色没有这两种前缀。
    if (code.startsWith('x6_') || code.startsWith('x5_')) {
      return TtsProvider.xunfei;
    }
    return TtsProvider.volc;
  }
}

/// 火山豆包 TTS 2.0 的 X-Api-Resource-Id，按音色前缀路由。
String volcResourceIdForVoice(String code) {
  // saturn_ 前缀的是声音复刻 2.0（ICL）音色，必须用 seed-icl-2.0 资源
  if (code.startsWith('saturn_')) return 'seed-icl-2.0';
  // 其他火山音色走主 TTS 资源
  return 'seed-tts-2.0';
}

const String kDefaultTtsVoice = 'zh_female_xiaohe_uranus_bigtts';

/// 播报模式，决定小治回答时是否自动出声。
///
/// - [auto]：默认。语音输入（长按悬浮球 / 抽屉里语音）→ 播；文字输入 → 不播。
///   解决"我用嘴问，结果回答只显示在屏幕上不读出来"的反直觉体验。
/// - [always]：所有回答都播。
/// - [shortOnly]：仅短答（底部胶囊卡片）播；进抽屉的长答静默。
/// - [silent]：完全不播。
enum TtsPlaybackMode {
  auto,
  always,
  shortOnly,
  silent;

  static TtsPlaybackMode fromCode(String? code) {
    switch (code) {
      case 'always':
        return TtsPlaybackMode.always;
      case 'shortOnly':
        return TtsPlaybackMode.shortOnly;
      case 'silent':
        return TtsPlaybackMode.silent;
      case 'auto':
      default:
        return TtsPlaybackMode.auto;
    }
  }

  String get code {
    switch (this) {
      case TtsPlaybackMode.auto:
        return 'auto';
      case TtsPlaybackMode.always:
        return 'always';
      case TtsPlaybackMode.shortOnly:
        return 'shortOnly';
      case TtsPlaybackMode.silent:
        return 'silent';
    }
  }

  String get label {
    switch (this) {
      case TtsPlaybackMode.auto:
        return '自动';
      case TtsPlaybackMode.always:
        return '始终播报';
      case TtsPlaybackMode.shortOnly:
        return '仅短答播报';
      case TtsPlaybackMode.silent:
        return '静音';
    }
  }

  String get description {
    switch (this) {
      case TtsPlaybackMode.auto:
        return '语音问的会播，文字打的静默';
      case TtsPlaybackMode.always:
        return '所有回答都用声音读出来';
      case TtsPlaybackMode.shortOnly:
        return '只播快速语音问到的短答';
      case TtsPlaybackMode.silent:
        return '完全不出声';
    }
  }
}

const TtsPlaybackMode kDefaultTtsPlaybackMode = TtsPlaybackMode.auto;

/// 播报语速档位（对外语义化倍率）。0.8 ≈ 慢；1.0 ≈ 标准；1.2/1.5 ≈ 快。
const List<double> kTtsSpeedOptions = <double>[0.8, 1.0, 1.2, 1.5];
const double kDefaultTtsSpeed = 1.0;

/// 把任意 double 落到最近的合法档位。
double normalizeTtsSpeed(double value) {
  if (value.isNaN || value.isInfinite) return kDefaultTtsSpeed;
  double best = kDefaultTtsSpeed;
  double bestDiff = (value - best).abs();
  for (final double option in kTtsSpeedOptions) {
    final double diff = (value - option).abs();
    if (diff < bestDiff) {
      bestDiff = diff;
      best = option;
    }
  }
  return best;
}

/// 把语义化倍率映射到讯飞 business.speed（0-100，默认 50）。
/// 经验值，确保 1.5x 听起来明显比 1.0x 快但不爆音。
int xunfeiSpeedForRate(double rate) {
  final double normalized = normalizeTtsSpeed(rate);
  if (normalized == 0.8) return 30;
  if (normalized == 1.0) return 50;
  if (normalized == 1.2) return 65;
  if (normalized == 1.5) return 85;
  return 50;
}

String ttsSpeedLabel(double rate) {
  final double n = normalizeTtsSpeed(rate);
  if (n == 0.8) return '慢速 (0.8x)';
  if (n == 1.0) return '标准 (1.0x)';
  if (n == 1.2) return '稍快 (1.2x)';
  if (n == 1.5) return '快速 (1.5x)';
  return '标准 (1.0x)';
}

class TtsVoiceOption {
  const TtsVoiceOption({
    required this.code,
    required this.label,
    required this.description,
  });

  final String code;
  final String label;
  final String description;
}

const List<TtsVoiceOption> kTtsVoiceOptions = <TtsVoiceOption>[
  // —— 豆包语音合成 2.0（主路径，需要在火山控制台音色管理里授权）——
  TtsVoiceOption(
    code: 'zh_female_xiaohe_uranus_bigtts',
    label: '小荷',
    description: '默认女声，自然柔和，适合日常对话',
  ),
  TtsVoiceOption(
    code: 'zh_male_liufei_uranus_bigtts',
    label: '刘飞',
    description: '沉稳男声，适合提醒和播报',
  ),
  TtsVoiceOption(
    code: 'saturn_zh_female_qingyingduoduo_cs_tob',
    label: '轻盈朵朵',
    description: '知性活力的女老师（声音复刻 2.0）',
  ),
  TtsVoiceOption(
    code: 'zh_female_vv_uranus_bigtts',
    label: 'Vivi',
    description: '语调平稳、咬字柔和的女声',
  ),
  TtsVoiceOption(
    code: 'zh_male_m191_uranus_bigtts',
    label: '云舟',
    description: '声音磁性的男生',
  ),
  TtsVoiceOption(
    code: 'zh_male_shaonianzixin_uranus_bigtts',
    label: '少年自信',
    description: '少年感十足的清爽男生',
  ),
  // —— 讯飞超拟人（备用 / fallback）——
  TtsVoiceOption(
    code: 'x6_lingxiaoxuan_pro',
    label: '聆小璇（讯飞备用）',
    description: '讯飞女声，火山服务异常时自动降级使用',
  ),
];

String normalizeTtsVoiceCode(String code) {
  for (final TtsVoiceOption option in kTtsVoiceOptions) {
    if (option.code == code) {
      return option.code;
    }
  }
  return kDefaultTtsVoice;
}

TtsVoiceOption ttsVoiceOptionFor(String code) {
  final String normalized = normalizeTtsVoiceCode(code);
  for (final TtsVoiceOption option in kTtsVoiceOptions) {
    if (option.code == normalized) {
      return option;
    }
  }
  return kTtsVoiceOptions.firstWhere(
    (TtsVoiceOption option) => option.code == kDefaultTtsVoice,
  );
}

class AppSettings {
  const AppSettings({
    this.remindersEnabled = true,
    this.showCompleted = true,
    this.showLunar = true,
    this.localeCode = 'zh-CN',
    this.ttsVoice = kDefaultTtsVoice,
    this.ttsPlaybackMode = kDefaultTtsPlaybackMode,
    this.ttsSpeed = kDefaultTtsSpeed,
  });

  factory AppSettings.fromMap(Map<String, Object?> map) {
    final Object? rawSpeed = map['tts_speed'];
    final double parsedSpeed = rawSpeed is num
        ? rawSpeed.toDouble()
        : (rawSpeed is String ? double.tryParse(rawSpeed) ?? kDefaultTtsSpeed : kDefaultTtsSpeed);
    return AppSettings(
      remindersEnabled: (map['reminders_enabled'] as int? ?? 1) == 1,
      showCompleted: (map['show_completed'] as int? ?? 1) == 1,
      showLunar: (map['show_lunar'] as int? ?? 1) == 1,
      localeCode: map['locale_code'] as String? ?? 'zh-CN',
      ttsVoice: normalizeTtsVoiceCode(
        map['tts_voice'] as String? ?? kDefaultTtsVoice,
      ),
      ttsPlaybackMode: TtsPlaybackMode.fromCode(
        map['tts_playback_mode'] as String?,
      ),
      ttsSpeed: normalizeTtsSpeed(parsedSpeed),
    );
  }

  final bool remindersEnabled;
  final bool showCompleted;
  final bool showLunar;
  final String localeCode;
  final String ttsVoice;
  final TtsPlaybackMode ttsPlaybackMode;
  final double ttsSpeed;

  AppSettings copyWith({
    bool? remindersEnabled,
    bool? showCompleted,
    bool? showLunar,
    String? localeCode,
    String? ttsVoice,
    TtsPlaybackMode? ttsPlaybackMode,
    double? ttsSpeed,
  }) {
    return AppSettings(
      remindersEnabled: remindersEnabled ?? this.remindersEnabled,
      showCompleted: showCompleted ?? this.showCompleted,
      showLunar: showLunar ?? this.showLunar,
      localeCode: localeCode ?? this.localeCode,
      ttsVoice: ttsVoice ?? this.ttsVoice,
      ttsPlaybackMode: ttsPlaybackMode ?? this.ttsPlaybackMode,
      ttsSpeed: ttsSpeed != null ? normalizeTtsSpeed(ttsSpeed) : this.ttsSpeed,
    );
  }

  Map<String, Object?> toDatabaseMap(DateTime now) {
    final String timestamp = now.toIso8601String();
    return <String, Object?>{
      'id': 1,
      'reminders_enabled': remindersEnabled ? 1 : 0,
      'show_completed': showCompleted ? 1 : 0,
      'show_lunar': showLunar ? 1 : 0,
      'locale_code': localeCode,
      'tts_voice': ttsVoice,
      'tts_playback_mode': ttsPlaybackMode.code,
      'tts_speed': ttsSpeed,
      'created_at': timestamp,
      'updated_at': timestamp,
    };
  }
}
