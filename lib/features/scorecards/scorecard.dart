import 'dart:math' as math;
import 'package:uuid/uuid.dart';

/// Standalone cards never create fixtures, send messages or advance a draw.
class Scorecard {
  Scorecard({required this.id, required this.title, required this.date});
  final String id;
  String title, date;
  String venue = '',
      rink = '',
      format = 'Singles',
      sideA = 'Side A',
      sideB = 'Side B';
  String playersA = '', playersB = '', marker = '', notes = '';
  int woods = 4, handicapA = 0, handicapB = 0;
  String scoring = 'shots';
  int? target, maxEnds, durationMinutes, lastJackMinutes;
  DateTime? startedAt, finishedAt;
  int revision = 0;
  int saveVersion = 0;
  final List<Map<String, dynamic>> ends = [];
  final List<Map<String, dynamic>> history = [];
  Map<String, dynamic>? signatureA, signatureB;

  factory Scorecard.create() => Scorecard(
    id: const Uuid().v4(),
    title: '',
    date: DateTime.now().toIso8601String().substring(0, 10),
  );
  int get totalA =>
      handicapA + ends.fold<int>(0, (n, e) => n + (e['a'] as int? ?? 0));
  int get totalB =>
      handicapB + ends.fold<int>(0, (n, e) => n + (e['b'] as int? ?? 0));
  bool get endInProgress => ends.isNotEmpty && ends.last['a'] == null;
  bool get complete => finishedAt != null;
  bool get hasSignatures => signatureA != null || signatureB != null;
  int elapsedSeconds(DateTime now) => startedAt == null
      ? 0
      : math.max(0, (finishedAt ?? now).difference(startedAt!).inSeconds);
  bool deadlineReached(DateTime now) =>
      startedAt != null &&
      lastJackMinutes != null &&
      elapsedSeconds(now) >= lastJackMinutes! * 60;
  String? cannotStartEnd(DateTime now) {
    if (complete) {
      return 'This scorecard is finished. Reopen it before making changes.';
    }
    if (startedAt == null) return 'Start the match first.';
    if (now.isBefore(startedAt!)) {
      return 'The device clock is earlier than the match start. Check the clock before continuing.';
    }
    if (endInProgress) return 'Record the current end before starting another.';
    if (deadlineReached(now)) {
      return 'Last-jack deadline reached. No further end may start.';
    }
    if (maxEnds != null && ends.length >= maxEnds!) {
      return 'The configured number of ends has been reached.';
    }
    if (target != null && (totalA >= target! || totalB >= target!)) {
      return 'The target score has been reached. Review and finish the card.';
    }
    return null;
  }

  void changed(String action, {Object? before, Object? after}) {
    revision++;
    signatureA = signatureB = null;
    history.add({
      'at': DateTime.now().toUtc().toIso8601String(),
      'action': action,
      'before': before,
      'after': after,
      'revision': revision,
    });
  }

  void startMatch(DateTime now) {
    if (startedAt != null) throw StateError('Match already started.');
    startedAt = now.toUtc();
    changed('Match started', after: startedAt!.toIso8601String());
  }

  void startEnd(DateTime now, {bool automatic = false}) {
    final reason = cannotStartEnd(now);
    if (reason != null) throw StateError(reason);
    ends.add({
      'jackAt': now.toUtc().toIso8601String(),
      'a': null,
      'b': null,
      'automatic': automatic,
    });
    changed(
      automatic
          ? 'End ${ends.length} started automatically after accepting the previous end'
          : 'Jack delivered: end ${ends.length}',
    );
  }

  void acceptEndScore(int index, int a, int b, DateTime now) {
    final advance = endInProgress && index == ends.length - 1;
    recordEnd(index, a, b);
    if (advance && cannotStartEnd(now) == null) {
      startEnd(now, automatic: true);
    }
  }

  void recordEnd(int index, int a, int b) {
    if (complete) {
      throw StateError('Reopen the scorecard before correcting scores.');
    }
    if (index < 0 || index >= ends.length) {
      throw StateError('End does not exist.');
    }
    if (a < 0 || b < 0) throw StateError('End scores cannot be negative.');
    if (scoring == 'shots' && a > 0 && b > 0) {
      throw StateError('For normal shots, only one side scores in an end.');
    }
    if (scoring == '100up' && a + b != 10) {
      throw StateError(
        'For 100 Up, the two scores must total 10 (4 + 3 + 2 + 1).',
      );
    }
    final before = Map<String, dynamic>.from(ends[index]);
    ends[index] = {...before, 'a': a, 'b': b};
    changed(
      'Score recorded: end ${index + 1}',
      before: before,
      after: Map<String, dynamic>.from(ends[index]),
    );
  }

  void finish(DateTime now) {
    if (!complete && endInProgress && ends.last['automatic'] == true) {
      ends.removeLast();
      changed('Unused automatically prepared end removed on finishing');
    }
    if (complete || ends.isEmpty || endInProgress) {
      throw StateError('Record all started ends before finishing.');
    }
    finishedAt = now.toUtc();
    changed('Scorecard finished');
  }

  void reopen() {
    finishedAt = null;
    changed('Scorecard reopened; signatures invalidated');
  }

  void sign(bool side, String name, List<List<Map<String, double>>> strokes) {
    if (!complete) {
      throw StateError('Finish and review the scorecard before signing.');
    }
    if (name.trim().isEmpty || !strokes.any((s) => s.length > 1)) {
      throw StateError('Enter a name and draw a signature.');
    }
    final value = {
      'name': name.trim(),
      'at': DateTime.now().toUtc().toIso8601String(),
      'revision': revision,
      'strokes': strokes,
    };
    if (side) {
      signatureA = value;
    } else {
      signatureB = value;
    }
  }

  Map<String, dynamic> toJson() => {
    'schema': 1,
    'saveVersion': saveVersion,
    'id': id,
    'title': title,
    'date': date,
    'venue': venue,
    'rink': rink,
    'format': format,
    'sideA': sideA,
    'sideB': sideB,
    'playersA': playersA,
    'playersB': playersB,
    'marker': marker,
    'notes': notes,
    'woods': woods,
    'handicapA': handicapA,
    'handicapB': handicapB,
    'scoring': scoring,
    'target': target,
    'maxEnds': maxEnds,
    'durationMinutes': durationMinutes,
    'lastJackMinutes': lastJackMinutes,
    'startedAt': startedAt?.toIso8601String(),
    'finishedAt': finishedAt?.toIso8601String(),
    'revision': revision,
    'ends': ends,
    'history': history,
    'signatureA': signatureA,
    'signatureB': signatureB,
  };
  factory Scorecard.fromJson(Map<String, dynamic> j) {
    if (j['schema'] != 1) {
      throw const FormatException('Unsupported scorecard version.');
    }
    final c = Scorecard(
      id: j['id'] as String,
      title: j['title'] as String,
      date: j['date'] as String,
    );
    c.venue = j['venue'] as String;
    c.rink = j['rink'] as String;
    c.format = j['format'] as String;
    c.sideA = j['sideA'] as String;
    c.sideB = j['sideB'] as String;
    c.playersA = j['playersA'] as String;
    c.playersB = j['playersB'] as String;
    c.marker = j['marker'] as String;
    c.notes = j['notes'] as String;
    c.woods = j['woods'] as int;
    c.handicapA = j['handicapA'] as int;
    c.handicapB = j['handicapB'] as int;
    c.scoring = j['scoring'] as String;
    c.target = j['target'] as int?;
    c.maxEnds = j['maxEnds'] as int?;
    c.durationMinutes = j['durationMinutes'] as int?;
    c.lastJackMinutes = j['lastJackMinutes'] as int?;
    c.startedAt = DateTime.tryParse(j['startedAt'] as String? ?? '');
    c.finishedAt = DateTime.tryParse(j['finishedAt'] as String? ?? '');
    c.revision = j['revision'] as int;
    c.saveVersion = j['saveVersion'] as int? ?? 0;
    c.ends.addAll(
      (j['ends'] as List).map((e) => Map<String, dynamic>.from(e as Map)),
    );
    c.history.addAll(
      (j['history'] as List).map((e) => Map<String, dynamic>.from(e as Map)),
    );
    c.signatureA = (j['signatureA'] as Map?)?.cast<String, dynamic>();
    c.signatureB = (j['signatureB'] as Map?)?.cast<String, dynamic>();
    return c;
  }
}
