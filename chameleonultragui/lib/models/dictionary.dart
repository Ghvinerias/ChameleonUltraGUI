import 'dart:convert';
import 'dart:typed_data';
import 'package:chameleonultragui/helpers/general.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

class Dictionary {
  String id;
  String name;
  List<Uint8List> keys;
  Color color;
  int keyLength;
  String? folderId;

  factory Dictionary.fromJson(String json) {
    Map<String, dynamic> data = jsonDecode(json);
    final id = data['id'] as String;
    final name = data['name'] as String;
    final encodedKeys = data['keys'] as List<dynamic>;
    if (data['color'] == null) {
      data['color'] = colorToHex(Colors.deepOrange);
    }

    if (data['keyLength'] == null) {
      // legacy
      data['keyLength'] = 12;
    }

    final keyLength = data['keyLength'] as int;
    final color = hexToColor(data['color']);
    final folderId = data['folderId'] as String?;

    List<Uint8List> keys = [];
    for (var key in encodedKeys) {
      keys.add(Uint8List.fromList(List<int>.from(key)));
    }
    return Dictionary(
        id: id,
        name: name,
        keys: keys,
        color: color,
        keyLength: keyLength,
        folderId: folderId);
  }

  String toJson() {
    return jsonEncode({
      'id': id,
      'name': name,
      'color': colorToHex(color),
      'keys': keys.map((key) => key.toList()).toList(),
      'keyLength': keyLength,
      if (folderId != null) 'folderId': folderId,
    });
  }

  @override
  String toString() {
    String output = "";
    for (var key in keys) {
      output += "${bytesToHex(key).toUpperCase()}\n";
    }
    return output;
  }

  Uint8List toFile() {
    return const Utf8Encoder().convert(toString());
  }

  factory Dictionary.fromString(String input,
      {String name = '', Color color = Colors.deepOrange}) {
    List<Uint8List> keys = [];
    List<int> allowedKeySizes = [
      12, // 6 - Mifare Classic
      8, // 4 - Mifare Ultralight / T55XX
      32, // 16 - Mifare Ultralight C / AES / Mifare Plus
    ];
    int currentKeySize = 0;

    for (var key in input.split("\n")) {
      key = key.trim().replaceAll('#', ' ');

      if (key.contains(' ')) {
        key = key.split(' ')[0];
      }

      if (allowedKeySizes.contains(key.length) &&
          isValidHexString(key) &&
          (currentKeySize == 0 || currentKeySize == key.length)) {
        if (currentKeySize == 0) {
          currentKeySize = key.length;
        }

        keys.add(hexToBytes(key));
      }
    }

    return Dictionary(
        id: const Uuid().v4(),
        name: name,
        keys: keys,
        color: color,
        keyLength: currentKeySize);
  }

  Dictionary(
      {String? id,
      this.name = "",
      this.keys = const [],
      this.color = Colors.deepOrange,
      this.keyLength = 0,
      this.folderId})
      : id = id ?? const Uuid().v4();
}

class DictionaryFolder {
  String id;
  String name;
  Color color;
  String? parentId;

  DictionaryFolder({
    String? id,
    required this.name,
    this.color = Colors.deepOrange,
    this.parentId,
  }) : id = id ?? const Uuid().v4();

  factory DictionaryFolder.fromJson(String source) {
    final data = jsonDecode(source) as Map<String, dynamic>;
    return DictionaryFolder(
      id: data['id'] as String,
      name: data['name'] as String,
      color: data['color'] == null
          ? Colors.deepOrange
          : hexToColor(data['color'] as String),
      parentId: data['parentId'] as String?,
    );
  }

  String toJson() => jsonEncode({
        'id': id,
        'name': name,
        'color': colorToHex(color),
        if (parentId != null) 'parentId': parentId,
      });
}

class DictionaryFolderBundle {
  final String rootFolderId;
  final List<DictionaryFolder> folders;
  final List<Dictionary> dictionaries;

  DictionaryFolderBundle({
    required this.rootFolderId,
    required this.folders,
    required this.dictionaries,
  });

  factory DictionaryFolderBundle.fromJson(String source) {
    final data = jsonDecode(source) as Map<String, dynamic>;
    if (data['format'] != 'chameleon-ultra-gui-dictionary-folder' ||
        data['version'] != 1) {
      throw const FormatException('Unsupported dictionary folder file');
    }
    return DictionaryFolderBundle(
      rootFolderId: data['rootFolderId'] as String,
      folders: (data['folders'] as List<dynamic>)
          .map((item) => DictionaryFolder.fromJson(jsonEncode(item)))
          .toList(),
      dictionaries: (data['dictionaries'] as List<dynamic>)
          .map((item) => Dictionary.fromJson(jsonEncode(item)))
          .toList(),
    );
  }

  String toJson() => jsonEncode({
        'format': 'chameleon-ultra-gui-dictionary-folder',
        'version': 1,
        'rootFolderId': rootFolderId,
        'folders':
            folders.map((folder) => jsonDecode(folder.toJson())).toList(),
        'dictionaries': dictionaries
            .map((dictionary) => jsonDecode(dictionary.toJson()))
            .toList(),
      });
}
