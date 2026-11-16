// 갈피 사진 고르기·자르기(2026-11-16 QA 은서 F14): 사진을 고른 뒤 간직할 부분을 자른다.
// - 자르기 화면 아래 문구(원본·자르기·돌리기·크기)는 앱 자원 res/values*/ucrop_strings.xml로 한국어로 덮는다(전에는 'ORIGINAL'·'Crop').
// - 자르기를 취소하면 이유 'crop'으로 알려 화면이 안내를 띄운다(전에는 아무 말 없이 사진 고르기 전체가 취소됐다).
// 고른 원본은 풀지 않고 자른 그림의 크기만 머리에서 읽는다(services/photos.dart pickPhoto의 crop과 같은 일, 거절·오류 뜻도 같다)
library;

import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';

import '../../services/photos.dart';

/// 자르기를 취소했을 때 안내
const cropCanceledMessage = '자르기를 취소해서 사진을 넣지 않았어요. 다시 찍거나 골라 주세요.';

Future<PhotoResult> pickPagePhoto(String from) async {
  try {
    final x = await ImagePicker().pickImage(source: from == 'camera' ? ImageSource.camera : ImageSource.gallery, imageQuality: 80);
    if (x == null) return const PhotoFail('canceled');
    final c = await ImageCropper().cropImage(
      sourcePath: x.path,
      uiSettings: [
        AndroidUiSettings(toolbarTitle: '사진 자르기', lockAspectRatio: false),
        IOSUiSettings(title: '사진 자르기', doneButtonTitle: '완료', cancelButtonTitle: '취소'),
      ],
    );
    if (c == null) return const PhotoFail('crop');
    final buf = await ui.ImmutableBuffer.fromUint8List(await c.readAsBytes());
    final d = await ui.ImageDescriptor.encoded(buf);
    final w = d.width, h = d.height;
    d.dispose();
    buf.dispose();
    return PhotoOk(Uri.file(c.path).toString(), width: w, height: h);
  } on PlatformException catch (e) {
    if (e.code.contains('denied') || e.code.contains('access')) return const PhotoFail('denied');
    return PhotoFail('error', e.message);
  } catch (e) {
    return PhotoFail('error', '$e');
  }
}
