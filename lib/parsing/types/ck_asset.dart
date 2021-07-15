import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';

class CKAsset
{
  String fileChecksum;
  String referenceChecksum;
  String wrappingKey;
  int size;

  String? downloadURL;
  Uint8List? cachedData;

  CKAsset(this.fileChecksum, this.referenceChecksum, this.wrappingKey, this.size, {this.downloadURL});

  Future<Uint8List?> fetchAsset() async
  {
    if (downloadURL == null) return null;

    var response = await http.get(Uri.parse(downloadURL!));
    if (response.statusCode != 200) return null;

    cachedData = response.bodyBytes;
    return response.bodyBytes;
  }

  MemoryImage? getAsImage()
  {
    if (cachedData == null) return null;

    return MemoryImage(cachedData!);
  }
}