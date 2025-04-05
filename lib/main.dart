import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:audio_session/audio_session.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Music App',
      theme: ThemeData.dark(),
      home: const MusicPlayerScreen(),
    );
  }
}

class MusicPlayerScreen extends StatefulWidget {
  const MusicPlayerScreen({Key? key}) : super(key: key);

  @override
  State<MusicPlayerScreen> createState() => MusicPlayerScreenState();
}

class MusicPlayerScreenState extends State<MusicPlayerScreen> {
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isPlaying = false;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  late Future<List<String>> _songsFuture;
  List<String> _songs = [];
  int? _currentIndex;
  bool _isShuffled = true;
  bool _isLooped = true;
  late SharedPreferences _prefs;
  Map<String, int> _songScores = {};

  @override
  void initState() {
    super.initState();
    _isShuffled = true;  // Add this
    _isLooped = true;     // Add this
    _songsFuture = _loadSongs();
    _initAudioSession();
    
    _audioPlayer.currentIndexStream.listen((index) {
      setState(() {
        _currentIndex = index;
      });
    });

    _audioPlayer.playerStateStream.listen((playerState) {
      setState(() {
        _isPlaying = playerState.playing;
      });
    });

    _audioPlayer.shuffleModeEnabledStream.listen((enabled) {
      setState(() {
        _isShuffled = enabled;
      });
    });
    
    _audioPlayer.loopModeStream.listen((mode) {
      setState(() {
        _isLooped = mode == LoopMode.all;
      });
    });
  }

  Future<List<String>> _loadSongs() async {
    final manifestContent = await rootBundle.loadString('AssetManifest.json');
    final Map<String, dynamic> manifest = json.decode(manifestContent);
    
    _songs = manifest.keys
        .where((path) => path.endsWith('.mp3') && path.startsWith('assets/'))
        .toList();

    if (_songs.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _setupPlaylist());
    }

    await _loadScores();
    return _songs;
  }

  Future<void> _loadScores() async {
    _prefs = await SharedPreferences.getInstance();
    String? scoresJson = _prefs.getString('songScores');
    if (scoresJson != null) {
      setState(() {
        _songScores = Map<String, int>.from(json.decode(scoresJson));
      });
    }
  }

  Future<void> _saveScores() async {
    String scoresJson = json.encode(_songScores);
    await _prefs.setString('songScores', scoresJson);
  }

  void _updateScore(String songPath, int newScore) {
    newScore = newScore.clamp(0, 9);
    setState(() {
      _songScores[songPath] = newScore;
    });
    _saveScores();
  }

  Future<void> _initAudioSession() async {
    final session = await AudioSession.instance;
    await session.configure(AudioSessionConfiguration.music());
  }

  Future<void> _setupPlaylist() async {
    await _audioPlayer.setShuffleModeEnabled(true);  // Add this
    await _audioPlayer.setLoopMode(LoopMode.all);    // Changed from LoopMode.off
    await _audioPlayer.setAudioSource(
      ConcatenatingAudioSource(
        children: _songs.map((song) => AudioSource.asset(song)).toList(),
      ),
    );
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    super.dispose();
  }

  String _getSongTitle(String filePath) {
    final fileName = filePath.split('/').last.replaceAll('.mp3', '');
    return fileName
        .split('_')
        .map((word) => word[0].toUpperCase() + word.substring(1))
        .join(' ');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _currentIndex != null 
              ? _getSongTitle(_songs[_currentIndex!])
              : 'Music Player',
          style: const TextStyle(fontSize: 25),
        ),
      ),
      body: FutureBuilder<List<String>>(
        future: _songsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          
          if (snapshot.hasError || _songs.isEmpty) {
            return const Center(child: Text('No songs found in assets folder'));
          }

          return Column(
            children: [
              StreamBuilder<Duration?>(
                stream: _audioPlayer.positionStream,
                builder: (context, snapshot) {
                  _position = snapshot.data ?? Duration.zero;
                  return StreamBuilder<Duration?>(
                    stream: _audioPlayer.durationStream,
                    builder: (context, snapshot) {
                      _duration = snapshot.data ?? Duration.zero;
                      return Slider(
                        min: 0,
                        max: _duration.inSeconds.toDouble(),
                        value: _position.inSeconds.toDouble(),
                        onChanged: (value) async {
                          await _audioPlayer.seek(Duration(seconds: value.toInt()));
                        },
                      );
                    },
                  );
                },
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    icon: const Icon(Icons.repeat),
                    color: _isLooped ? Colors.green : null,
                    onPressed: () async {
                      final newMode = _isLooped ? LoopMode.off : LoopMode.all;
                      await _audioPlayer.setLoopMode(newMode);
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.skip_previous, size: 40),
                    onPressed: () => _audioPlayer.seekToPrevious(),
                  ),
                  IconButton(
                    icon: Icon(_isPlaying ? Icons.pause : Icons.play_arrow, size: 50),
                    onPressed: () async {
                      if (_isPlaying) {
                        await _audioPlayer.pause();
                      } else {
                        await _audioPlayer.play();
                      }
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.skip_next, size: 40),
                    onPressed: () => _audioPlayer.seekToNext(),
                  ),
                  IconButton(
                    icon: const Icon(Icons.shuffle),
                    color: _isShuffled ? Colors.green : null,
                    onPressed: () async {
                      await _audioPlayer.setShuffleModeEnabled(!_isShuffled);
                    },
                  ),
                ],
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: _songs.length,
                  itemBuilder: (context, index) {
                    String songPath = _songs[index];
                    int score = _songScores[songPath] ?? 0;
                    return ListTile(
                      title: Row(
                        children: [
                          Expanded(
                            child: Text(_getSongTitle(songPath)),
                          ),
                          IconButton(
                            icon: const Text('-'),
                            onPressed: () {
                              _updateScore(songPath, score - 1);
                            },
                          ),
                          Text(score.toString()),
                          IconButton(
                            icon: const Text('+'),
                            onPressed: () {
                              _updateScore(songPath, score + 1);
                            },
                          ),
                        ],
                      ),
                      onTap: () async {
                        if (_isPlaying) {
                          await _audioPlayer.stop();
                        }
                        await _audioPlayer.seek(Duration.zero, index: index);
                        await _audioPlayer.play();
                      },
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
