import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:audio_session/audio_session.dart';

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

  final List<String> _songs = [
    'assets/gorila_000.mp3',
  ];

  @override
  void initState() {
    super.initState();
    _initAudioSession();
    _setupPlaylist();
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Music Player'),
      ),
      body: Column(
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
          
          // Song Info
          const Padding(
            padding: EdgeInsets.all(16.0),
            child: Column(
              children: [
                Text(
                  'Song Title',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 8),
                Text('Artist Name', style: TextStyle(fontSize: 18)),
              ],
            ),
          ),
          
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
                  setState(() => _isPlaying = !_isPlaying);
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
                title: Text('Song ${index + 1}'),
                subtitle: Text('Artist ${index + 1}'),
                onTap: () => _audioPlayer.seek(Duration.zero, index: index),
              ),
            ),
          ),
        ],
      ),
    );
  }
}