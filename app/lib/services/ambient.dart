// 환경음(ASMR) 재생(지금 앱 services/ambient.ts). 독서 타이머와 따로 움직인다(소리만 들어도 독서 시간은 쌓이지 않는다).
// 음원은 반복용 WAV(assets/sounds/provenance.json): 빗소리는 Freesound 녹음을 모노 22kHz로 줄이고 이음매를 섞은 것, 벽난로는 사용자가 준 반복 음원(2026-11-23)을 빗소리 크기에 맞춘 것. 실제 재생 여부는 플레이어 상태로만 표시한다.
// 화면을 꺼도 이어 듣고 잠금 화면에 '빗소리 · 책장 한켠'처럼 보인다(just_audio_background)
library;

import 'dart:io';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';

import '../store/settings_store.dart';
import 'error_text.dart';

const _app = MethodChannel('app.covebook/app');

/// 배경 재생(잠금 화면·알림 조작) 준비: 앱을 켤 때 바로 시작해 두고(플레이어를 만들기 전에 끝나야 한다, 패키지 안내대로) 재생 때 기다린다.
/// 2026-11-15 QA: 앱을 뒤로 보내고 화면을 끄면 1분쯤 뒤 소리가 멈췄고 알림이 없었다(화면 앞 서비스 0번, 알림 권한 없음).
/// 첫 재생 때에야 준비하던 것을 켤 때로 옮기고 Android 13+ 알림 권한을 묻는다(실기기 확인 필요)
Future<void>? _bg;
Future<void> initAmbientBackground() => _bg ??= _initBackground().catchError((Object e) {
      _bg = null; // 다음 재생 때 다시 해 본다
      throw e;
    });

Future<void> _initBackground() => () async {
      await JustAudioBackground.init(
        androidNotificationChannelId: 'app.covebook.ambient',
        androidNotificationChannelName: '환경음',
        androidNotificationOngoing: true,
        // 알림 작은 아이콘: 책장 탭 모양 한 색(기본 앱 아이콘은 흰 동그라미로만 보였다)
        androidNotificationIcon: 'drawable/ic_stat_shelf',
      );
      // 통화·다른 앱 소리에 멈췄다 이어지게(음악 재생 세션)
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration.music());
    }();

class SceneInfo {
  const SceneInfo(this.id, this.name, this.sound, this.asset);
  final String id, name, sound, asset;
}

const scenes = [
  SceneInfo('rain', '밤의 창가', '빗소리', 'assets/sounds/rain.wav'),
  SceneInfo('fire', '벽난로', '장작 타는 소리', 'assets/sounds/fire.wav'),
];

/// 장면 이름(밤의 창가는 소리 쪽 이름으로 부른다: 머리줄·분위기 줄·시트가 같은 이름)
String sceneName(String id) => id == 'rain' ? '창가의 빗소리' : scenes.where((s) => s.id == id).firstOrNull?.name ?? '';

/// 실제 출력 음량 = 음소거면 0, 아니면 설정 음량
double outputVolume(double volume, bool muted) => muted ? 0 : volume.clamp(0.0, 1.0);

class Ambient extends ChangeNotifier {
  Ambient._() {
    SettingsStore.instance.addListener(_applyVolume);
  }
  static final instance = Ambient._();

  String? scene;
  bool playing = false;

  /// 앱이 스스로 켜거나 멈추지 않은 재생 바뀜(알림 · 잠금 화면 · 이어폰 단추): true 켬, false 멈춤. 앱 틀이 독서 타이머를 같이 맞춘다
  /// (2026-11-21 사용자 '읽기 멈췄는데 왜 다른 화면에서 타이머는 돌아가?': 알림에서 멈추면 소리만 멈췄다)
  void Function(bool playing)? onExternal;

  /// 이 시각까지 오는 재생 바뀜은 앱이 부른 것(play · pause · hold)
  DateTime _selfUntil = DateTime(0);
  void _self() => _selfUntil = DateTime.now().add(const Duration(seconds: 1));
  String? error;
  AudioPlayer? _player;
  static bool _askedNotify = false;

  void _applyVolume() {
    final s = SettingsStore.instance;
    _player?.setVolume(outputVolume(s.volume, s.muted));
  }

  /// 사용자가 켜 둔 소리(앱이 꺼졌다 켜져도 이어 읽을 때 다시 켠다). 설정에 남긴다
  void _want(bool on) {
    if (SettingsStore.instance.soundOn != on) SettingsStore.instance.set({'soundOn': on});
  }

  /// 소리를 켜 둔 채 앱이 꺼졌으면 다시 켠다(이어 읽기)
  Future<void> resumeIfWanted() async {
    final s = SettingsStore.instance;
    await s.load();
    if (s.soundOn && !playing) await play(s.scene);
  }

  Future<void> play(String id) async {
    // 장면을 바꾸는 동안(옛 소리 멈춤 → 새 플레이어 준비)의 '멈춤'도 앱이 부른 것: 새 플레이어가 처음 '안 나는 중'을 알려
    // 밖에서 멈춘 것으로 읽혀 독서 타이머가 멈췄다(2026-11-27 에뮬: 장면을 넘기면 일시정지). 다 켤 때까지 넉넉히 막고 켠 뒤 1초로 줄인다
    _selfUntil = DateTime.now().add(const Duration(seconds: 10));
    try {
      _want(true);
      await initAmbientBackground();
      // Android 13+: 알림(잠금 화면 조작)을 보이려면 권한이 필요하다. 처음 소리를 켤 때 한 번 묻는다
      if (!_askedNotify && !kIsWeb && Platform.isAndroid) {
        _askedNotify = true;
        _app.invokeMethod<void>('requestNotifications').catchError((_) {});
      }
      if (scene != id || _player == null) {
        // 이전 장면 소리를 먼저 멈춘다(두 소리가 겹치지 않게)
        final old = _player;
        _player = null;
        await old?.stop();
        await old?.dispose();
        final info = scenes.firstWhere((s) => s.id == id);
        final p = AudioPlayer();
        _player = p;
        p.playingStream.listen((v) {
          if (!identical(_player, p) || v == playing) return;
          playing = v;
          notifyListeners();
          if (DateTime.now().isAfter(_selfUntil)) onExternal?.call(v);
        });
        await p.setAudioSource(AudioSource.asset(info.asset, tag: MediaItem(id: info.id, title: info.sound, artist: '책장 한켠')));
        await p.setLoopMode(LoopMode.one);
        scene = id;
        notifyListeners();
      }
      _applyVolume();
      _self();
      _player!.play();
      error = null;
      notifyListeners();
    } catch (e) {
      _self();
      error = '소리를 재생하지 못했어요. ${errorText(e)}';
      playing = false;
      notifyListeners();
    }
  }

  void pause() {
    _want(false);
    _self();
    _player?.pause();
  }

  /// 독서 타이머를 멈출 때: 소리도 멈추되 켜 둔 설정(soundOn)은 그대로 둔다. 이어 읽으면 resumeIfWanted가 다시 켠다
  /// (2026-11-21 사용자 '타이머 멈출 때 소리도 같이 멈추게')
  void hold() {
    _self();
    _player?.pause();
  }

  /// 소리 크기 막대를 끄는 동안: 저장하지 않고 지금 나는 소리에만 바로 반영(손을 떼면 설정에 저장 → _applyVolume)
  void preview(double volume) => _player?.setVolume(outputVolume(volume, false));

  /// 소리 끄고 나가기: 플레이어를 놓아 잠금 화면 표시도 거둔다
  Future<void> stop() async {
    _want(false);
    final p = _player;
    _player = null;
    scene = null;
    playing = false;
    notifyListeners();
    await p?.stop();
    await p?.dispose();
  }
}
