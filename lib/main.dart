import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:audio_session/audio_session.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
// import 'package:google_fonts/google_fonts.dart';
import 'dart:convert';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Neon Beats',
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: Colors.black,
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF00FF5A),
          secondary: Color(0xFF00FF5A),
          surface: Color(0xFF1A1A1A),
          background: Color(0xFF000000),
        ),
        textTheme: TextTheme(
          titleLarge: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
            color: Colors.white,
          ),
          bodyLarge: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w300,
            color: Colors.white,
          ),
        ),
        sliderTheme: SliderThemeData(
          activeTrackColor: const Color(0xFF00FF5A),
          inactiveTrackColor: Colors.grey.withOpacity(0.3),
          thumbColor: const Color(0xFF00FF5A),
          overlayColor: const Color(0x2200FF5A),
          trackHeight: 4,
          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
          overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      home: const MusicPlayerScreen(),
    );
  }
}

class MusicPlayerScreen extends StatefulWidget {
  const MusicPlayerScreen({super.key});

  @override
  State<MusicPlayerScreen> createState() => MusicPlayerScreenState();
}

class MusicPlayerScreenState extends State<MusicPlayerScreen> {
  final AudioPlayer _audioPlayer = AudioPlayer();
  final ItemScrollController _itemScrollController = ItemScrollController();
  final ItemPositionsListener _itemPositionsListener = ItemPositionsListener.create();
  bool _isPlaying = false;
  bool _isShuffled = true;
  bool _isLooped = true;
  late Future<List<String>> _songsFuture;
  List<String> _songs = [];
  int? _currentIndex;
  late SharedPreferences _prefs;
  Map<String, int> _songScores = {};
  bool _sortAscending = false;
  double _dragValue = 0.0;

  @override
  void initState() {
    super.initState();
    _songsFuture = _loadSongs();
    _initAudioSession();
    _audioPlayer.currentIndexStream.listen((index) {
      setState(() => _currentIndex = index);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToCurrentSong();
      });
    });
    _audioPlayer.playerStateStream.listen((state) {
      setState(() => _isPlaying = state.playing);
    });
    _audioPlayer.shuffleModeEnabledStream.listen((enabled) {
      setState(() => _isShuffled = enabled);
    });
    _audioPlayer.loopModeStream.listen((mode) {
      setState(() => _isLooped = mode == LoopMode.all);
    });
  }

  void _scrollToCurrentSong() {
    if (_currentIndex == null) return;
    _itemScrollController.scrollTo(
      index: _currentIndex!,
      duration: const Duration(milliseconds: 300),
      alignment: 0.4,
    );
  }

  String _getSongTitle(String filePath) {
    final fileName = filePath.split('/').last.replaceAll('.mp3', '');
    final parts = fileName.split('+');
    if (parts.length < 2) return fileName;
    return parts[1]
        .split('_')
        .map((word) => word[0].toUpperCase() + word.substring(1))
        .join(' ');
  }

  String _getSongArtist(String filePath) {
    final fileName = filePath.split('/').last.replaceAll('.mp3', '');
    final parts = fileName.split('+');
    if (parts.isEmpty) return 'Unknown Artist';
    return parts[0]
        .split('_')
        .map((word) => word[0].toUpperCase() + word.substring(1))
        .join(' ');
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
    // Toggle the sort order each time the button is pressed.
    _sortAscending = !_sortAscending;

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
      // Use ascending or descending based on the toggle:
      return _sortAscending 
          ? scoreA.compareTo(scoreB)
          : scoreB.compareTo(scoreA);
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: FutureBuilder<List<String>>(
        future: _songsFuture,
        builder: (context, snapshot) {
          return Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFF0A0A0A), Colors.black],
              ),
            ),
            child: Column(
              children: [
                const SizedBox(height: 40),
                Expanded(child: _buildSongList()),
              ],
            ),
          );
        },
      ),
      bottomNavigationBar: Container(
        color: const Color.fromARGB(255, 17, 17, 17),
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: _scrollToCurrentSong,
                      child: _currentIndex != null
                          ? ShaderMask(
                              shaderCallback: (bounds) => const LinearGradient(
                                colors: [Color(0xFF00FF5A), Color(0xFF00E0FF)],
                              ).createShader(bounds),
                              child: Text(
                                _getSongTitle(_songs[_currentIndex!]),
                                style: Theme.of(context).textTheme.titleLarge,
                                overflow: TextOverflow.ellipsis,
                              ),
                            )
                          : Text(
                              'Neon Beats',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.sort),
                    color: Theme.of(context).colorScheme.primary,
                    onPressed: _sortSongsByScore,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _buildSeekBar(),
              const SizedBox(height: 12),
              _buildPlayerControls(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSeekBar() {
    return StreamBuilder<Duration?>(
      stream: _audioPlayer.durationStream,
      builder: (context, snapDur) {
        final duration = snapDur.data ?? Duration.zero;
        return StreamBuilder<Duration>(
          stream: _audioPlayer.positionStream,
          builder: (context, snapPos) {
            final position = snapPos.data ?? Duration.zero;
            // update drag value when not dragging
            _dragValue = position.inMilliseconds / (duration.inMilliseconds > 0 ? duration.inMilliseconds : 1);
            return Slider(
              value: _dragValue.clamp(0.0, 1.0),
              onChanged: (value) {
                setState(() => _dragValue = value);
              },
              onChangeEnd: (value) async {
                final newPos = duration * value;
                await _audioPlayer.seek(newPos);
              },
            );
          },
        );
      },
    );
  }

  Widget _buildPlayerControls() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _buildControlButton(
          icon: Icons.shuffle,
          isActive: _isShuffled,
          onPressed: () => _audioPlayer.setShuffleModeEnabled(!_isShuffled),
        ),
        _buildControlButton(
          icon: Icons.skip_previous,
          size: 36,
          onPressed: () => _audioPlayer.seekToPrevious(),
        ),
        Container(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF00FF5A), Color(0xFF00E0FF)],
            ),
            borderRadius: BorderRadius.circular(40),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF00FF5A).withOpacity(0.4),
                blurRadius: 20,
                spreadRadius: 2,
              ),
            ],
          ),
          child: IconButton(
            icon: Icon(
              _isPlaying ? Icons.pause : Icons.play_arrow,
              size: 40,
            ),
            color: Colors.black,
            onPressed: () async {
              if (_isPlaying) {
                await _audioPlayer.pause();
              } else {
                await _audioPlayer.play();
              }
            },
            style: IconButton.styleFrom(
              backgroundColor: Colors.transparent,
              padding: const EdgeInsets.all(20),
            ),
          ),
        ),
        _buildControlButton(
          icon: Icons.skip_next,
          size: 36,
          onPressed: () => _audioPlayer.seekToNext(),
        ),
        _buildControlButton(
          icon: Icons.repeat,
          isActive: _isLooped,
          onPressed: () async {
            final newMode = _isLooped ? LoopMode.off : LoopMode.all;
            await _audioPlayer.setLoopMode(newMode);
          },
        ),
      ],
    );
  }

  Widget _buildControlButton({
    required IconData icon,
    VoidCallback? onPressed,
    double size = 24,
    bool isActive = false,
  }) {
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: isActive
              ? Theme.of(context).colorScheme.primary
              : Colors.grey.withOpacity(0.3),
          width: 2,
        ),
      ),
      child: IconButton(
        icon: Icon(icon, size: size),
        color: isActive
            ? Theme.of(context).colorScheme.primary
            : Colors.white,
        onPressed: onPressed,
      ),
    );
  }

  Widget _buildSongList() {
    return ScrollablePositionedList.builder(
      itemScrollController: _itemScrollController,
      itemPositionsListener: _itemPositionsListener,
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 10),
      itemCount: _songs.length,
      itemBuilder: (context, index) {
        final songPath = _songs[index];
        final score = _songScores[songPath] ?? 0;
        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(5),
            border: Border.all(
              color: _currentIndex == index
                  ? Theme.of(context).colorScheme.primary.withOpacity(0.3)
                  : Colors.transparent,
            ),
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 2),
            leading: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(5),
              ),
              alignment: Alignment.center,
              child: Text(
                '${index + 1}',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.primary,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _getSongTitle(songPath),
                  style: TextStyle(
                    color: _currentIndex == index
                        ? Theme.of(context).colorScheme.primary
                        : Colors.white,
                    fontWeight: _currentIndex == index 
                        ? FontWeight.w600 
                        : FontWeight.normal,
                  ),
                ),
                Text(
                  _getSongArtist(songPath),
                  style: Theme.of(context).textTheme.bodyLarge!.copyWith(
                        fontSize: 12,
                        color: Colors.grey.withOpacity(0.8),
                      ),
                ),
              ],
            ),
            trailing: _buildScoreBadge(songPath, score),
            onTap: () async {
              if (_isPlaying) await _audioPlayer.stop();
              await _audioPlayer.seek(Duration.zero, index: index);
              await _audioPlayer.play();
            },
          ),
        );
      },
    );
  }

  Widget _buildScoreBadge(String songPath, int score) {
    return Container(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.remove, size: 18),
            color: Theme.of(context).colorScheme.primary,
            onPressed: () => _updateScore(songPath, score - 1),
          ),
          Text(
            '$score',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.add, size: 18),
            color: Theme.of(context).colorScheme.primary,
            onPressed: () => _updateScore(songPath, score + 1),
          ),
        ],
      ),
    );
  }

  Widget _buildScoreControls() {
    return Container(
      // decoration: BoxDecoration(
      //   color: Colors.black.withOpacity(0.3),
      //   borderRadius: BorderRadius.circular(20),
      //   border: Border.all(
      //     color: Theme.of(context).colorScheme.primary.withOpacity(0.5),
      //   ),
      // ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.sort),
            color: Theme.of(context).colorScheme.primary,
            onPressed: _sortSongsByScore,
          ),
          Text(
            'Score',
            style: TextStyle(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

}
