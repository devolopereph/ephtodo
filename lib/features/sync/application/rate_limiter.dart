import 'dart:collection';

import '../domain/sync_models.dart';

final class AttemptLimiter {
  AttemptLimiter({
    required this.maxAttempts,
    required this.window,
    required this.baseLockout,
    Stopwatch? monotonicClock,
  }) : _clock = monotonicClock ?? (Stopwatch()..start());

  final int maxAttempts;
  final Duration window;
  final Duration baseLockout;
  final Stopwatch _clock;
  final Map<String, _AttemptState> _states = {};

  void check(String key) {
    final state = _states[key];
    if (state == null) return;
    final now = _clock.elapsedMilliseconds;
    if (state.lockedUntilMs > now) {
      throw const SyncApiException(
        'temporarily_locked',
        'Too many attempts. Try again later.',
        statusCode: 429,
      );
    }
    _trim(state, now);
  }

  void failed(String key) {
    final now = _clock.elapsedMilliseconds;
    final state = _states.putIfAbsent(key, _AttemptState.new);
    _trim(state, now);
    state.attempts.addLast(now);
    if (state.attempts.length >= maxAttempts) {
      state.lockoutCount++;
      final multiplier = 1 << (state.lockoutCount - 1).clamp(0, 5);
      state.lockedUntilMs = now + baseLockout.inMilliseconds * multiplier;
      state.attempts.clear();
    }
  }

  void succeeded(String key) => _states.remove(key);

  void clear() => _states.clear();

  void _trim(_AttemptState state, int now) {
    final cutoff = now - window.inMilliseconds;
    while (state.attempts.isNotEmpty && state.attempts.first < cutoff) {
      state.attempts.removeFirst();
    }
    if (state.lockedUntilMs <= now && state.attempts.isEmpty) {
      state.lockedUntilMs = 0;
    }
  }
}

final class _AttemptState {
  final Queue<int> attempts = Queue<int>();
  int lockedUntilMs = 0;
  int lockoutCount = 0;
}
