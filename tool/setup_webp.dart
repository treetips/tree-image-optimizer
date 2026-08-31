// ignore_for_file: avoid_print
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:http/http.dart' as http;

/// Google Storage から libwebp を取得して tools/libwebp に配置するスクリプト.
///
/// 実行:
///   dart run tool/setup_webp.dart
///
/// AppConstants.webpVersion と同期させること。
const String webpVersion = '1.6.0';

const String baseUrl =
    'https://storage.googleapis.com/downloads.webmproject.org/releases/webp';

const Map<String, String> archives = {
  'macos-arm64': 'libwebp-$webpVersion-mac-arm64.tar.gz',
  'macos-x86-64': 'libwebp-$webpVersion-mac-x86-64.tar.gz',
  'linux-x86-64': 'libwebp-$webpVersion-linux-x86-64.tar.gz',
  'linux-aarch64': 'libwebp-$webpVersion-linux-aarch64.tar.gz',
  'windows-x64': 'libwebp-$webpVersion-windows-x64.zip',
};

/// 配置先マッピング: archiveKey -> `tools/libwebp/bin/<os>/`
const Map<String, String> destMap = {
  'macos-arm64': 'tools/libwebp/bin/macos',
  'macos-x86-64': 'tools/libwebp/bin/macos', // 上書き注意: 本番では両archを個別に保持したい場合は分離する
  'linux-x86-64': 'tools/libwebp/bin/linux',
  'linux-aarch64': 'tools/libwebp/bin/linux',
  'windows-x64': 'tools/libwebp/bin/windows',
};

Future<void> main(List<String> args) async {
  final onlyCurrent = args.contains('--current-only');
  final currentOs = _currentOsName();
  final currentArch = await _currentArch();
  print('webpVersion=$webpVersion os=$currentOs arch=$currentArch');

  final targets = <String, String>{};
  if (onlyCurrent) {
    final key = _keyForCurrent(currentOs, currentArch);
    if (key != null) {
      targets[key] = archives[key]!;
      print('current-only mode: $key -> ${archives[key]}');
    } else {
      print('Unsupported current platform: $currentOs $currentArch');
      exit(1);
    }
  } else {
    targets.addAll(archives);
    print('Downloading all archives: ${targets.keys.join(", ")}');
  }

  final tmpDir = Directory.systemTemp.createTempSync('setup_webp');
  print('tmpDir=${tmpDir.path}');

  for (final entry in targets.entries) {
    final key = entry.key;
    final archiveName = entry.value;
    final url = '$baseUrl/$archiveName';
    final destDir = destMap[key]!;
    print('\n=== $key ===');
    print('url=$url');
    print('dest=$destDir');

    final archivePath = '${tmpDir.path}/$archiveName';
    await _download(url, archivePath);

    final isZip = archiveName.endsWith('.zip');
    final executableName = key.startsWith('windows') ? 'cwebp.exe' : 'cwebp';
    final targetPath = '$destDir/$executableName';

    await Directory(destDir).create(recursive: true);

    if (isZip) {
      final bytes = await File(archivePath).readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);
      bool found = false;
      for (final file in archive) {
        if (file.isFile && file.name.endsWith('/bin/$executableName')) {
          final target = File(targetPath);
          // macos-arm64 と macos-x86-64 が同じ dest に上書きされるのを避けるため、
          // --current-only 以外で macos-x86-64 はスキップするか、別名で保存する
          // ここでは current-only でない場合、最初にダウンロードした macos-arm64 を優先し、x86-64 はスキップする
          if (key == 'macos-x86-64' && !onlyCurrent) {
            print(
              'skip $key (already populated macos from arm64) -> $targetPath',
            );
            found = true;
            break;
          }
          await target.writeAsBytes(file.content as List<int>);
          print('extracted $targetPath (${file.size} bytes)');
          found = true;
          break;
        }
      }
      if (!found) {
        print('cwebp not found in $archiveName');
        // list files for debug
        for (final f in archive) {
          if (f.name.contains('cwebp')) print('  candidate: ${f.name}');
        }
        exit(1);
      }
    } else {
      final bytes = await File(archivePath).readAsBytes();
      final gzBytes = GZipDecoder().decodeBytes(bytes);
      final archive = TarDecoder().decodeBytes(gzBytes);
      bool found = false;
      for (final file in archive) {
        if (file.isFile && file.name.endsWith('/bin/$executableName')) {
          if (key == 'macos-x86-64' && !onlyCurrent) {
            print('skip $key (already populated macos from arm64)');
            found = true;
            break;
          }
          // linux-aarch64 も linux-x86-64 と同じ dest なので同様にスキップ
          if (key == 'linux-aarch64' && !onlyCurrent) {
            print('skip $key (already populated linux from x86-64)');
            found = true;
            break;
          }
          final target = File(targetPath);
          await target.writeAsBytes(file.content as List<int>);
          print('extracted $targetPath (${file.size} bytes)');
          found = true;
          break;
        }
      }
      if (!found) {
        print('cwebp not found in $archiveName');
        exit(1);
      }
    }

    if (!key.startsWith('windows')) {
      final result = await Process.run('chmod', ['+x', targetPath]);
      if (result.exitCode != 0) {
        print('chmod failed: ${result.stderr}');
      } else {
        print('chmod +x $targetPath');
      }
    }

    // Verify only if current OS matches target
    final shouldVerify =
        (key.startsWith('macos') && currentOs == 'macos') ||
        (key.startsWith('linux') && currentOs == 'linux') ||
        (key.startsWith('windows') && currentOs == 'windows');
    if (shouldVerify) {
      final verify = await Process.run(targetPath, ['-version']);
      print(
        'verify $targetPath -version: exit=${verify.exitCode} stdout=${verify.stdout} stderr=${verify.stderr}',
      );
    } else {
      print('skip verify for $key (currentOs=$currentOs)');
    }
  }

  print('\nDone. Cleaning tmpDir');
  try {
    tmpDir.deleteSync(recursive: true);
  } catch (_) {}

  print('\nInstalled:');
  for (final dest in destMap.values.toSet()) {
    final exe = dest.contains('windows') ? 'cwebp.exe' : 'cwebp';
    final f = File('$dest/$exe');
    print(
      '  $dest/$exe exists=${f.existsSync()} size=${f.existsSync() ? f.lengthSync() : 0}',
    );
  }
}

String _currentOsName() {
  if (Platform.isWindows) return 'windows';
  if (Platform.isLinux) return 'linux';
  return 'macos';
}

Future<String> _currentArch() async {
  try {
    final result = await Process.run('uname', ['-m']);
    return (result.stdout as String).trim().toLowerCase();
  } catch (_) {
    return 'unknown';
  }
}

String? _keyForCurrent(String os, String arch) {
  final a = arch.toLowerCase();
  if (os == 'macos') {
    if (a.contains('arm64') || a.contains('aarch64')) return 'macos-arm64';
    if (a.contains('x86_64')) return 'macos-x86-64';
    return 'macos-arm64'; // default to arm64 on Apple Silicon
  }
  if (os == 'linux') {
    if (a.contains('aarch64') || a.contains('arm64')) return 'linux-aarch64';
    return 'linux-x86-64';
  }
  if (os == 'windows') return 'windows-x64';
  return null;
}

Future<void> _download(String url, String destPath) async {
  print('downloading $url -> $destPath');
  final client = http.Client();
  final request = http.Request('GET', Uri.parse(url));
  final response = await client.send(request);
  if (response.statusCode != 200) {
    throw Exception('Failed to download $url: ${response.statusCode}');
  }
  final file = File(destPath);
  await file.parent.create(recursive: true);
  final sink = file.openWrite();
  var received = 0;
  final total = response.contentLength ?? 0;
  await for (final chunk in response.stream) {
    received += chunk.length;
    sink.add(chunk);
    if (total > 0) {
      final pct = (received / total * 100).toStringAsFixed(1);
      stdout.write('\r  $received/$total bytes ($pct%)');
    } else {
      stdout.write('\r  $received bytes');
    }
  }
  await sink.close();
  client.close();
  print('\n  downloaded $received bytes');
}
