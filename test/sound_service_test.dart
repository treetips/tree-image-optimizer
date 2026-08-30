import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tree_image_optimizer/data/services/sound_service.dart';

void main() {
  late Directory tempDir;
  late Directory bundledDir;
  late Directory userDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('sound_test');
    bundledDir = Directory('${tempDir.path}/assets/sounds')
      ..createSync(recursive: true);
    userDir = Directory('${tempDir.path}/user')..createSync(recursive: true);

    // 同梱サウンド
    Directory('${bundledDir.path}/success').createSync();
    Directory('${bundledDir.path}/error').createSync();
    File('${bundledDir.path}/success/b2.mp3').writeAsStringSync('');
    File('${bundledDir.path}/success/a1.wav').writeAsStringSync('');
    File('${bundledDir.path}/error/e1.wav').writeAsStringSync('');

    // ユーザーサウンド
    Directory('${userDir.path}/success').createSync();
    Directory('${userDir.path}/error').createSync();
    File('${userDir.path}/success/user1.flac').writeAsStringSync('');
    File('${userDir.path}/error/user2.mp3').writeAsStringSync('');
    File('${userDir.path}/error/notaudio.txt').writeAsStringSync('');
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  SoundService build() {
    return SoundService(
      bundledBaseDir: bundledDir.path,
      userBaseDir: userDir.path,
    );
  }

  test('成功サウンドは同梱→ユーザーの順でソートして返す', () async {
    final options = await build().listSounds(success: true);

    expect(options.map((o) => o.name).toList(), [
      'a1.wav',
      'b2.mp3',
      'user1.flac',
    ]);
    // 同梱が先、ユーザーが後
    expect(options[0].isBundled, isTrue);
    expect(options[1].isBundled, isTrue);
    expect(options[2].isBundled, isFalse);

    // 同梱のラベルには（サンプル）が付く
    expect(options[0].label, '（サンプル）a1.wav');
    expect(options[2].label, 'user1.flac');
  });

  test('失敗サウンド一覧は音声ファイルのみを返す', () async {
    final options = await build().listSounds(success: false);

    expect(options.map((o) => o.name).toList(), ['e1.wav', 'user2.mp3']);
  });

  test('ユーザーフォルダが無い場合は同梱のみ返す', () async {
    final service = SoundService(
      bundledBaseDir: bundledDir.path,
      userBaseDir: '${tempDir.path}/not_exist',
    );
    final options = await service.listSounds(success: true);

    expect(options.map((o) => o.name).toList(), ['a1.wav', 'b2.mp3']);
  });
}
