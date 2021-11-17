import 'dart:async';
import 'dart:convert';
import 'dart:io';

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
  static int functionLength = 24;

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
    var addMsg = '';

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

    addMsg = '$addMsg$name|$message.';

    if (!Platform.isIOS) {
      var start = '';
      switch (lv) {
        case info:
          start = '\x1B[39m';
          break;
        case warn:
          start = '\x1B[33m';
          break;
        case error:
          start = '\x1B[31m';
          break;
        default:
          start = '';
      }
      addMsg = '$start$addMsg\x1B[0m';
    }

    if (showPath) {
      if (debugMode) {
        addMsg = '$addMsg $path';
      } else {
        var _path = path.replaceAll(')', '');
        addMsg = '$addMsg $_path:1)';
      }
    }

    // ignore: avoid_print
    zone.print(addMsg);
    return true;
  }
}
