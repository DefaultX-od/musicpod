import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:mpris_service/mpris_service.dart';
import 'package:musicpod/data/audio.dart';
import 'package:palette_generator/palette_generator.dart';
import 'package:safe_change_notifier/safe_change_notifier.dart';

class PlayerModel extends SafeChangeNotifier {
  PlayerModel(MPRIS mpris)
      : _audioPlayer = AudioPlayer(),
        _mediaControlService = mpris;

  final AudioPlayer _audioPlayer;
  final MPRIS _mediaControlService;
  StreamSubscription<PlayerState>? _playerSub;
  StreamSubscription<Duration>? _durationSub;
  StreamSubscription<Duration>? _positionSub;

  List<Audio>? _queue;
  List<Audio>? get queue => _queue;
  set queue(List<Audio>? value) {
    if (value == null) return;
    _queue = value;
    notifyListeners();
  }

  bool? _fullScreen;
  bool? get fullScreen => _fullScreen;
  set fullScreen(bool? value) {
    if (value == null || value == _fullScreen) return;
    _fullScreen = value;
    notifyListeners();
  }

  Audio? _audio;
  Audio? get audio => _audio;
  void setAudio(Audio? value) {
    if (value == null || value == _audio) return;
    _audio = value;

    if (audio!.path != null || audio!.url != null) {
      _mediaControlService.metadata = MPRISMetadata(
        audio!.path != null ? Uri.file(audio!.path!) : Uri.parse(audio!.url!),
        artUrl: _audio!.imageUrl == null
            ? null
            : Uri.parse(
                _audio!.imageUrl!,
              ),
        album: _audio?.metadata?.album,
        albumArtist: [_audio?.metadata?.albumArtist ?? ''],
        artist: [_audio?.metadata?.albumArtist ?? ''],
        discNumber: _audio?.metadata?.discNumber,
        title: _audio?.metadata?.title,
        trackNumber: _audio?.metadata?.trackNumber,
      );
    }

    notifyListeners();
  }

  Audio? _nextAudio;
  Audio? get nextAudio => _nextAudio;
  set nextAudio(Audio? value) {
    if (value == null || value == _nextAudio) return;
    _nextAudio = value;
    notifyListeners();
  }

  bool _isPlaying = false;
  bool get isPlaying => _isPlaying;
  set isPlaying(bool value) {
    if (value == _isPlaying) return;
    _isPlaying = value;
    notifyListeners();
  }

  Duration? _duration;
  Duration? get duration => _duration;
  set duration(Duration? value) {
    if (value == _duration) return;
    _duration = value;
    notifyListeners();
  }

  Duration? _position;
  Duration? get position => _position;
  set position(Duration? value) {
    if (value == _position) return;
    _position = value;
    notifyListeners();
  }

  bool _repeatSingle = false;
  bool get repeatSingle => _repeatSingle;
  set repeatSingle(bool value) {
    if (value == _repeatSingle) return;
    _repeatSingle = value;
    notifyListeners();
  }

  Future<void> play() async {
    if (audio!.path != null) {
      await _audioPlayer.play(DeviceFileSource(audio!.path!));
    } else if (audio!.url != null) {
      await _audioPlayer.play(UrlSource(audio!.url!));
    }
    loadColor();
  }

  Future<void> stop() async {
    await _audioPlayer.release();
    await _audioPlayer.stop();
  }

  Future<void> pause() async {
    if (audio == null) return;
    await _audioPlayer.pause();
  }

  Future<void> seek() async {
    if (position == null) return;
    await _audioPlayer.seek(position!);
  }

  Future<void> resume() async {
    if (audio == null) return;
    await _audioPlayer.resume();
  }

  Future<void> init() async {
    _mediaControlService.setEventHandler(
      MPRISEventHandler(
        playPause: () async {
          isPlaying ? pause() : play();
          _mediaControlService.playbackStatus = (isPlaying
              ? MPRISPlaybackStatus.paused
              : MPRISPlaybackStatus.playing);
        },
        play: () async {
          play();
        },
        pause: () async {
          pause();
          _mediaControlService.playbackStatus = MPRISPlaybackStatus.paused;
        },
        next: () async {
          playNext();
        },
        previous: () async {
          playPrevious();
        },
      ),
    );

    _playerSub = _audioPlayer.onPlayerStateChanged.listen((playerState) {
      isPlaying = playerState == PlayerState.playing;
      _mediaControlService.playbackStatus =
          isPlaying ? MPRISPlaybackStatus.playing : MPRISPlaybackStatus.paused;
    });
    _audioPlayer.onDurationChanged.listen((newDuration) {
      duration = newDuration;
    });
    _audioPlayer.onPositionChanged.listen((newPosition) {
      position = newPosition;
      estimateNext();
    });

    _audioPlayer.onPlayerComplete.listen((_) async {
      if (_repeatSingle == true) {
        _audioPlayer.seek(Duration.zero);
        await _audioPlayer.resume();
      } else {
        playNext();
      }
    });
    notifyListeners();
  }

  Future<void> playNext() async {
    estimateNext();
    if (nextAudio == null) return;
    setAudio(nextAudio);

    await _audioPlayer.release();
    await _audioPlayer.stop();
    await play();
  }

  void estimateNext() {
    if (queue?.isNotEmpty == true && audio != null && queue!.contains(audio)) {
      final currentIndex = queue!.indexOf(audio!);

      if (currentIndex == queue!.length - 1) {
        nextAudio = queue!.elementAt(0);
      } else {
        nextAudio = queue?.elementAt(currentIndex + 1);
      }
    }
  }

  Future<void> playPrevious() async {
    if (queue?.isNotEmpty == true && audio != null && queue!.contains(audio)) {
      final currentIndex = queue!.indexOf(audio!);

      if (currentIndex == 0) {
        return;
      }

      nextAudio = queue?.elementAt(currentIndex - 1);

      if (nextAudio == null) return;
      setAudio(nextAudio);

      await _audioPlayer.release();
      await _audioPlayer.stop();
      await play();
    }
  }

  Future<void> startPlaylist(Set<Audio> audios) async {
    queue = audios.toList();
    setAudio(audios.first);
    await stop();
    await play();
  }

  Color? _color;
  void resetColor() => _color = null;
  Color? get color => _color;
  Color? get surfaceTintColor => _color?.withOpacity(0.1);

  Future<void> loadColor() async {
    if (audio?.audioType == AudioType.local) {
      if (audio == null ||
          audio?.path == null ||
          audio!.metadata == null ||
          audio!.metadata!.picture == null) return;

      final image = MemoryImage(
        audio!.metadata!.picture!.data,
      );
      final generator = await PaletteGenerator.fromImageProvider(image);
      _color = generator.dominantColor?.color;
      notifyListeners();
    } else if (audio?.audioType == AudioType.podcast) {
      if (audio == null || audio?.imageUrl == null) return;

      final image = NetworkImage(
        audio!.imageUrl!,
      );
      final generator = await PaletteGenerator.fromImageProvider(image);
      _color = generator.dominantColor?.color;
      notifyListeners();
    }
  }

  bool _isUpNextExpanded = false;
  bool get isUpNextExpanded => _isUpNextExpanded;
  set isUpNextExpanded(bool value) {
    if (value == _isUpNextExpanded) return;
    _isUpNextExpanded = value;
    notifyListeners();
  }

  @override
  void dispose() {
    _mediaControlService.dispose();
    _playerSub?.cancel();
    _positionSub?.cancel();
    _durationSub?.cancel();
    _audioPlayer.dispose();
    super.dispose();
  }
}
