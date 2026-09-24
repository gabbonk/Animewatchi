import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

const base = 'https://api.jikan.moe/v4';

final Map<String, dynamic> _cache = {};
DateTime _last = DateTime.fromMillisecondsSinceEpoch(0);

// ✅ FIXED API (headers + proper throttle)
Future<dynamic> api(String path) async {
  if (_cache.containsKey(path)) return _cache[path];

  final now = DateTime.now();
  final diff = now.difference(_last).inMilliseconds;

  if (diff < 400) {
    await Future.delayed(Duration(milliseconds: 400 - diff));
  }

  _last = DateTime.now();

  final r = await http.get(
    Uri.parse('$base$path'),
    headers: {
      "Accept": "application/json",
      "User-Agent": "AnimeHubApp/1.0",
    },
  );

  if (r.statusCode != 200) {
    throw Exception('HTTP ${r.statusCode} → ${r.body}');
  }

  return _cache[path] = jsonDecode(r.body);
}

Map<String, dynamic> item(dynamic a) => {
      'id': a['mal_id'],
      'title': a['title'],
      'img': a['images']?['jpg']?['image_url'],
    };

Future<List<Map<String, dynamic>>> loadWatch() async {
  final p = await SharedPreferences.getInstance();
  return (p.getStringList('watch') ?? [])
      .map((e) => Map<String, dynamic>.from(jsonDecode(e)))
      .toList();
}

Future<void> saveWatch(List<Map<String, dynamic>> l) async {
  final p = await SharedPreferences.getInstance();
  await p.setStringList('watch', l.map((e) => jsonEncode(e)).toList());
}

Future<void> openUrl(String? u) async {
  if (u == null) return;
  final uri = Uri.parse(u);
  if (await canLaunchUrl(uri)) {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

void main() => runApp(MaterialApp(
      title: 'Anime Hub',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.deepPurple, brightness: Brightness.dark),
      ),
      home: const Home(),
    ));

class Home extends StatefulWidget {
  const Home({super.key});
  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  int tab = 0;

  @override
  Widget build(BuildContext context) {
    final pages = [const TopTab(), const SearchTab(), const WatchTab()];
    return Scaffold(
      appBar: AppBar(title: const Text('Anime Hub')),
      body: KeyedSubtree(key: ValueKey(tab), child: pages[tab]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (i) => setState(() => tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.trending_up), label: 'Browse'),
          NavigationDestination(icon: Icon(Icons.search), label: 'Search'),
          NavigationDestination(icon: Icon(Icons.bookmark), label: 'Watchlist'),
        ],
      ),
    );
  }
}

class TopTab extends StatefulWidget {
  const TopTab({super.key});
  @override
  State<TopTab> createState() => _TopTabState();
}

class _TopTabState extends State<TopTab> {
  String path = '/top/anime?limit=24';

  Widget chip(String label, String p) => ChoiceChip(
        label: Text(label),
        selected: path == p,
        onSelected: (_) => setState(() => path = p),
      );

  @override
  Widget build(BuildContext context) => Column(children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: Wrap(spacing: 8, children: [
            chip('Top rated', '/top/anime?limit=24'),
            chip('Airing now', '/seasons/now?limit=24'),
            chip('Upcoming', '/seasons/upcoming?limit=24'),
          ]),
        ),
        Expanded(child: Remote(path, key: ValueKey(path))),
      ]);
}

class SearchTab extends StatefulWidget {
  const SearchTab({super.key});
  @override
  State<SearchTab> createState() => _SearchTabState();
}

class _SearchTabState extends State<SearchTab> {
  String q = '';

  @override
  Widget build(BuildContext context) => Column(children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            decoration: const InputDecoration(
              hintText: 'Search anime...',
              prefixIcon: Icon(Icons.search),
              border: OutlineInputBorder(),
            ),
            textInputAction: TextInputAction.search,
            onSubmitted: (v) => setState(() => q = v.trim()),
          ),
        ),
        Expanded(
          child: q.isEmpty
              ? const Center(child: Text('Type a title and press search'))
              : Remote(
                  '/anime?q=${Uri.encodeQueryComponent(q)}&limit=24&sfw=true',
                  key: ValueKey(q),
                ),
        ),
      ]);
}

class WatchTab extends StatelessWidget {
  const WatchTab({super.key});

  @override
  Widget build(BuildContext context) => FutureBuilder(
        future: loadWatch(),
        builder: (c, s) {
          if (!s.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final l = s.data as List<Map<String, dynamic>>;
          if (l.isEmpty) {
            return const Center(child: Text('Your watchlist is empty'));
          }
          return Grid(l);
        },
      );
}

class Remote extends StatelessWidget {
  final String path;
  const Remote(this.path, {super.key});

  @override
  Widget build(BuildContext context) => FutureBuilder(
        future: api(path),
        builder: (c, s) {
          if (s.hasError) {
            return Center(
                child: Text('Error: ${s.error}\nTry again in a moment.'));
          }
          if (!s.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final seen = <dynamic>{};
          final list = (s.data['data'] as List)
              .map(item)
              .where((m) => seen.add(m['id']))
              .toList();

          if (list.isEmpty) {
            return const Center(child: Text('No results'));
          }

          return Grid(list);
        },
      );
}

class Grid extends StatelessWidget {
  final List<Map<String, dynamic>> items;
  const Grid(this.items, {super.key});

  @override
  Widget build(BuildContext context) => GridView.builder(
        padding: const EdgeInsets.all(8),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          childAspectRatio: 0.62,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
        ),
        itemCount: items.length,
        itemBuilder: (c, i) {
          final m = items[i];
          return InkWell(
            onTap: () => Navigator.push(
              c,
              MaterialPageRoute(builder: (_) => Detail(m['id'])),
            ),
            child: Card(
              clipBehavior: Clip.antiAlias,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: SizedBox(
                      width: double.infinity,
                      child: m['img'] == null
                          ? const Icon(Icons.image_not_supported)
                          : Image.network(
                              m['img'],
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) =>
                                  const Icon(Icons.broken_image),
                            ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: Text(
                      '${m['title']}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
}

class Detail extends StatefulWidget {
  final int id;
  const Detail(this.id, {super.key});

  @override
  State<Detail> createState() => _DetailState();
}

class _DetailState extends State<Detail> {
  bool saved = false;

  @override
  void initState() {
    super.initState();
    loadWatch().then((l) {
      if (mounted) {
        setState(() => saved = l.any((e) => e['id'] == widget.id));
      }
    });
  }

  Future<void> toggle(Map<String, dynamic> m) async {
    final l = await loadWatch();
    if (saved) {
      l.removeWhere((e) => e['id'] == widget.id);
    } else {
      l.add(m);
    }
    await saveWatch(l);
    setState(() => saved = !saved);
  }

  @override
  Widget build(BuildContext context) => FutureBuilder(
        future: api('/anime/${widget.id}/full'),
        builder: (c, s) {
          if (s.hasError) {
            return Scaffold(
              appBar: AppBar(),
              body: Center(child: Text('Error: ${s.error}')),
            );
          }
          if (!s.hasData) {
            return Scaffold(
              appBar: AppBar(),
              body: const Center(child: CircularProgressIndicator()),
            );
          }

          final a = s.data['data'];
          final m = item(a);
          final trailer = a['trailer']?['url'];
          final stream = (a['streaming'] as List?) ?? [];
          final genres = (a['genres'] as List?) ?? [];

          return Scaffold(
            appBar: AppBar(
              title: Text('${a['title']}',
                  overflow: TextOverflow.ellipsis),
              actions: [
                IconButton(
                  icon: Icon(
                      saved ? Icons.bookmark : Icons.bookmark_border),
                  onPressed: () => toggle(m),
                ),
              ],
            ),
            body: ListView(
              padding: const EdgeInsets.all(12),
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (m['img'] != null)
                      Image.network(m['img'],
                          width: 120, fit: BoxFit.cover),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${a['title']}',
                              style:
                                  Theme.of(c).textTheme.titleLarge),
                          const SizedBox(height: 8),
                          Text('Score: ${a['score'] ?? 'N/A'}'),
                          Text('Episodes: ${a['episodes'] ?? '?'}'),
                          Text('Status: ${a['status'] ?? '?'}'),
                          Text('Year: ${a['year'] ?? '?'}'),
                        ],
                      ),
                    ),
                  ],
                ),  await p.setStringList('watch', l.map((e) => jsonEncode(e)).toList());
}

Future<void> openUrl(String? u) async {
  if (u != null) await launchUrl(Uri.parse(u), mode: LaunchMode.externalApplication);
}

void main() => runApp(MaterialApp(
      title: 'Anime Hub',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.deepPurple, brightness: Brightness.dark),
      ),
      home: const Home(),
    ));

class Home extends StatefulWidget {
  const Home({super.key});
  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  int tab = 0;
  @override
  Widget build(BuildContext context) {
    final pages = [const TopTab(), const SearchTab(), const WatchTab()];
    return Scaffold(
      appBar: AppBar(title: const Text('Anime Hub')),
      body: KeyedSubtree(key: ValueKey(tab), child: pages[tab]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (i) => setState(() => tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.trending_up), label: 'Browse'),
          NavigationDestination(icon: Icon(Icons.search), label: 'Search'),
          NavigationDestination(icon: Icon(Icons.bookmark), label: 'Watchlist'),
        ],
      ),
    );
  }
}

class TopTab extends StatefulWidget {
  const TopTab({super.key});
  @override
  State<TopTab> createState() => _TopTabState();
}

class _TopTabState extends State<TopTab> {
  String path = '/top/anime?limit=24';
  Widget chip(String label, String p) => ChoiceChip(
      label: Text(label), selected: path == p, onSelected: (_) => setState(() => path = p));
  @override
  Widget build(BuildContext context) => Column(children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: Wrap(spacing: 8, children: [
            chip('Top rated', '/top/anime?limit=24'),
            chip('Airing now', '/seasons/now?limit=24'),
            chip('Upcoming', '/seasons/upcoming?limit=24'),
          ]),
        ),
        Expanded(child: Remote(path, key: ValueKey(path))),
      ]);
}

class SearchTab extends StatefulWidget {
  const SearchTab({super.key});
  @override
  State<SearchTab> createState() => _SearchTabState();
}

class _SearchTabState extends State<SearchTab> {
  String q = '';
  @override
  Widget build(BuildContext context) => Column(children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            decoration: const InputDecoration(
                hintText: 'Search anime...',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder()),
            textInputAction: TextInputAction.search,
            onSubmitted: (v) => setState(() => q = v.trim()),
          ),
        ),
        Expanded(
          child: q.isEmpty
              ? const Center(child: Text('Type a title and press search'))
              : Remote('/anime?q=${Uri.encodeQueryComponent(q)}&limit=24&sfw=true',
                  key: ValueKey(q)),
        ),
      ]);
}

class WatchTab extends StatelessWidget {
  const WatchTab({super.key});
  @override
  Widget build(BuildContext context) => FutureBuilder(
        future: loadWatch(),
        builder: (c, s) {
          if (!s.hasData) return const Center(child: CircularProgressIndicator());
          final l = s.data as List<Map<String, dynamic>>;
          if (l.isEmpty) return const Center(child: Text('Your watchlist is empty'));
          return Grid(l);
        },
      );
}

class Remote extends StatelessWidget {
  final String path;
  const Remote(this.path, {super.key});
  @override
  Widget build(BuildContext context) => FutureBuilder(
        future: api(path),
        builder: (c, s) {
          if (s.hasError) {
            return Center(child: Text('Error: ${s.error}\nTry again in a moment.'));
          }
          if (!s.hasData) return const Center(child: CircularProgressIndicator());
          final seen = <dynamic>{};
          final list = (s.data['data'] as List)
              .map(item)
              .where((m) => seen.add(m['id']))
              .toList();
          if (list.isEmpty) return const Center(child: Text('No results'));
          return Grid(list);
        },
      );
}

class Grid extends StatelessWidget {
  final List<Map<String, dynamic>> items;
  const Grid(this.items, {super.key});
  @override
  Widget build(BuildContext context) => GridView.builder(
        padding: const EdgeInsets.all(8),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2, childAspectRatio: 0.62, crossAxisSpacing: 8, mainAxisSpacing: 8),
        itemCount: items.length,
        itemBuilder: (c, i) {
          final m = items[i];
          return InkWell(
            onTap: () => Navigator.push(
                c, MaterialPageRoute(builder: (_) => Detail(m['id']))),
            child: Card(
              clipBehavior: Clip.antiAlias,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(
                  child: SizedBox(
                    width: double.infinity,
                    child: m['img'] == null
                        ? const Icon(Icons.image_not_supported)
                        : Image.network(m['img'], fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => const Icon(Icons.broken_image)),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text('${m['title']}',
                      maxLines: 2, overflow: TextOverflow.ellipsis),
                ),
              ]),
            ),
          );
        },
      );
}

class Detail extends StatefulWidget {
  final int id;
  const Detail(this.id, {super.key});
  @override
  State<Detail> createState() => _DetailState();
}

class _DetailState extends State<Detail> {
  bool saved = false;

  @override
  void initState() {
    super.initState();
    loadWatch().then((l) {
      if (mounted) setState(() => saved = l.any((e) => e['id'] == widget.id));
    });
  }

  Future<void> toggle(Map<String, dynamic> m) async {
    final l = await loadWatch();
    if (saved) {
      l.removeWhere((e) => e['id'] == widget.id);
    } else {
      l.add(m);
    }
    await saveWatch(l);
    setState(() => saved = !saved);
  }

  @override
  Widget build(BuildContext context) => FutureBuilder(
        future: api('/anime/${widget.id}/full'),
        builder: (c, s) {
          if (s.hasError) {
            return Scaffold(
                appBar: AppBar(),
                body: Center(child: Text('Error: ${s.error}')));
          }
          if (!s.hasData) {
            return Scaffold(
                appBar: AppBar(),
                body: const Center(child: CircularProgressIndicator()));
          }
          final a = s.data['data'];
          final m = item(a);
          final trailer = a['trailer']?['url'];
          final stream = (a['streaming'] as List?) ?? [];
          final genres = (a['genres'] as List?) ?? [];
          return Scaffold(
            appBar: AppBar(title: Text('${a['title']}', overflow: TextOverflow.ellipsis), actions: [
              IconButton(
                icon: Icon(saved ? Icons.bookmark : Icons.bookmark_border),
                onPressed: () => toggle(m),
              ),
            ]),
            body: ListView(padding: const EdgeInsets.all(12), children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (m['img'] != null)
                  Image.network(m['img'], width: 120, fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const SizedBox(width: 120)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${a['title']}', style: Theme.of(c).textTheme.titleLarge),
                    const SizedBox(height: 8),
                    Text('Score: ${a['score'] ?? 'N/A'}'),
                    Text('Episodes: ${a['episodes'] ?? '?'}'),
                    Text('Status: ${a['status'] ?? '?'}'),
                    Text('Year: ${a['year'] ?? '?'}'),
                  ]),
                ),
              ]),
              const SizedBox(height: 12),
              Wrap(
                  spacing: 6,
                  children: genres.map<Widget>((g) => Chip(label: Text('${g['name']}'))).toList()),
              const SizedBox(height: 8),
              Text('${a['synopsis'] ?? 'No synopsis available.'}'),
              const SizedBox(height: 12),
              if (trailer != null)
                FilledButton.icon(
                    onPressed: () => openUrl(trailer),
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('Watch trailer')),
              if (stream.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text('Where to watch', style: Theme.of(c).textTheme.titleMedium),
                Wrap(
                  spacing: 8,
                  children: stream
                      .map<Widget>((x) => OutlinedButton(
                          onPressed: () => openUrl(x['url']), child: Text('${x['name']}')))
                      .toList(),
                ),
              ],
              const SizedBox(height: 16),
              Text('Episodes', style: Theme.of(c).textTheme.titleMedium),
              FutureBuilder(
                future: api('/anime/${widget.id}/episodes'),
                builder: (c, e) {
                  if (e.hasError) return const Text('Episode list unavailable.');
                  if (!e.hasData) {
                    return const Padding(
                        padding: EdgeInsets.all(16),
                        child: Center(child: CircularProgressIndicator()));
                  }
                  final eps = e.data['data'] as List;
                  if (eps.isEmpty) return const Text('No episode list yet.');
                  return Column(
                    children: eps
                        .map<Widget>((x) => ListTile(
                            dense: true,
                            leading: Text('${x['mal_id']}'),
                            title: Text('${x['title']}')))
                        .toList(),
                  );
                },
              ),
            ]),
          );
        },
      );
}
