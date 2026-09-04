import "../../../core/update/github_urls.dart";
import "preferences_manager.dart";
import "schedule_times_remote.dart";

class LessonTimesSyncResult {
  const LessonTimesSyncResult({
    required this.ok,
    required this.changed,
    this.skipped = false,
  });

  /// Запрос прошёл (или был осознанно пропущен по интервалу).
  final bool ok;

  /// Время пар изменилось — расписание нужно перерисовать.
  final bool changed;

  /// Ничего не запрашивали: рано по интервалу или ждём после ошибки.
  final bool skipped;
}

/// Синхронизация времени пар с `schedule_times.json`.
///
/// Вынесена из ScheduleController, чтобы её мог запускать и фоновый воркер:
/// иначе виджет и напоминания жили на старом времени, пока пользователь не
/// откроет приложение.
class LessonTimesSync {
  LessonTimesSync(this._prefs, {ScheduleTimesRemoteService? service})
      : _service = service ?? ScheduleTimesRemoteService();

  final PreferencesManager _prefs;
  final ScheduleTimesRemoteService _service;

  /// Пауза после первой неудачи; дальше удваивается до [_maxBackoff].
  static const Duration _baseBackoff = Duration(minutes: 15);
  static const Duration _maxBackoff = Duration(hours: 6);

  /// Общий потолок на всю цепочку запросов. GitHubHttpClient сам даёт 8 с и
  /// два захода на URL, а фолбэков три — без этого холодный старт на плохой
  /// сети упирался в десятки секунд.
  static const Duration _totalTimeout = Duration(seconds: 12);

  Future<LessonTimesSyncResult> run({bool force = false}) async {
    final url = _prefs.lessonTimesRemoteUrl.trim();
    if (url.isEmpty ||
        (!url.startsWith("http://") && !url.startsWith("https://"))) {
      throw const FormatException("Некорректная ссылка на файл времени пар");
    }

    final nowMs = DateTime.now().millisecondsSinceEpoch;
    if (!force && !_dueForCheck(nowMs)) {
      return const LessonTimesSyncResult(
          ok: true, changed: false, skipped: true);
    }

    final useEtag = _prefs.lessonTimesUseEtag;
    final etag = _prefs.lessonTimesRemoteEtag;

    final ScheduleTimesFetchOutcome outcome;
    try {
      outcome = await _fetchWithFallbacks(
        url,
        useEtag: useEtag,
        etag: etag,
      ).timeout(_totalTimeout);
    } catch (_) {
      _noteFailure(nowMs);
      rethrow;
    }

    _noteSuccess();
    _prefs.lessonTimesRemoteCheckedAt = nowMs;

    if (outcome is ScheduleTimesFetchNotModified) {
      return const LessonTimesSyncResult(ok: true, changed: false);
    }
    if (outcome is! ScheduleTimesFetchSuccess) {
      return const LessonTimesSyncResult(ok: false, changed: false);
    }

    _prefs.lessonTimesMinIntervalHours =
        outcome.hints.minIntervalHours.clamp(1, 168);
    _prefs.lessonTimesUseEtag = outcome.hints.useEtagIfPossible;
    final newEtag = outcome.etag?.trim();
    if (newEtag != null && newEtag.isNotEmpty) {
      _prefs.lessonTimesRemoteEtag = newEtag;
    }

    final data = outcome.data;
    final changed = data.fingerprint != _prefs.lessonTimesRemoteFingerprint;
    if (!changed && !force) {
      return const LessonTimesSyncResult(ok: true, changed: false);
    }

    for (final entry in data.byCollege.entries) {
      if (entry.value.isEmpty) continue;
      _prefs.setRemoteLessonTimes(entry.key, entry.value);
    }
    _prefs.applyStoredLessonTimes();
    _prefs.lessonTimesRemoteFingerprint = data.fingerprint;
    _prefs.lessonTimesRemoteSyncedAt = DateTime.now().millisecondsSinceEpoch;

    return LessonTimesSyncResult(ok: true, changed: changed);
  }

  /// Пора ли проверять: истёк ли интервал из подсказок файла и не ждём ли мы
  /// паузу после неудачных попыток.
  bool _dueForCheck(int nowMs) {
    final retryAfter = _prefs.lessonTimesRetryAfter;
    if (retryAfter > nowMs) return false;
    final lastCheckedAt = _prefs.lessonTimesRemoteCheckedAt;
    if (lastCheckedAt == null) return true;
    final intervalMs =
        Duration(hours: _prefs.lessonTimesMinIntervalHours).inMilliseconds;
    return nowMs - lastCheckedAt >= intervalMs;
  }

  /// Цепочка фолбэков как у обновлялки: ветка data → master → легаси-файл.
  /// Работает и если ветка data ещё не создана или недоступна.
  Future<ScheduleTimesFetchOutcome> _fetchWithFallbacks(
    String url, {
    required bool useEtag,
    required String etag,
  }) async {
    try {
      return await _service.fetch(
        url,
        ifNoneMatch: useEtag && etag.isNotEmpty ? etag : null,
        sendConditional: useEtag && etag.isNotEmpty,
      );
    } catch (_) {
      if (!url.contains(GitHubProjectUrls.scheduleTimesFile)) rethrow;
      try {
        return await _service.fetch(
          GitHubProjectUrls.scheduleTimesMasterFallbackRaw,
          ifNoneMatch: null,
          sendConditional: false,
        );
      } catch (_) {
        return await _service.fetch(
          GitHubProjectUrls.lessonTimesLegacyRaw,
          ifNoneMatch: null,
          sendConditional: false,
        );
      }
    }
  }

  /// Растущая пауза после ошибки: без неё каждый запуск приложения на плохой
  /// сети упирался в полную цепочку запросов с нуля.
  void _noteFailure(int nowMs) {
    final fails = (_prefs.lessonTimesFailCount + 1).clamp(1, 16);
    _prefs.lessonTimesFailCount = fails;
    var delay = _baseBackoff * (1 << (fails - 1));
    if (delay > _maxBackoff) delay = _maxBackoff;
    _prefs.lessonTimesRetryAfter = nowMs + delay.inMilliseconds;
  }

  void _noteSuccess() {
    if (_prefs.lessonTimesFailCount != 0) _prefs.lessonTimesFailCount = 0;
    if (_prefs.lessonTimesRetryAfter != 0) _prefs.lessonTimesRetryAfter = 0;
  }
}
