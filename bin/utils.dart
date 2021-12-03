// ignore_for_file: avoid_print

import 'dart:convert';

import 'package:args/args.dart';
import 'package:file/file.dart';
import 'package:file/local.dart';

void main(List<String> args) {
  final argParser = ArgParser();

  argParser.addMultiOption('files');
  argParser.addOption('dir');
  argParser.addOption('safeTo');
  argParser.addOption('oneFileRename');
  argParser.addOption('prefix');

  const fs = LocalFileSystem();

  final result = argParser.parse(args);
  final files = result['files'] as List<String>? ?? const [];
  final dir = result['dir'] as String? ?? '';
  final safeTo = result['safeTo'] as String? ?? '';
  final oneFileRename = result['oneFileRename'] as String? ?? '';
  final prefix = result['prefix'] as String?;

  final safeToDir = fs.currentDirectory.childDirectory(safeTo);
  final allFiles = <File>[];
  if (files.isNotEmpty) {
    for (var file in files) {
      final f = fs.currentDirectory.childFile(file);
      allFiles.add(f);
    }
  }
  if (dir.isNotEmpty) {
    final parentDir = fs.currentDirectory.childDirectory(dir);
    if (parentDir.existsSync()) {
      final _lists = parentDir.listSync(followLinks: false);
      for (final f in _lists) {
        if (f is File) {
          allFiles.add(f);
        }
      }
    }
  }

  if (oneFileRename.isNotEmpty) {
    if (allFiles.length == 1) {
      parserJson(allFiles.first, safeToDir,
          rename: oneFileRename, prefix: prefix);
      return;
    }
    printNotice('无法重命名，有${allFiles.length}个文件');
  }

  for (var file in allFiles) {
    parserJson(file, safeToDir, prefix: prefix);
  }
}

void parserJson(File file, Directory safeTo, {String? prefix, String? rename}) {
  if (file.existsSync()) {
    final rawData = file.readAsStringSync();
    try {
      final data = jsonDecode(rawData);
      final jsonFileName = file.basename;
      final name = rename ?? jsonFileName.split('.').first;
      final _prefix = prefix == null ? '' : '${prefix}_';
      final prefixName = '$_prefix$name';

      final pFile = MapIsClass(data, prefixName)..parser();
      final fileName = getDartFileName('$prefixName.dart');
      final safeFile = safeTo.childFile(fileName);
      if (!safeFile.existsSync()) {
        safeFile.createSync(recursive: true);
      }
      safeFile.writeAsStringSync(pFile.toString());
      print('generate file: $jsonFileName to $fileName done.');
    } catch (e) {
      print('解析失败：$e');
    }
  }
}

String getDartFileName(String fileName) {
  return fileName.replaceAllMapped(RegExp('([A-Z])([a-z]*)'), (m) {
    return '_${m[1]?.toLowerCase()}${m[2]}';
  });
}

String getToCamel(String name) {
  return name.replaceAllMapped(RegExp('[_-]([A-Za-z]+)'), (match) {
    final data = match[1]!;
    final first = data.substring(0, 1).toUpperCase();
    final second = data.substring(1);
    return '$first$second';
  });
}

String getDartClassName(String name) {
  final camel = getToCamel(name);
  if (camel.length <= 1) return camel.toUpperCase();
  final first = camel.substring(0, 1).toUpperCase();
  final others = camel.substring(1);
  return '$first$others';
}

String getDartMemberName(String name) {
  final camel = getToCamel(name);
  if (camel.length <= 1) return camel.toLowerCase();
  final first = camel.substring(0, 1).toLowerCase();
  final others = camel.substring(1);
  return '$first$others';
}

class MapIsClass {
  MapIsClass(this.data, this.keyName, {this.parent});
  final Map<String, Object?> data;
  final String keyName;
  final MapIsClass? parent;
  final List<MapIsClass> children = [];

  late String shortName = getDartClassName(keyName);

  String? _className;
  String get getClassName => _className ??=
      parent == null ? shortName : '${parent!.getClassName}$shortName';

  final buffer = StringBuffer();
  void parser() {
    final top = parent == null
        ? 'import \'package:json_annotation/json_annotation.dart\';\n\n'
            'part \'${getDartFileName(keyName)}.g.dart\';\n\n'
            '@JsonSerializable(explicitToJson: true)'
        : '@JsonSerializable(explicitToJson: true)';

    buffer
      ..write(top)
      ..write('\n')
      ..write('class $getClassName {\n')
      ..write('  const $getClassName({');

    final fields = StringBuffer();

    for (final entry in data.entries) {
      final jsonKey = entry.key;
      final key = getDartMemberName(jsonKey);
      final childData = entry.value;
      var valueType = '';
      if (childData is Map<String, Object?>) {
        final childFile = MapIsClass(childData, key, parent: this)..parser();
        children.add(childFile);
        valueType = childFile.getClassName;
      } else if (childData is List) {
        if (childData.isNotEmpty) {
          final listItemData = childData.first;
          if (listItemData is Map<String, Object?>) {
            final childFile = MapIsClass(listItemData, key, parent: this)
              ..parser();
            children.add(childFile);
            valueType = 'List<${childFile.getClassName}?>';
          }
        }
      }
      if (valueType.isEmpty) {
        if (childData == null) {
          printNotice('$getClassName.$key is null');
          valueType = 'Object';
        } else {
          valueType = '${childData.runtimeType}';
        }
      }
      fields
        ..write('  @JsonKey(name: \'$jsonKey\')\n')
        ..write('  final $valueType? $key;\n');
      buffer.write('\n    this.$key,');
    }
    buffer
      ..write('\n  });\n')
      ..write(fields)
      ..write('\n')
      ..write('  factory $getClassName.fromJson(Map<String,dynamic> json) => ')
      ..write('_\$${getClassName}FromJson(json);\n')
      ..write(
          '  Map<String,dynamic> toJson() => _\$${getClassName}ToJson(this);\n')
      ..write('}\n');
  }

  // ignore: annotate_overrides
  String toString() {
    return '${buffer.toString()}\n${children.join('\n')}';
  }
}

void printNotice(String msg) {
  print('!NOTICE: $msg');
}
