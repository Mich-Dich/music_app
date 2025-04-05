import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:audio_session/audio_session.dart';
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
  int? _currentIndex; // Add this variable

  @override
  void initState() {
    super.initState();
    _songsFuture = _loadSongs();
    _initAudioSession();
    
    // Add this listener for current track index
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
  }

  Future<List<String>> _loadSongs() async {
    // Load asset manifest
    final manifestContent = await rootBundle.loadString('AssetManifest.json');
    final Map<String, dynamic> manifest = json.decode(manifestContent);
    
    // Filter MP3 files from assets
    _songs = manifest.keys
        .where((path) => path.endsWith('.mp3') && path.startsWith('assets/'))
        .toList();

    // Setup playlist if songs are found
    if (_songs.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _setupPlaylist());
    }

    return _songs;
  }

  Future<void> _initAudioSession() async {
    final session = await AudioSession.instance;
    await session.configure(AudioSessionConfiguration.music());
  }

  Future<void> _setupPlaylist() async {
    await _audioPlayer.setLoopMode(LoopMode.off);
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
    // Remove path and extension, capitalize first letters
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
              // Album Art
              Container(
                height: 300,
                decoration: const BoxDecoration(
                  image: DecorationImage(
                    image: AssetImage('assets/album_art.jpg'),
                    fit: BoxFit.cover,
                  ),
                ),
              ),
              // ... [Keep the rest of your existing UI elements] ...
              // Progress Bar
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
              // Controls
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
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
                      // Remove the setState from here
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.skip_next, size: 40),
                    onPressed: () => _audioPlayer.seekToNext(),
                  ),
                ],
              ),
              // Song List
              Expanded(
                child: ListView.builder(
                  itemCount: _songs.length,
                  itemBuilder: (context, index) => ListTile(
                    title: Text(_songs[index].split('/').last),
                    subtitle: Text('Artist ${index + 1}'),
                    onTap: () => _audioPlayer.seek(Duration.zero, index: index),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}