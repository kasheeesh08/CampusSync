import 'dart:convert';

import 'models.dart';

class ImportResult {
  final List<TimetableEntry> entries;
  final List<String> errors;
  const ImportResult(this.entries, this.errors);
  bool get ok => errors.isEmpty && entries.isNotEmpty;
}

/// Parses admin-uploaded timetable data (CSV or JSON) into entries.
///
/// CSV header (case-insensitive, order free):
/// `weekday,start,end,kind,subject,faculty,room,batch,shared_note`
/// - weekday: Mon..Sun or 1..7; kind: lecture|lab|tutorial|elective|break|library
/// - faculty: faculty id or initials; room: room id, code or alias.
class TimetableImporter {
  final List<Room> rooms;
  final List<Faculty> faculty;

  TimetableImporter({required this.rooms, required this.faculty});

  static const requiredColumns = ['weekday', 'start', 'end', 'kind'];
  static const supportedExtensions = ['csv', 'json'];

  /// 'csv' | 'json' for supported uploads, otherwise null.
  static String? formatFor(String fileName) {
    final dot = fileName.lastIndexOf('.');
    final ext = dot < 0 ? '' : fileName.substring(dot + 1).toLowerCase();
    return supportedExtensions.contains(ext) ? ext : null;
  }

  /// Parses an uploaded file, rejecting unsupported types instead of guessing.
  ImportResult parseFile(String fileName, String text, {String idPrefix = 'e'}) {
    final format = formatFor(fileName);
    if (format == null) {
      return ImportResult(const [], ['Unsupported file type "$fileName". Upload a .csv or .json timetable.']);
    }
    if (text.trim().isEmpty) return ImportResult(const [], ['"$fileName" is empty.']);
    return format == 'json' ? parseJson(text) : parseCsv(text, idPrefix: idPrefix);
  }

  String? resolveRoom(String raw) {
    final v = raw.trim();
    if (v.isEmpty) return null;
    String norm(String s) => s.toUpperCase().replaceAll(RegExp(r'^E\.\s*'), '').replaceAll(RegExp(r'[\s\-.]'), '');
    final n = norm(v);
    for (final r in rooms) {
      if (norm(r.id) == n || norm(r.code) == n || norm(r.name) == n || r.aliases.any((a) => norm(a) == n)) return r.id;
    }
    return null;
  }

  Faculty? resolveFaculty(String raw) {
    final v = raw.trim();
    if (v.isEmpty) return null;
    for (final f in faculty) {
      if (f.id == v || f.initials.any((i) => i.toUpperCase() == v.toUpperCase())) return f;
    }
    return null;
  }

  static int? parseWeekday(String raw) {
    final v = raw.trim().toLowerCase();
    final n = int.tryParse(v);
    if (n != null) return (n >= 1 && n <= 7) ? n : null;
    for (var i = 0; i < 7; i++) {
      if (v.startsWith(weekdayShort[i].toLowerCase())) return i + 1;
    }
    return null;
  }

  ImportResult parseCsv(String text, {String idPrefix = 'e'}) {
    final lines = const LineSplitter().convert(text).where((l) => l.trim().isNotEmpty).toList();
    if (lines.isEmpty) return const ImportResult([], ['File is empty.']);
    final header = _splitCsv(lines.first).map((h) => h.trim().toLowerCase()).toList();
    final missing = requiredColumns.where((c) => !header.contains(c)).toList();
    if (missing.isNotEmpty) return ImportResult(const [], ['Missing column(s): ${missing.join(', ')}.']);

    final entries = <TimetableEntry>[];
    final errors = <String>[];
    for (var i = 1; i < lines.length; i++) {
      final cells = _splitCsv(lines[i]);
      String col(String name) {
        final idx = header.indexOf(name);
        return idx >= 0 && idx < cells.length ? cells[idx].trim() : '';
      }

      final lineNo = i + 1;
      final rowErrors = <String>[];
      final weekday = parseWeekday(col('weekday'));
      if (weekday == null) rowErrors.add('invalid weekday "${col('weekday')}"');
      int? start, end;
      try {
        start = parseHm(col('start'));
        end = parseHm(col('end'));
        if (end <= start) rowErrors.add('end time must be after start time');
      } on FormatException catch (e) {
        rowErrors.add(e.message);
      }
      EntryKind? kind;
      try {
        kind = EntryKind.parse(col('kind').toLowerCase());
      } on FormatException catch (e) {
        rowErrors.add(e.message);
      }
      final roomRaw = col('room');
      final roomId = resolveRoom(roomRaw);
      if (roomRaw.isNotEmpty && roomId == null) rowErrors.add('unknown room "$roomRaw"');
      final facRaw = col('faculty');
      final fac = resolveFaculty(facRaw);
      if (facRaw.isNotEmpty && fac == null) rowErrors.add('unknown faculty "$facRaw"');

      if (rowErrors.isNotEmpty) {
        errors.add('Line $lineNo: ${rowErrors.join('; ')}.');
        continue;
      }
      String? opt(String c) => col(c).isEmpty ? null : col(c);
      entries.add(
        TimetableEntry(
          id: '$idPrefix-${(i - 1).toString().padLeft(3, '0')}',
          weekday: weekday!,
          startMin: start!,
          endMin: end!,
          kind: kind!,
          subjectCode: opt('subject'),
          facultyId: fac?.id,
          facultyInitials: facRaw.isEmpty ? null : facRaw.toUpperCase(),
          roomId: roomId,
          roomLabel: opt('room'),
          batch: opt('batch'),
          sharedNote: opt('shared_note'),
        ),
      );
    }
    return ImportResult(entries, errors);
  }

  /// Accepts either a list of entries or `{ "entries": [...] }` in seed format.
  ImportResult parseJson(String text) {
    try {
      final decoded = jsonDecode(text);
      final list = decoded is List ? decoded : (decoded is Map ? decoded['entries'] : null);
      if (list is! List) return const ImportResult([], ['JSON must be a list of entries or contain an "entries" list.']);
      final entries = <TimetableEntry>[];
      final errors = <String>[];
      for (var i = 0; i < list.length; i++) {
        try {
          entries.add(TimetableEntry.fromJson(Map<String, dynamic>.from(list[i] as Map)));
        } catch (e) {
          errors.add('Entry ${i + 1}: $e');
        }
      }
      return ImportResult(entries, errors);
    } on FormatException catch (e) {
      return ImportResult(const [], ['Invalid JSON: ${e.message}']);
    }
  }

  static List<String> _splitCsv(String line) {
    final out = <String>[];
    final buf = StringBuffer();
    var quoted = false;
    for (var i = 0; i < line.length; i++) {
      final c = line[i];
      if (c == '"') {
        if (quoted && i + 1 < line.length && line[i + 1] == '"') {
          buf.write('"');
          i++;
        } else {
          quoted = !quoted;
        }
      } else if (c == ',' && !quoted) {
        out.add(buf.toString());
        buf.clear();
      } else {
        buf.write(c);
      }
    }
    out.add(buf.toString());
    return out;
  }
}
