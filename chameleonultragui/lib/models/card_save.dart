import 'dart:convert';
import 'dart:typed_data';
import 'package:chameleonultragui/helpers/definitions.dart';
import 'package:chameleonultragui/helpers/general.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

class CardSave {
  String id;
  String uid;
  int sak;
  Uint8List atqa;
  Uint8List ats;
  String name;
  TagType tag;
  List<Uint8List> data;
  CardSaveExtra extraData;
  Color color;
  String? folderId;

  factory CardSave.fromJson(String json) {
    Map<String, dynamic> data = jsonDecode(json);
    final id = data['id'] as String;
    final uid = data['uid'] as String;
    final sak = data['sak'] as int;
    final atqa = List<int>.from(data['atqa'] as List<dynamic>);
    final ats = List<int>.from((data['ats'] ?? []) as List<dynamic>);
    final name = data['name'] as String;
    final tag = getTagTypeByValue(data['tag']);
    final extraData = CardSaveExtra.import(data['extra'] ?? {});
    final color =
        data['color'] == null ? Colors.deepOrange : hexToColor(data['color']);
    final folderId = data['folderId'] as String?;
    List<Uint8List> tagData = (data['data'] as List<dynamic>)
        .map((e) => Uint8List.fromList(List<int>.from(e)))
        .toList();

    return CardSave(
        id: id,
        uid: uid,
        sak: sak,
        name: name,
        tag: tag,
        data: tagData,
        color: color,
        folderId: folderId,
        extraData: extraData,
        ats: Uint8List.fromList(ats),
        atqa: Uint8List.fromList(atqa));
  }

  String toJson() {
    return jsonEncode({
      'id': id,
      'uid': uid,
      'sak': sak,
      'atqa': atqa.toList(),
      'ats': ats.toList(),
      'name': name,
      'tag': tag.value,
      'color': colorToHex(color),
      'data': data.map((data) => data.toList()).toList(),
      'extra': extraData.export(),
      if (folderId != null) 'folderId': folderId,
    });
  }

  CardSave({
    String? id,
    required this.uid,
    required this.name,
    required this.tag,
    int? sak,
    Uint8List? atqa,
    Uint8List? ats,
    CardSaveExtra? extraData,
    this.color = Colors.deepOrange,
    this.folderId,
    this.data = const [],
  })  : id = id ?? const Uuid().v4(),
        sak = sak ?? 0,
        atqa = atqa ?? Uint8List(0),
        ats = ats ?? Uint8List(0),
        extraData = extraData ?? CardSaveExtra();
}

class CardSaveExtra {
  Uint8List ultralightSignature;
  Uint8List ultralightVersion;
  List<int> ultralightCounters;

  factory CardSaveExtra.import(Map<String, dynamic> data) {
    List<int> readBytes(Map<String, dynamic> data, String key) {
      return List<int>.from(
          data[key] != null ? data[key] as List<dynamic> : []);
    }

    final ultralightSignature = readBytes(data, 'ultralightSignature');
    final ultralightVersion = readBytes(data, 'ultralightVersion');
    final ultralightCounters = data['ultralightCounters'] != null
        ? List<int>.from(data['ultralightCounters'] as List<dynamic>)
        : <int>[];

    return CardSaveExtra(
        ultralightSignature: Uint8List.fromList(ultralightSignature),
        ultralightVersion: Uint8List.fromList(ultralightVersion),
        ultralightCounters: ultralightCounters);
  }

  Map<String, dynamic> export() {
    Map<String, dynamic> json = {};

    if (ultralightSignature.isNotEmpty) {
      json['ultralightSignature'] = ultralightSignature;
    }

    if (ultralightVersion.isNotEmpty) {
      json['ultralightVersion'] = ultralightVersion;
    }

    if (ultralightCounters.isNotEmpty) {
      json['ultralightCounters'] = ultralightCounters;
    }

    return json;
  }

  CardSaveExtra(
      {Uint8List? ultralightSignature,
      Uint8List? ultralightVersion,
      List<int>? ultralightCounters})
      : ultralightSignature = ultralightSignature ?? Uint8List(0),
        ultralightVersion = ultralightVersion ?? Uint8List(0),
        ultralightCounters = ultralightCounters ?? <int>[];
}
