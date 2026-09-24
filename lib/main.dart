// FULL FEATURED ANIME APP (AniAPI + Watchlist + Glass UI)

import 'dart:convert';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

const base = "https://api.aniapi.com/v1";

// ================= API =================
Future<dynamic> api(String path) async {
  final res = await http.get(Uri.parse("$base$path"));

  if (res.statusCode != 200) {
    throw Exception("Error ${res.statusCode}");
  }

  return jsonDecode(res.body);
}

Map<String, dynamic> item(dynamic a) => {
      "id": a["id"],
      "title": a["titles"]?["en"] ?? a["titles"]?["jp"] ?? "No Title",
      "img": a["cover_image"],
    };

// ================= WATCHLIST =================
Future<List<Map<String, dynamic>>> loadWatch() async {
  final p = await SharedPreferences.getInstance();
  return (p.getStringList("watch") ?? [])
      .map((e) => Map<String, dynamic>.from(jsonDecode(e)))
      .toList();
}

Future<void> saveWatch(List<Map<String, dynamic>> list) async {
  final p = await SharedPreferences.getInstance();
  await p.setStringList(
      "watch", list.map((e) => jsonEncode(e)).toList());
}

// ================= URL =================
Future<void> openUrl(String? url) async {
  if (url == null) return;
  final uri = Uri.parse(url);
  if (await canLaunchUrl(uri)) {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

// ================= APP =================
void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: "Anime Hub",
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(),
      home: const Home(),
    );
  }
}

// ================= HOME =================
class Home extends StatefulWidget {
  const Home({super.key});
  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  int tab = 0;

  @override
  Widget build(BuildContext context) {
    final pages = [
      const BrowseTab(),
      const SearchTab(),
      const WatchTab(),
    ];

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(title: const Text("Anime Hub")),
      body: pages[tab],
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (i) => setState(() => tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home), label: "Browse"),
          NavigationDestination(icon: Icon(Icons.search), label: "Search"),
          NavigationDestination(icon: Icon(Icons.bookmark), label: "Saved"),
        ],
      ),
    );
  }
}

// ================= GLASS CARD =================
Widget glass({required Widget child}) {
  return ClipRRect(
    borderRadius: BorderRadius.circular(16),
    child: BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white24),
        ),
        child: child,
      ),
    ),
  );
}

// ================= BROWSE =================
class BrowseTab extends StatelessWidget {
  const BrowseTab({super.key});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: api("/anime?per_page=12"),
      builder: (c, s) {
        if (!s.hasData) return const Center(child: CircularProgressIndicator());

        final list =
            (s.data["data"]["documents"] as List).map(item).toList();

        return Grid(list);
      },
    );
  }
}

// ================= SEARCH =================
class SearchTab extends StatefulWidget {
  const SearchTab({super.key});
  @override
  State<SearchTab> createState() => _SearchTabState();
}

class _SearchTabState extends State<SearchTab> {
  String q = "";

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            decoration: const InputDecoration(
              hintText: "Search anime...",
              border: OutlineInputBorder(),
            ),
            onSubmitted: (v) => setState(() => q = v),
          ),
        ),
        Expanded(
          child: q.isEmpty
              ? const Center(child: Text("Search something"))
              : FutureBuilder(
                  future: api("/anime?title=$q"),
                  builder: (c, s) {
                    if (!s.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    final list =
                        (s.data["data"]["documents"] as List).map(item).toList();

                    return Grid(list);
                  },
                ),
        ),
      ],
    );
  }
}

// ================= WATCHLIST =================
class WatchTab extends StatelessWidget {
  const WatchTab({super.key});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: loadWatch(),
      builder: (c, s) {
        if (!s.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final list = s.data as List<Map<String, dynamic>>;

        if (list.isEmpty) {
          return const Center(child: Text("No bookmarks yet"));
        }

        return Grid(list);
      },
    );
  }
}

// ================= GRID =================
class Grid extends StatelessWidget {
  final List<Map<String, dynamic>> items;
  const Grid(this.items, {super.key});

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.all(8),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 0.65,
      ),
      itemCount: items.length,
      itemBuilder: (c, i) {
        final m = items[i];

        return InkWell(
          onTap: () => Navigator.push(
            c,
            MaterialPageRoute(builder: (_) => Detail(m)),
          ),
          child: glass(
            child: Column(
              children: [
                Expanded(
                  child: Image.network(m["img"], fit: BoxFit.cover),
                ),
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text(
                    m["title"],
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
}

// ================= DETAIL =================
class Detail extends StatefulWidget {
  final Map<String, dynamic> anime;
  const Detail(this.anime, {super.key});

  @override
  State<Detail> createState() => _DetailState();
}

class _DetailState extends State<Detail> {
  bool saved = false;

  @override
  void initState() {
    super.initState();
    loadWatch().then((list) {
      saved = list.any((e) => e["id"] == widget.anime["id"]);
      setState(() {});
    });
  }

  Future<void> toggle() async {
    final list = await loadWatch();

    if (saved) {
      list.removeWhere((e) => e["id"] == widget.anime["id"]);
    } else {
      list.add(widget.anime);
    }

    await saveWatch(list);
    setState(() => saved = !saved);
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.anime;

    return Scaffold(
      appBar: AppBar(
        title: Text(a["title"]),
        actions: [
          IconButton(
            icon: Icon(saved ? Icons.bookmark : Icons.bookmark_border),
            onPressed: toggle,
          )
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Image.network(a["img"]),
          const SizedBox(height: 10),

          // 🔥 Episode Selector (basic)
          const Text("Episodes (sample)"),
          Wrap(
            spacing: 8,
            children: List.generate(
              12,
              (i) => OutlinedButton(
                onPressed: () {
                  openUrl("https://www.google.com/search?q=${a["title"]}+episode+${i + 1}");
                },
                child: Text("${i + 1}"),
              ),
            ),
          ),

          const SizedBox(height: 12),

          ElevatedButton(
            onPressed: () => openUrl("https://anilist.co/anime/${a["id"]}"),
            child: const Text("Open More Info"),
          ),
        ],
      ),
    );
  }
}
