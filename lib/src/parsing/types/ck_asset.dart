import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';

/// A representation of a CloudKit asset.
class CKAsset
{
  /// The size of the asset.
  int size;

  /// The download URL for the asset.
  String? downloadURL;
  /// The cached version of the asset.
  Uint8List? cachedData;

  CKAsset(this.size, {this.downloadURL});

  /// Download the asset.
  Future<Uint8List?> fetchAsset() async
  {
    if (downloadURL == null) return null;

    var response = await http.get(Uri.parse(downloadURL!));
    if (response.statusCode != 200) return null;

    cachedData = response.bodyBytes;
    return response.bodyBytes;
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
    "downloadURL": downloadURL
  };
}