import 'dart:convert';

import 'package:chameleonultragui/helpers/general.dart';
import 'package:chameleonultragui/models/card_save.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

class CardFolder {
  String id;
  String name;
  Color color;
  String? parentId;

  /// Last modification time (epoch ms). Null for legacy data.
  int? updatedAt;

  CardFolder({
    String? id,
    required this.name,
    this.color = Colors.deepOrange,
    this.parentId,
    this.updatedAt,
  }) : id = id ?? const Uuid().v4();

  factory CardFolder.fromJson(String source) {
    final data = jsonDecode(source) as Map<String, dynamic>;
    return CardFolder(
      id: data['id'] as String,
      name: data['name'] as String,
      color: data['color'] == null
          ? Colors.deepOrange
          : hexToColor(data['color'] as String),
      parentId: data['parentId'] as String?,
      updatedAt: data['updatedAt'] as int?,
    );
  }

  String toJson() => jsonEncode({
    'id': id,
    'name': name,
    'color': colorToHex(color),
    if (parentId != null) 'parentId': parentId,
    if (updatedAt != null) 'updatedAt': updatedAt,
  });
}

/// Versioned Chameleon Ultra GUI folder interchange format.
class CardFolderBundle {
  final String rootFolderId;
  final List<CardFolder> folders;
  final List<CardSave> cards;

  CardFolderBundle({
    required this.rootFolderId,
    required this.folders,
    required this.cards,
  });

  factory CardFolderBundle.fromJson(String source) {
    final data = jsonDecode(source) as Map<String, dynamic>;
    if (data['format'] != 'chameleon-ultra-gui-folder' ||
        data['version'] != 1) {
      throw const FormatException('Unsupported folder file');
    }
    return CardFolderBundle(
      rootFolderId: data['rootFolderId'] as String,
      folders: (data['folders'] as List<dynamic>)
          .map((item) => CardFolder.fromJson(jsonEncode(item)))
          .toList(),
      cards: (data['cards'] as List<dynamic>)
          .map((item) => CardSave.fromJson(jsonEncode(item)))
          .toList(),
    );
  }

  String toJson() => jsonEncode({
    'format': 'chameleon-ultra-gui-folder',
    'version': 1,
    'rootFolderId': rootFolderId,
    'folders': folders.map((folder) => jsonDecode(folder.toJson())).toList(),
    'cards': cards.map((card) => jsonDecode(card.toJson())).toList(),
  });
}
