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
      // Update the ThemeData in MyApp widget
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

  Future<void> _sortSongsByScore() async {
    String? currentSongPath;
    bool wasPlaying = _isPlaying;
    if (_currentIndex != null && _currentIndex! < _songs.length) {
      currentSongPath = _songs[_currentIndex!];
    }

    await _audioPlayer.pause();

    List<String> sortedSongs = List.from(_songs);
    sortedSongs.sort((a, b) {
      int scoreA = _songScores[a] ?? 0;
      int scoreB = _songScores[b] ?? 0;
      return scoreB.compareTo(scoreA); // Descending order
    });

    setState(() {
      _songs = sortedSongs;
    });

    await _audioPlayer.setShuffleModeEnabled(false);
    await _audioPlayer.setAudioSource(
      ConcatenatingAudioSource(
        children: _songs.map((song) => AudioSource.asset(song)).toList(),
      ),
    );

    if (currentSongPath != null) {
      int newIndex = _songs.indexOf(currentSongPath);
      if (newIndex != -1) {
        await _audioPlayer.seek(Duration.zero, index: newIndex);
        if (wasPlaying) {
          await _audioPlayer.play();
        }
      }
    }

    setState(() {});
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
        backgroundColor: Colors.black,
        elevation: 0,
        title: _currentIndex != null
            ? Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      _getSongTitle(_songs[_currentIndex!]),
                      style: Theme.of(context).textTheme.titleLarge!.copyWith(
                            color: const Color.fromARGB(255, 0, 255, 34),
                          ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Container(
                    decoration: BoxDecoration(
                      color: const Color.fromARGB(255, 0, 0, 0).withOpacity(0.2),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.remove, size: 20),
                          color: const Color.fromARGB(255, 0, 255, 34),
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
                          color: const Color.fromARGB(255, 0, 255, 34),
                          onPressed: () {
                            final songPath = _songs[_currentIndex!];
                            final currentScore = _songScores[songPath] ?? 0;
                            _updateScore(songPath, currentScore + 1);
                          },
                        ),
                        IconButton(
                          icon: const Icon(Icons.sort),
                          color: const Color.fromARGB(255, 0, 255, 34),
                          onPressed: _sortSongsByScore,
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

          return Stack(
            children: [
              // Background for the highlighted song
              Container(
                color: Colors.black, // Set the background color
              ),
              Column(
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
                        color: _isLooped ? const Color.fromARGB(255, 0, 255, 8) : null,
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
                        color: _isShuffled ? const Color.fromARGB(255, 0, 255, 8) : null,
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
                          tileColor: _currentIndex == index 
                              ? Colors.greenAccent.withOpacity(0.1)
                              : null,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(15),
                          ),
                          title: Row(
                            children: [
                              Expanded(
                                // color: const Color.fromARGB(157, 21, 255, 0),
                                child: Text(
                                  _getSongTitle(songPath),
                                  style: TextStyle(
                                    color: _currentIndex == index 
                                        ? const Color.fromARGB(255, 0, 255, 34) 
                                        : Colors.white,
                                    fontWeight: _currentIndex == index 
                                        ? FontWeight.bold 
                                        : FontWeight.normal,
                                  ),
                                ),
                              ),
                              Container(
                                decoration: BoxDecoration(
                                  color: const Color.fromARGB(0, 0, 255, 132),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Row(
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.remove, size: 18),
                                      color: _currentIndex == index 
                                        ? const Color.fromARGB(255, 0, 255, 34) 
                                        : const Color.fromARGB(125, 9, 255, 0),
                                      onPressed: () { 
                                        _updateScore(songPath, score - 1);
                                      },
                                    ),
                                    Text(score.toString(),
                                        style: const TextStyle(color: Colors.white)),
                                    IconButton(
                                      icon: const Icon(Icons.add, size: 18),
                                      color: _currentIndex == index 
                                        ? const Color.fromARGB(255, 0, 255, 34) 
                                        : const Color.fromARGB(125, 9, 255, 0),
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
              ),
            ],
          );
        },
      ),
    );
  }
}
