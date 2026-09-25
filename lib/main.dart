import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

const base = 'https://api.jikan.moe/v4';
final Map<String, dynamic> _cache = {};

// All requests funnel through this queue so only one hits the network
// at a time, spaced out, instead of a page firing 3+ calls at once.
Future<dynamic> _queue = Future.value();

// Cached, serialized, and retried with backoff (Jikan allows ~3 req/s
// but is a free/shared service that returns 504s under load).
Future<dynamic> api(String path) {
  if (_cache.containsKey(path)) return Future.value(_cache[path]);
  final result = _queue
      .then((_) => Future.delayed(const Duration(milliseconds: 350)))
      .then((_) => _fetchWithRetry(path));
  // Swallow errors here so one failure doesn't poison the queue chain
  // for requests queued after it.
  _queue = result.then((_) => null).catchError((_) => null);
  return result;
}

Future<dynamic> _fetchWithRetry(String path) async {
  const maxAttempts = 4;
  for (var attempt = 1; attempt <= maxAttempts; attempt++) {
    try {
      final r = await http
          .get(Uri.parse('$base$path'))
          .timeout(const Duration(seconds: 12));

      if (r.statusCode == 200) {
        return _cache[path] = jsonDecode(r.body);
      }

      // 429 = rate limited, 500/502/503/504 = server-side/overload.
      // Worth retrying. Anything else (404, etc) fails immediately.
      final retryable = r.statusCode == 429 || r.statusCode >= 500;
      if (!retryable || attempt == maxAttempts) {
        throw Exception('HTTP ${r.statusCode}');
      }
    } catch (e) {
      if (attempt == maxAttempts) rethrow;
    }
    // Exponential backoff: 500ms, 1000ms, 2000ms between retries.
    await Future.delayed(Duration(milliseconds: 500 * (1 << (attempt - 1))));
  }
  throw Exception('Failed after $maxAttempts attempts');
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

class Remote extends StatefulWidget {
  final String path;
  const Remote(this.path, {super.key});
  @override
  State<Remote> createState() => _RemoteState();
}

class _RemoteState extends State<Remote> {
  late Future<dynamic> future = api(widget.path);
  @override
  Widget build(BuildContext context) => FutureBuilder(
        future: future,
        builder: (c, s) {
          if (s.hasError) {
            return Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Text('Something went wrong loading this.'),
                const SizedBox(height: 8),
                Text('${s.error}', style: Theme.of(c).textTheme.bodySmall),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: () => setState(() => future = api(widget.path)),
                  child: const Text('Retry'),
                ),
              ]),
            );
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
  Future<dynamic>? epFuture;
  late Future<dynamic> detailFuture = api('/anime/${widget.id}/full');

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
        future: detailFuture,
        builder: (c, s) {
          if (s.hasError) {
            return Scaffold(
              appBar: AppBar(),
              body: Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text('Error: ${s.error}'),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: () => setState(
                        () => detailFuture = api('/anime/${widget.id}/full')),
                    child: const Text('Retry'),
                  ),
                ]),
              ),
            );
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
              StatefulBuilder(
                builder: (c, setEpState) {
                  epFuture ??= api('/anime/${widget.id}/episodes');
                  return FutureBuilder(
                    future: epFuture,
                    builder: (c, e) {
                      if (e.hasError) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Row(children: [
                            const Expanded(child: Text('Episode list failed to load.')),
                            TextButton(
                              onPressed: () => setEpState(
                                  () => epFuture = api('/anime/${widget.id}/episodes')),
                              child: const Text('Retry'),
                            ),
                          ]),
                        );
                      }
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
                  );
                },
              ),
            ]),
          );
        },
      );
}
