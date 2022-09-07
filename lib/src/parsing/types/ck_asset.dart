import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';

import '/src/database/ck_local_database_manager.dart';
import '/src/parsing/ck_field_structure.dart';

/// A representation of a CloudKit asset.
class CKAsset
{
  /// The size of the asset.
  int size;
  /// The file checksum of the asset.
  String fileChecksum;

  /// The download URL for the asset.
  String? downloadURL;
  /// The cached version of the asset.
  Uint8List? cachedData;

  /// The field path to the asset.
  CKFieldPath? fieldPath;

  CKAsset(this.size, this.fileChecksum, {this.downloadURL, this.cachedData, this.fieldPath});

  CKAsset.fromJSON(Map<String, dynamic> json, {this.fieldPath}) :
        size = json["size"],
        fileChecksum = json["fileChecksum"],
        downloadURL = json["downloadURL"],
        cachedData = json["cachedData"] != null ? Uint8List.fromList(json["cachedData"].cast<int>()) : null;

  /// Fetch the asset.
  Future<Uint8List?> fetchAsset({CKLocalDatabaseManager? manager}) async
  {
    if (cachedData != null) return cachedData;

    var managerToUse = manager ?? CKLocalDatabaseManager.shared;
    cachedData = await managerToUse.queryAssetCache(fileChecksum);
    if (cachedData != null) return cachedData;

    if (downloadURL == null) return null;

    var response = await http.get(Uri.parse(downloadURL!));
    if (response.statusCode != 200) return null;

    cachedData = response.bodyBytes;
    if (cachedData != null && fieldPath != null) await managerToUse.insertAssetCache(fieldPath!, fileChecksum, cachedData!);

    return cachedData;
  }

  /// Return the cached version of the asset as an image, if possible.
  MemoryImage? getAsImage()
  {
    if (cachedData == null) return null;

    return MemoryImage(cachedData!);
  }

  /// Convert the asset to JSON
  Map<String, dynamic> toJSON() => {
    "size": size,
    "fileChecksum": fileChecksum,
    "downloadURL": downloadURL
  };
}