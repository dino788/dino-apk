import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';

typedef Channel = Map<String, String>;
typedef DataMap = Map<String, Map<String, List<Channel>>>;

DataMap _emptyData() => {
      'live': {'الكل': <Channel>[]},
      'movies': {'الكل': <Channel>[]},
      'series': {'الكل': <Channel>[]},
    };

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
    DeviceOrientation.portraitUp,
  ]);
  runApp(const DinoAllachApp());
}

class DinoAllachApp extends StatelessWidget {
  const DinoAllachApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'dino allach',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0B0C10),
        primaryColor: const Color(0xFFE50914),
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _hostCtrl = TextEditingController();
  final TextEditingController _userCtrl = TextEditingController();
  final TextEditingController _passCtrl = TextEditingController();
  final TextEditingController _m3uCtrl = TextEditingController();
  final TextEditingController _searchCtrl = TextEditingController();

  String _currentTab = 'live'; // live, movies, series
  String _status = 'جاهز';
  String _selectedCat = 'الكل';

  DataMap _data = _emptyData();

  List<Channel> _currentChannels = [];
  VideoPlayerController? _videoController;
  ChewieController? _chewieController;
  String _nowPlaying = 'اختر قناة لبدء البث';

  @override
  void initState() {
    super.initState();
    _loadSavedCredentials();
  }

  Future<void> _loadSavedCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    _hostCtrl.text = prefs.getString('host') ?? '';
    _userCtrl.text = prefs.getString('user') ?? '';
    _passCtrl.text = prefs.getString('pass') ?? '';
    _m3uCtrl.text = prefs.getString('m3u') ?? '';
    if (_hostCtrl.text.isNotEmpty && _userCtrl.text.isNotEmpty) {
      _loginXtream();
    } else if (_m3uCtrl.text.isNotEmpty) {
      _loadM3U();
    }
  }

  Future<void> _loginXtream() async {
    String h = _hostCtrl.text.trim();
    if (h.endsWith('/')) h = h.substring(0, h.length - 1);
    String u = _userCtrl.text.trim();
    String p = _passCtrl.text.trim();
    if (h.isEmpty || u.isEmpty || p.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('host', h);
    await prefs.setString('user', u);
    await prefs.setString('pass', p);

    setState(() => _status = 'جاري جلب القنوات والأفلام...');
    final headers = {'User-Agent': 'IPTVSmartersPlayer'};

    DataMap temp = _emptyData();

    try {
      // 1. Live TV
      final lCatRes = await http.get(
          Uri.parse('$h/player_api.php?username=$u&password=$p&action=get_live_categories'),
          headers: headers);
      Map<String, String> lCats = {};
      if (lCatRes.statusCode == 200) {
        for (var c in jsonDecode(lCatRes.body)) {
          lCats[c['category_id'].toString()] = c['category_name'].toString();
        }
      }
      final liveRes = await http.get(
          Uri.parse('$h/player_api.php?username=$u&password=$p&action=get_live_streams'),
          headers: headers);
      if (liveRes.statusCode == 200) {
        for (var st in jsonDecode(liveRes.body)) {
          String grp = lCats[st['category_id'].toString()] ?? 'Live TV';
          String sid = st['stream_id'].toString();
          Channel item = {
            'name': st['name'].toString(),
            'url': '$h/live/$u/$p/$sid.ts',
            'group': grp
          };
          temp['live']!['الكل']!.add(item);
          temp['live']!.putIfAbsent(grp, () => <Channel>[]).add(item);
        }
      }

      // 2. Movies (VOD)
      final vCatRes = await http.get(
          Uri.parse('$h/player_api.php?username=$u&password=$p&action=get_vod_categories'),
          headers: headers);
      Map<String, String> vCats = {};
      if (vCatRes.statusCode == 200) {
        for (var c in jsonDecode(vCatRes.body)) {
          vCats[c['category_id'].toString()] = c['category_name'].toString();
        }
      }
      final vodRes = await http.get(
          Uri.parse('$h/player_api.php?username=$u&password=$p&action=get_vod_streams'),
          headers: headers);
      if (vodRes.statusCode == 200) {
        for (var st in jsonDecode(vodRes.body)) {
          String grp = vCats[st['category_id'].toString()] ?? 'Movies';
          String sid = st['stream_id'].toString();
          String ext = (st['container_extension'] ?? 'mp4').toString();
          Channel item = {
            'name': st['name'].toString(),
            'url': '$h/movie/$u/$p/$sid.$ext',
            'group': grp
          };
          temp['movies']!['الكل']!.add(item);
          temp['movies']!.putIfAbsent(grp, () => <Channel>[]).add(item);
        }
      }

      // 3. Series
      final sCatRes = await http.get(
          Uri.parse('$h/player_api.php?username=$u&password=$p&action=get_series_categories'),
          headers: headers);
      Map<String, String> sCats = {};
      if (sCatRes.statusCode == 200) {
        for (var c in jsonDecode(sCatRes.body)) {
          sCats[c['category_id'].toString()] = c['category_name'].toString();
        }
      }
      final serRes = await http.get(
          Uri.parse('$h/player_api.php?username=$u&password=$p&action=get_series'),
          headers: headers);
      if (serRes.statusCode == 200) {
        for (var st in jsonDecode(serRes.body)) {
          String grp = sCats[st['category_id'].toString()] ?? 'Series';
          String sid = st['series_id'].toString();
          Channel item = {
            'name': '🍿 ${st['name']}',
            'url': 'series://$h|$u|$p|$sid',
            'group': grp
          };
          temp['series']!['الكل']!.add(item);
          temp['series']!.putIfAbsent(grp, () => <Channel>[]).add(item);
        }
      }

      setState(() {
        _data = temp;
        _selectedCat = 'الكل';
        _currentChannels = _data[_currentTab]!['الكل'] ?? [];
        _status = 'تم التحميل بنجاح';
      });
    } catch (e) {
      setState(() => _status = 'خطأ في الاتصال بالسيرفر');
    }
  }

  Future<void> _loadM3U() async {
    String url = _m3uCtrl.text.trim();
    if (url.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('m3u', url);
    setState(() => _status = 'جاري تحميل M3U...');

    try {
      final res = await http.get(Uri.parse(url),
          headers: {'User-Agent': 'IPTVSmartersPlayer'});
      if (res.statusCode == 200) {
        DataMap temp = _emptyData();
        String curName = 'Channel';
        String curGrp = 'General';
        final grpReg = RegExp(r'group-title="([^"]*)"', caseSensitive: false);

        for (var raw in const LineSplitter().convert(res.body)) {
          String line = raw.trim();
          if (line.startsWith('#EXTINF')) {
            final m = grpReg.firstMatch(line);
            curGrp = (m != null && m.group(1)!.isNotEmpty) ? m.group(1)! : 'General';
            final parts = line.split(',');
            curName = parts.length > 1 ? parts.sublist(1).join(',').trim() : 'Stream';
          } else if (line.startsWith('http')) {
            String sec = 'live';
            if (line.contains('/movie/') || line.endsWith('.mp4') || line.endsWith('.mkv')) {
              sec = 'movies';
            }
            if (line.contains('/series/')) sec = 'series';
            Channel item = {'name': curName, 'url': line, 'group': curGrp};
            temp[sec]!['الكل']!.add(item);
            temp[sec]!.putIfAbsent(curGrp, () => <Channel>[]).add(item);
          }
        }
        setState(() {
          _data = temp;
          _selectedCat = 'الكل';
          _currentChannels = _data[_currentTab]!['الكل'] ?? [];
          _status = 'تم تحميل القائمة';
        });
      }
    } catch (e) {
      setState(() => _status = 'تعذر تحميل M3U');
    }
  }

  Future<void> _playChannel(Channel ch) async {
    String url = ch['url']!;
    if (url.startsWith('series://')) {
      _loadSeriesEpisodes(url);
      return;
    }

    setState(() => _nowPlaying = ch['name']!);
    await _videoController?.dispose();
    _chewieController?.dispose();

    // تشغيل عبر ExoPlayer الأصلي في الأندرويد مع الهوية الذكية
    _videoController = VideoPlayerController.networkUrl(
      Uri.parse(url),
      httpHeaders: {
        'User-Agent': 'ExoPlayerLib/2.19.1 (Linux; Android 13; TV)',
        'Connection': 'keep-alive',
      },
    );

    try {
      await _videoController!.initialize();
      _chewieController = ChewieController(
        videoPlayerController: _videoController!,
        autoPlay: true,
        isLive: _currentTab == 'live',
        allowFullScreen: true,
        overlay: const Padding(
          padding: EdgeInsets.all(14.0),
          child: Align(
            alignment: Alignment.topLeft,
            child: Text(
              'dino allach',
              style: TextStyle(
                color: Color(0x66FFFFFF),
                fontSize: 16,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.2,
              ),
            ),
          ),
        ),
      );
      setState(() {});
    } catch (e) {
      setState(() => _status = 'تعذر تشغيل القناة، جاري إعادة المحاولة...');
    }
  }

  Future<void> _loadSeriesEpisodes(String rawUrl) async {
    final parts = rawUrl.replaceFirst('series://', '').split('|');
    if (parts.length < 4) return;
    String h = parts[0], u = parts[1], p = parts[2], sid = parts[3];
    setState(() => _status = 'جاري جلب الحلقات...');
    try {
      final res = await http.get(
        Uri.parse('$h/player_api.php?username=$u&password=$p&action=get_series_info&series_id=$sid'),
        headers: {'User-Agent': 'IPTVSmartersPlayer'},
      );
      if (res.statusCode == 200) {
        final decoded = jsonDecode(res.body);
        final epsMap = decoded['episodes'];
        List<Channel> epList = [];
        if (epsMap is Map) {
          epsMap.forEach((season, eps) {
            for (var ep in eps) {
              String id = ep['id'].toString();
              String ext = (ep['container_extension'] ?? 'mp4').toString();
              epList.add({
                'name': '▶ ${ep['title'] ?? 'Episode $id'}',
                'url': '$h/series/$u/$p/$id.$ext',
                'group': 'Season $season'
              });
            }
          });
        }
        setState(() {
          _currentChannels = epList;
          _status = 'تم جلب ${epList.length} حلقة';
        });
      }
    } catch (_) {}
  }

  void _openLoginModal() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF12151F),
        title: const Text('إعدادات السيرفر - DINO ALLACH',
            style: TextStyle(color: Color(0xFFF5C518))),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                  controller: _hostCtrl,
                  decoration: const InputDecoration(labelText: 'Host (http://server:8080)')),
              TextField(
                  controller: _userCtrl,
                  decoration: const InputDecoration(labelText: 'Username')),
              TextField(
                  controller: _passCtrl,
                  decoration: const InputDecoration(labelText: 'Password')),
              const SizedBox(height: 12),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE50914)),
                onPressed: () {
                  Navigator.pop(context);
                  _loginXtream();
                },
                child: const Text('اتصال بـ Xtream Codes'),
              ),
              const Divider(height: 24),
              TextField(
                  controller: _m3uCtrl,
                  decoration: const InputDecoration(labelText: 'أو رابط M3U مباشر')),
              const SizedBox(height: 10),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                  _loadM3U();
                },
                child: const Text('تحميل M3U'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _videoController?.dispose();
    _chewieController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cats = _data[_currentTab]!.keys.toList();
    final filteredChannels = _currentChannels
        .where((c) => c['name']!.toLowerCase().contains(_searchCtrl.text.toLowerCase()))
        .toList();

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              // الشريط العلوي
              Container(
                color: const Color(0xFF12151F),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(
                  children: [
                    const Text(
                      '⚡ DINO ALLACH PRO',
                      style: TextStyle(
                          color: Color(0xFFF5C518), fontSize: 18, fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(width: 14),
                    _tabBtn('live', '📺 مباشر (${_data['live']!['الكل']!.length})'),
                    const SizedBox(width: 8),
                    _tabBtn('movies', '🎬 أفلام (${_data['movies']!['الكل']!.length})'),
                    const SizedBox(width: 8),
                    _tabBtn('series', '🍿 مسلسلات (${_data['series']!['الكل']!.length})'),
                    const Spacer(),
                    Text(_status,
                        style: const TextStyle(color: Color(0xFFF5C518), fontSize: 12)),
                    const SizedBox(width: 10),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE50914)),
                      onPressed: _openLoginModal,
                      icon: const Icon(Icons.vpn_key, size: 16),
                      label: const Text('السيرفر'),
                    ),
                  ],
                ),
              ),
              // الجسم الرئيسي
              Expanded(
                child: Row(
                  children: [
                    // الباقات
                    Container(
                      width: 190,
                      color: const Color(0xFF12151F),
                      child: ListView.builder(
                        itemCount: cats.length,
                        itemBuilder: (_, i) {
                          String c = cats[i];
                          bool sel = c == _selectedCat;
                          return ListTile(
                            dense: true,
                            selected: sel,
                            selectedTileColor: const Color(0xFFE50914),
                            title: Text('$c (${_data[_currentTab]![c]!.length})',
                                style: const TextStyle(fontSize: 13)),
                            onTap: () {
                              setState(() {
                                _selectedCat = c;
                                _currentChannels = _data[_currentTab]![c] ?? [];
                              });
                            },
                          );
                        },
                      ),
                    ),
                    // القنوات
                    Container(
                      width: 240,
                      color: const Color(0xFF161A28),
                      child: Column(
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(6.0),
                            child: TextField(
                              controller: _searchCtrl,
                              onChanged: (_) => setState(() {}),
                              decoration: const InputDecoration(
                                hintText: 'بحث سريع...',
                                isDense: true,
                                prefixIcon: Icon(Icons.search, size: 18),
                              ),
                            ),
                          ),
                          Expanded(
                            child: ListView.builder(
                              itemCount: filteredChannels.length,
                              itemBuilder: (_, i) {
                                final ch = filteredChannels[i];
                                return ListTile(
                                  dense: true,
                                  title: Text('${i + 1}. ${ch['name']}',
                                      style: const TextStyle(fontSize: 13)),
                                  onTap: () => _playChannel(ch),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                    // مشغل ExoPlayer
                    Expanded(
                      child: Container(
                        color: Colors.black,
                        child: Column(
                          children: [
                            Expanded(
                              child: _chewieController != null &&
                                      _videoController!.value.isInitialized
                                  ? Chewie(controller: _chewieController!)
                                  : const Center(
                                      child: Text(
                                        'DINO ALLACH PLAYER\nExoPlayer Native Engine',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                            color: Colors.white38,
                                            fontSize: 18,
                                            fontWeight: FontWeight.bold),
                                      ),
                                    ),
                            ),
                            Container(
                              width: double.infinity,
                              color: const Color(0xFF12151F),
                              padding: const EdgeInsets.all(8),
                              child: Text(
                                'يشتغل الآن: $_nowPlaying',
                                style: const TextStyle(
                                    color: Color(0xFFF5C518), fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tabBtn(String key, String label) {
    bool active = _currentTab == key;
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: active ? const Color(0xFFF5C518) : const Color(0xFF1F2538),
        foregroundColor: active ? Colors.black : Colors.white,
      ),
      onPressed: () {
        setState(() {
          _currentTab = key;
          _selectedCat = 'الكل';
          _currentChannels = _data[key]!['الكل'] ?? [];
        });
      },
      child: Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
    );
  }
}
