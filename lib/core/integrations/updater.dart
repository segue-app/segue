import 'dart:async';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'updates.dart';

import 'package:segue/core/l10n/l10n.dart';

/// What [Updater] is doing.
enum UpdateStage { idle, downloading, installing, done, failed }

/// Installs a new release from inside the app, without visiting GitHub:
///
/// * Android: downloads the APK for this phone and opens the installer.
/// * Windows, Linux: downloads, swaps the app's files after it quits and
///   starts the new version.
/// * macOS: the sandbox doesn't let an app replace itself, so the new
///   Segue.app is unpacked into Downloads and shown in Finder.
class Updater {
  Updater({http.Client? client}) : _http = client ?? http.Client();

  final http.Client _http;

  /// macOS: show the new app in Finder when it's ready (off in tests).
  bool revealInFinder = true;

  /// macOS: where the last update was unpacked.
  String? unpackedPath;
  static const _channel = MethodChannel('fm.segue/update');

  final stage = ValueNotifier<UpdateStage>(UpdateStage.idle);

  /// 0…1 while downloading (null when the size is unknown).
  final progress = ValueNotifier<double?>(null);

  /// What to tell the user about the last step (or error).
  final message = ValueNotifier<String>('');

  bool get busy =>
      stage.value == UpdateStage.downloading ||
      stage.value == UpdateStage.installing;

  /// Whether this platform can update itself from [u].
  static bool canInstall(AppUpdate u) =>
      assetName() != null && u.assets.containsKey(assetName());

  /// The release file this build needs.
  @visibleForTesting
  static String? assetName({String? os, String? dartVersion}) {
    switch (os ?? Platform.operatingSystem) {
      case 'android':
        final v = dartVersion ?? Platform.version;
        if (v.contains('android_arm64')) return 'segue-android-arm64.apk';
        if (v.contains('android_x64')) return 'segue-android-x86_64.apk';
        if (v.contains('android_arm')) return 'segue-android-armv7.apk';
        return 'segue-android-arm64.apk';
      case 'windows':
        return 'segue-windows-x64.zip';
      case 'linux':
        return 'segue-linux-x64.tar.gz';
      case 'macos':
        return 'segue-macos.zip';
    }
    return null;
  }

  Future<void> install(AppUpdate u) async {
    if (busy) return;
    final name = assetName();
    final url = name == null ? null : u.assets[name];
    if (url == null) {
      _fail('Для этой системы нет файла обновления'.tr);
      return;
    }
    try {
      stage.value = UpdateStage.downloading;
      message.value = 'Скачиваем {0}…'.trArgs([u.version]);
      final file = await _download(url, name!);
      stage.value = UpdateStage.installing;
      if (Platform.isAndroid) {
        await _android(file);
      } else if (Platform.isWindows) {
        await _windows(file);
      } else if (Platform.isLinux) {
        await _linux(file);
      } else if (Platform.isMacOS) {
        await _macos(file, u.version);
      }
    } catch (e) {
      debugPrint('update: $e');
      _fail('Не получилось обновиться: {0}'.trArgs([e]));
    }
  }

  void _fail(String why) {
    message.value = why;
    stage.value = UpdateStage.failed;
  }

  Future<File> _download(String url, String name) async {
    final base = Platform.isMacOS
        ? (await getDownloadsDirectory())!
        : Directory('${(await getTemporaryDirectory()).path}/updates');
    await base.create(recursive: true);
    final file = File('${base.path}/$name');
    final res = await _http
        .send(http.Request('GET', Uri.parse(url)))
        .timeout(const Duration(seconds: 30));
    if (res.statusCode != 200) throw StateError('HTTP ${res.statusCode}');
    final total = res.contentLength;
    var got = 0;
    progress.value = total == null ? null : 0;
    final sink = file.openWrite();
    try {
      await for (final chunk in res.stream.timeout(
        const Duration(seconds: 60),
      )) {
        sink.add(chunk);
        got += chunk.length;
        if (total != null && total > 0) progress.value = got / total;
      }
    } finally {
      await sink.close();
    }
    if (total != null && got != total) {
      throw StateError('файл скачался не до конца'.tr);
    }
    return file;
  }

  Future<void> _android(File apk) async {
    final r = await _channel.invokeMethod<String>('install', {
      'path': apk.path,
    });
    if (r == 'permission') {
      // Settings opened: allow "install unknown apps", then tap again.
      message.value =
          'Разреши Segue устанавливать приложения и нажми «Обновить» ещё раз'
              .tr;
      stage.value = UpdateStage.idle;
      return;
    }
    message.value = 'Подтверди установку'.tr;
    stage.value = UpdateStage.done;
  }

  /// Unpacks next to the download, then a script waits for this process
  /// to quit, copies the new files over the app's folder and starts it.
  Future<void> _windows(File zip) async {
    final unpacked = Directory('${zip.parent.path}/new');
    if (unpacked.existsSync()) unpacked.deleteSync(recursive: true);
    await extractFileToDisk(zip.path, unpacked.path);
    final exe = File(Platform.resolvedExecutable);
    final script = File('${zip.parent.path}/update.cmd');
    await script.writeAsString(
      '@echo off\r\n'
      ':wait\r\n'
      'tasklist /FI "PID eq $pid" 2>NUL | find "$pid" >NUL\r\n'
      'if not errorlevel 1 ( timeout /t 1 /nobreak >NUL & goto wait )\r\n'
      'robocopy "${unpacked.path}" "${exe.parent.path}" /E /NFL /NDL /NJH /NJS /R:5 /W:1 >NUL\r\n'
      'start "" "${exe.path}"\r\n',
    );
    await Process.start('cmd', [
      '/c',
      script.path,
    ], mode: ProcessStartMode.detached);
    exit(0);
  }

  Future<void> _linux(File archive) async {
    final unpacked = Directory('${archive.parent.path}/new');
    if (unpacked.existsSync()) unpacked.deleteSync(recursive: true);
    await extractFileToDisk(archive.path, unpacked.path);
    final exe = File(Platform.resolvedExecutable);
    final script = File('${archive.parent.path}/update.sh');
    await script.writeAsString(
      '#!/bin/sh\n'
      'while kill -0 $pid 2>/dev/null; do sleep 0.5; done\n'
      'cp -rf "${unpacked.path}/." "${exe.parent.path}/"\n'
      'chmod +x "${exe.path}"\n'
      'nohup "${exe.path}" >/dev/null 2>&1 &\n',
    );
    await Process.start('sh', [script.path], mode: ProcessStartMode.detached);
    exit(0);
  }

  Future<void> _macos(File zip, String version) async {
    final dir = Directory('${zip.parent.path}/Segue $version');
    if (dir.existsSync()) dir.deleteSync(recursive: true);
    // ditto keeps the bundle's symlinks and signature intact.
    final r = await Process.run('/usr/bin/ditto', [
      '-x',
      '-k',
      zip.path,
      dir.path,
    ]);
    if (r.exitCode != 0) throw StateError('ditto: ${r.stderr}');
    zip.deleteSync();
    unpackedPath = '${dir.path}/Segue.app';
    if (revealInFinder) {
      await Process.run('/usr/bin/open', ['-R', unpackedPath!]);
    }
    message.value = 'Новая версия в «Загрузках»: перетащи Segue в «Программы» с заменой и открой заново'
        .tr;
    stage.value = UpdateStage.done;
  }
}

final updaterProvider = Provider<Updater>((ref) => Updater());
