import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:characters/characters.dart';
import 'dart:math' as math;

const bool releaseMode =
    bool.fromEnvironment('dart.vm.product', defaultValue: false);

const bool profileMode =
    bool.fromEnvironment('dart.vm.profile', defaultValue: false);
const bool debugMode = !releaseMode && !profileMode;

abstract class Log {
  static const int info = 0;
  static const int warn = 1;
  static const int error = 2;
  static int level = 0;
  static int functionLength = 18;

  static bool i(Object? info,
      {bool showPath = true, bool onlyDebug = true, Zone? zone}) {
    return _log(Log.info, info, StackTrace.current, showPath, onlyDebug, zone);
  }

  static bool w(Object? warn,
      {bool showPath = true, bool onlyDebug = true, Zone? zone}) {
    return _log(Log.warn, warn, StackTrace.current, showPath, onlyDebug, zone);
  }

  static bool e(Object? error,
      {bool showPath = true, bool onlyDebug = true, Zone? zone}) {
    return _log(
        Log.error, error, StackTrace.current, showPath, onlyDebug, zone);
  }

  static bool log(int lv, Object? message,
      {bool showPath = true,
      StackTrace? stackTrace,
      bool onlyDebug = true,
      Zone? zone}) {
    return _log(lv, message, stackTrace ?? StackTrace.current, showPath,
        onlyDebug, zone);
  }

  static bool _log(int lv, Object? message, StackTrace stackTrace,
      bool showPath, bool onlyDebug,
      [Zone? zone]) {
    if (message == null || (!debugMode && onlyDebug)) return true;
    zone ??= Zone.current;
    var start = '';
    var end = '';

    var path = '', name = '';

    final st = stackTrace.toString();

    final sp = LineSplitter.split(st).toList();
    final spl = sp[1].split(RegExp(r' +'));

    if (spl.length >= 3) {
      final _s = spl[1].split('.');
      name =
          _s.sublist(_s.length <= 1 ? 0 : 1, math.min(2, _s.length)).join('.');
      path = spl.last;

      if (name.length > functionLength) {
        name = '${name.substring(0, functionLength - 3)}...';
      } else {
        name = name.padRight(functionLength);
      }
    }

    start = '$start$name|';

    if (!Platform.isIOS) {
      var s = '';
      switch (lv) {
        case info:
          s = '\x1B[39m';
          break;
        case warn:
          s = '\x1B[33m';
          break;
        case error:
          s = '\x1B[31m';
          break;
        default:
          s = '';
      }
      start = '$s$start';
      end = '\x1B[0m';
    }

    if (showPath) {
      if (debugMode) {
        end = '$end $path';
      } else {
        var _path = path.replaceAll(')', '');
        end = '$end $_path:1)';
      }
    }
    final split = '$message'.split('\n').expand((e) => splitString(e)).toList();

    for (var i = 0; i < split.length; i++) {
      if (i < split.length - 1) {
        zone.print('$start${split[i]}');
      } else {
        zone.print('$start${split[i]}$end');
      }
    }
    return true;
  }

  static List<String> splitString(Object source) {
    final rawSource = source.toString().characters;
    final length = rawSource.length;
    final list = <String>[];
    if (length == 0) return list;
    const maxLength = 110;
    for (var i = 0; i < length;) {
      final end = math.min(i + 84, length);
      final subC = rawSource.getRange(i, end);
      final sub = subC.toString();
      var count = 0;
      if (sub.length > maxLength / 2) {
        for (var element in sub.codeUnits) {
          if (element >= 19968 && element <= 40869) count++;
          if (count > 5) {
            break;
          }
        }
      }
      if (count <= 5) {
        list.add(sub);
        i = end;
      } else {
        final buffer = StringBuffer();
        var hasLenght = maxLength;
        for (var item in subC) {
          if (hasLenght <= 0) break;
          buffer.write(item);
          if (item.length > 1) {
            hasLenght -= 2;
            continue;
          }
          final itemCode = item.codeUnits.first;
          if (itemCode >= 19968 && itemCode <= 40869) {
            hasLenght -= 2;
            continue;
          }
          hasLenght -= 1;
        }
        final source = buffer.toString();
        i += source.characters.length;
        list.add(source);
      }
    }
    return list;
  }
}
