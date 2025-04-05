import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:audio_session/audio_session.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:audio_service/audio_service.dart';
import 'audio_handler.dart';
import 'dart:convert';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final audioPlayer = await setupAudioPlayer();
  await AudioService.init(
    builder: () => AudioPlayerHandler(audioPlayer),
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.yourcompany.yourapp.channel.audio',
      androidNotificationChannelName: 'Music playback',
      androidNotificationOngoing: true,
      androidStopForegroundOnPause: true,
    ),
  );
  runApp(const MyApp());
}

Future<AudioPlayer> setupAudioPlayer() async {
  final player = AudioPlayer();
  return player;
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Music App',
      theme: ThemeData.dark().copyWith(
        colorScheme: const ColorScheme.dark(
          primary: Colors.greenAccent,
          secondary: Colors.green,
          background: Colors.black,
          surface: Color(0xFF121212),
        ),
        textTheme: const TextTheme(
          titleLarge: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          bodyLarge: TextStyle(fontSize: 18),
        ),
        sliderTheme: SliderThemeData(
          activeTrackColor: const Color.fromARGB(255, 0, 209, 63),
          inactiveTrackColor: Colors.grey[800],
          thumbColor: const Color.fromARGB(255, 0, 209, 17),
          overlayColor: const Color.fromARGB(255, 0, 231, 0).withOpacity(0.2),
        ),
      ),
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
  final AudioPlayer AudioService = AudioPlayer();
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
    
    AudioService.currentIndexStream.listen((index) {
      setState(() {
        _currentIndex = index;
      });
    });

    AudioService.playerStateStream.listen((playerState) {
      setState(() {
        _isPlaying = playerState.playing;
      });
    });

    AudioService.shuffleModeEnabledStream.listen((enabled) {
      setState(() {
        _isShuffled = enabled;
      });
    });
    
    AudioService.loopModeStream.listen((mode) {
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
    await session.configure(AudioSessionConfiguration(
      avAudioSessionCategory: AVAudioSessionCategory.playback,
      avAudioSessionCategoryOptions: AVAudioSessionCategoryOptions.mixWithOthers,
      avAudioSessionMode: AVAudioSessionMode.defaultMode,
      avAudioSessionRouteSharingPolicy: AVAudioSessionRouteSharingPolicy.defaultPolicy,
      avAudioSessionSetActiveOptions: AVAudioSessionSetActiveOptions.none,
      androidAudioAttributes: const AndroidAudioAttributes(
        contentType: AndroidAudioContentType.music,
        flags: AndroidAudioFlags.none,
        usage: AndroidAudioUsage.media,
      ),
      androidAudioFocusGainType: AndroidAudioFocusGainType.gain,
      androidWillPauseWhenDucked: true,
    ));
  }

  Future<void> _setupPlaylist() async {
    await AudioService.setShuffleModeEnabled(true);  // Add this
    await AudioService.setLoopMode(LoopMode.all);    // Changed from LoopMode.off
    await AudioService.setAudioSource(
      ConcatenatingAudioSource(
        children: _songs.map((song) => AudioSource.asset(song)).toList(),
      ),
    );
  }

  @override
  void dispose() {
    AudioService.dispose();
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
        backgroundColor: Colors.black,
        elevation: 0,
        title: _currentIndex != null
            ? Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween, // Add this
                children: [
                  Expanded(
                    child: Text(
                      _getSongTitle(_songs[_currentIndex!]),
                      style: Theme.of(context).textTheme.titleLarge!.copyWith(
                            color: Colors.greenAccent,
                          ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.greenAccent.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.remove, size: 20),
                          color: Colors.greenAccent,
                          onPressed: () {
                            final songPath = _songs[_currentIndex!];
                            final currentScore = _songScores[songPath] ?? 0;
                            _updateScore(songPath, currentScore - 1);
                          },
                        ),
                        Text('${_songScores[_songs[_currentIndex!]] ?? 0}',
                          style: const TextStyle(fontSize: 20, color: Colors.white)),
                        IconButton(
                          icon: const Icon(Icons.add, size: 20),
                          color: Colors.greenAccent,
                          onPressed: () {
                            final songPath = _songs[_currentIndex!];
                            final currentScore = _songScores[songPath] ?? 0;
                            _updateScore(songPath, currentScore + 1);
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              )
            : const Text('Music Player', style: TextStyle(fontSize: 25)),
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
                stream: AudioService.positionStream,
                builder: (context, snapshot) {
                  _position = snapshot.data ?? Duration.zero;
                  return StreamBuilder<Duration?>(
                    stream: AudioService.durationStream,
                    builder: (context, snapshot) {
                      _duration = snapshot.data ?? Duration.zero;
                      return Slider(
                        min: 0,
                        max: _duration.inSeconds.toDouble(),
                        value: _position.inSeconds.toDouble(),
                        onChanged: (value) async {
                          await AudioService.seek(Duration(seconds: value.toInt()));
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
                    color: _isLooped ? const Color.fromARGB(255, 0, 255, 8) : null,
                    onPressed: () async {
                      final newMode = _isLooped ? LoopMode.off : LoopMode.all;
                      await AudioService.setLoopMode(newMode);
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.skip_previous, size: 40),
                    onPressed: () => AudioService.seekToPrevious(),
                  ),
                  IconButton(
                    icon: Icon(_isPlaying ? Icons.pause : Icons.play_arrow, size: 50),
                    onPressed: () async {
                      if (_isPlaying) {
                        await AudioService.pause();
                      } else {
                        await AudioService.play();
                      }
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.skip_next, size: 40),
                    onPressed: () => AudioService.seekToNext(),
                  ),
                  IconButton(
                    icon: const Icon(Icons.shuffle),
                    color: _isShuffled ? const Color.fromARGB(255, 0, 255, 8) : null,
                    onPressed: () async {
                      await AudioService.setShuffleModeEnabled(!_isShuffled);
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
                      tileColor: _currentIndex == index 
                          ? Colors.greenAccent.withOpacity(0.1)
                          : null,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(15),
                      ),
                      title: Row(
                        children: [
                          Expanded(
                            child: Text(
                              _getSongTitle(songPath),
                              style: TextStyle(
                                color: _currentIndex == index 
                                    ? Colors.greenAccent 
                                    : Colors.white,
                                fontWeight: _currentIndex == index 
                                    ? FontWeight.bold 
                                    : FontWeight.normal,
                              ),
                            ),
                          ),
                          Container(
                            decoration: BoxDecoration(
                              color: Colors.greenAccent.withOpacity(0),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Row(
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.remove, size: 18),
                                  color: Colors.greenAccent,
                                  onPressed: () { 
                                    _updateScore(songPath, score - 1);
                                  },
                                ),
                                Text(score.toString(),
                                    style: const TextStyle(color: Colors.white)),
                                IconButton(
                                  icon: const Icon(Icons.add, size: 18),
                                  color: Colors.greenAccent,
                                  onPressed: () { 
                                    _updateScore(songPath, score + 1);
                                  },
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      onTap: () async {
                        if (_isPlaying) {
                          await AudioService.stop();
                        }
                        await AudioService.seek(Duration.zero, index: index);
                        await AudioService.play();
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
