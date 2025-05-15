// ignore_for_file: curly_braces_in_flow_control_structures

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:audio_session/audio_session.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'dart:math';
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

class _ListItem {
  final bool isHeader;
  final int score;
  final String? songPath;

  _ListItem.header(this.score)
      : isHeader = true,
        songPath = null;

  _ListItem.song(this.songPath, this.score)
      : isHeader = false;
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
  // bool _isLooped = true;
  late Future<List<String>> _songsFuture;
  List<String> _songs = [];
  int? _currentIndex;
  late SharedPreferences _prefs;
  Map<String, int> _songScores = {};
  double _dragValue = 0.0;
  final _rand = Random();
  List<int> _weightedIndices = [];
  List<int> _history = [];
  bool _reachedEnd = false;

  @override
  void initState() {
    super.initState();
    _initAudioSession();
    _songsFuture = _loadSongs().then((songs) async {
      await _sortSongsByScore();
      return songs;
    });
    
    _audioPlayer.playerStateStream.listen((state) {
      setState(() => _isPlaying = state.playing);
    });

    _audioPlayer.positionStream.listen((position) {
      final duration = _audioPlayer.duration;
      if (duration != null && _audioPlayer.playing) {
        final remaining = duration - position;
        if (remaining.inMilliseconds <= 100) { // 100ms threshold
          _reachedEnd = true;
        }
      }
    });

    _audioPlayer.currentIndexStream.listen((index) {
      if (_reachedEnd && index != null) {
        Future.microtask(() {_playNext();});        
        _reachedEnd = false;
      }
      
      setState(() => _currentIndex = index);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToCurrentSong();
        _buildWeightedIndices();
      });
    });

    _buildWeightedIndices();
    _audioPlayer.setLoopMode(LoopMode.off);
  }

void _scrollToCurrentSong() {

  if (_currentIndex == null)
    return;

  final items = _buildGroupedList();
  final currentPath = _songs[_currentIndex!];
  final targetIndex = items.indexWhere((it) => !it.isHeader && it.songPath == currentPath );
  final idx = targetIndex != -1 ? targetIndex : items.indexWhere((it) => !it.isHeader );
  _itemScrollController.scrollTo(
    index: idx,
    duration: const Duration(milliseconds: 300),
    alignment: 0.4,
  );
}


  void _buildWeightedIndices() {
    _weightedIndices = [];
    for (var i = 0; i < _songs.length; i++) {
      final score = _songScores[_songs[i]] ?? 0;
      for (var j = 0; j < score; j++)
        _weightedIndices.add(i);
    }
      
    if (_weightedIndices.isEmpty && _songs.isNotEmpty)
      _weightedIndices = List.generate(_songs.length, (i) => i);
  }

  Future<void> _playNext() async {
    
    if (_songs.isEmpty)
      return;

    int pick;
    int loopCounter = 0;
    do {
      pick = _weightedIndices[_rand.nextInt(_weightedIndices.length)];
      loopCounter++;
    } while (pick == _currentIndex && loopCounter < 100);

    if (pick == _currentIndex) {                // if we failed to find a different one after 100 tries, just pick the next in list:
      final current = _currentIndex ?? 0;
      pick = (current + 1) < _songs.length ? current + 1 : 0;
    }

    await _audioPlayer.seek(Duration.zero, index: pick);
    await _audioPlayer.play();
  }

  Future<void> _playPrevious() async {

    if (_history.length < 2)
      return;

    _history.removeLast();
    final previous = _history.removeLast();
    await _audioPlayer.seek(Duration.zero, index: previous);
    await _audioPlayer.play();
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
      _songScores = Map<String, int>.from(json.decode(scoresJson));
    }

    // Assign a default score of 1 to songs without a score
    bool updated = false;
    for (final song in _songs) {
      if (!_songScores.containsKey(song)) {
        _songScores[song] = 1;
        updated = true;
      }
    }

    if (updated) {
      await _saveScores();
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
    // await _audioPlayer.setShuffleModeEnabled(true);
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
      return scoreB.compareTo(scoreA);
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

  List<_ListItem> _buildGroupedList() {
    // group songs by score
    final Map<int, List<String>> byScore = { for (var s=0; s<=9; s++) s: [] };
    for (var song in _songs) {
      final score = _songScores[song] ?? 0;
      byScore[score]!.add(song);
    }

    // flatten: highest score first
    final List<_ListItem> items = [];
    for (int score = 9; score >= 0; score--) {
      items.add(_ListItem.header(score));
      for (var song in byScore[score]!) {
        items.add(_ListItem.song(song, score));
      }
    }
    return items;
  }

  void _openSearchPopup() {
    showDialog(
      context: context,
      builder: (context) {
        String query = '';
        List<String> matches = [];

        return StatefulBuilder(
          builder: (context, setState) {
            void _filterSongs(String input) {
              final lower = input.toLowerCase();
              final filtered = _songs.where((path) {
                final title = _getSongTitle(path).toLowerCase();
                final artist = _getSongArtist(path).toLowerCase();
                return title.contains(lower) || artist.contains(lower);
              }).toList();
              setState(() {
                query = input;
                matches = filtered;
              });
            }

            return AlertDialog(
              backgroundColor: Theme.of(context).colorScheme.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              title: const Text('Search Songs'),
              content: SizedBox(
                width: double.maxFinite,
                height: 350,
                child: Column(
                  children: [
                    TextField(
                      decoration: InputDecoration(
                        hintText: 'Type song title or artist...',
                        prefixIcon: const Icon(Icons.search),
                        filled: true,
                        fillColor: Colors.white12,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      onChanged: _filterSongs,
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: matches.isEmpty && query.isNotEmpty
                          ? const Center(
                              child: Text(
                                'No matches found',
                                style: TextStyle(color: Colors.white60),
                              ),
                            )
                          : ListView.separated(
                              itemCount: matches.length,
                              separatorBuilder: (context, index) => const Divider(
                                color: Colors.white24,
                                height: 1,
                              ),
                              itemBuilder: (context, i) {
                                final path = matches[i];
                                return ListTile(
                                  leading: const Icon(
                                    Icons.music_note,
                                    color: Color(0xFF00FF5A),
                                  ),
                                  title: Text(
                                    _getSongTitle(path),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  subtitle: Text(
                                    _getSongArtist(path),
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Colors.white70,
                                    ),
                                  ),
                                  onTap: () async {
                                    final newIndex = _songs.indexOf(path);
                                    Navigator.of(context).pop();
                                    await _audioPlayer.seek(
                                      Duration.zero,
                                      index: newIndex,
                                    );
                                    await _audioPlayer.play();
                                  },
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  child: const Text('Close'),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            );
          },
        );
      },
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
        IconButton(
          icon: const Icon(Icons.search),
          color: Theme.of(context).colorScheme.primary,
          onPressed: _openSearchPopup,
        ),
        _buildControlButton(
          icon: Icons.skip_previous,
          size: 36,
          onPressed: () => _playPrevious(),
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
          onPressed: () => _playNext(),
        ),
        IconButton(
          icon: const Icon(Icons.sort),
          color: Theme.of(context).colorScheme.primary,
          onPressed: _sortSongsByScore,
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
    final items = _buildGroupedList();

    return ScrollablePositionedList.builder(
      itemScrollController: _itemScrollController,
      itemPositionsListener: _itemPositionsListener,
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 10),
      itemCount: items.length,
      itemBuilder: (context, idx) {
        final item = items[idx];
        if (item.isHeader) {
          // A divider + score label
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                Expanded(child: Divider(color: Colors.white24)),
                const SizedBox(width: 8),
                Text(
                  'Score ${item.score}',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(child: Divider(color: Colors.white24)),
              ],
            ),
          );
        } else {
          // Find the real index in _songs so that tapping/scrolling still works
          final songIndex = _songs.indexOf(item.songPath!);
          return Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(5),
              border: Border.all(
                color: _currentIndex == songIndex
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
                  '${songIndex + 1}',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _getSongTitle(item.songPath!),
                    style: TextStyle(
                      color: _currentIndex == songIndex
                          ? Theme.of(context).colorScheme.primary
                          : Colors.white,
                      fontWeight: _currentIndex == songIndex
                          ? FontWeight.w600
                          : FontWeight.normal,
                    ),
                  ),
                  Text(
                    _getSongArtist(item.songPath!),
                    style: Theme.of(context).textTheme.bodyLarge!
                        .copyWith(fontSize: 12, color: Colors.grey.withOpacity(0.8)),
                  ),
                ],
              ),
              trailing: _buildScoreBadge(item.songPath!, item.score),
              onTap: () async {
                if (_isPlaying) await _audioPlayer.stop();
                await _audioPlayer.seek(Duration.zero, index: songIndex);
                await _audioPlayer.play();
              },
            ),
          );
        }
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

}
