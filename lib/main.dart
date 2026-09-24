import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

const base = "https://api.aniapi.com/v1";

// 🔥 API CALL
Future<dynamic> api(String path) async {
  final res = await http.get(
    Uri.parse("$base$path"),
    headers: {
      "Accept": "application/json",
    },
  );

  if (res.statusCode != 200) {
    throw Exception("Error ${res.statusCode}");
  }

  return jsonDecode(res.body);
}

// 🔥 Convert data
Map<String, dynamic> item(dynamic a) => {
      "id": a["id"],
      "title": a["titles"]?["en"] ??
          a["titles"]?["jp"] ??
          "No Title",
      "img": a["cover_image"],
    };

Future<void> openUrl(String? url) async {
  if (url == null) return;
  final uri = Uri.parse(url);
  if (await canLaunchUrl(uri)) {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

void main() {
  runApp(const MyApp());
}

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
    ];

    return Scaffold(
      appBar: AppBar(title: const Text("Anime Hub")),
      body: pages[tab],
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (i) => setState(() => tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home), label: "Browse"),
          NavigationDestination(icon: Icon(Icons.search), label: "Search"),
        ],
      ),
    );
  }
}

// 🔥 BROWSE
class BrowseTab extends StatelessWidget {
  const BrowseTab({super.key});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: api("/anime?per_page=12"),
      builder: (c, s) {
        if (s.hasError) return Center(child: Text("Error"));
        if (!s.hasData) return const Center(child: CircularProgressIndicator());

        final list =
            (s.data["data"]["documents"] as List).map(item).toList();

        return Grid(list);
      },
    );
  }
}

// 🔥 SEARCH
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
                    if (s.hasError) return Center(child: Text("Error"));
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

// 🔥 GRID UI
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
            MaterialPageRoute(builder: (_) => Detail(m["id"])),
          ),
          child: Card(
            child: Column(
              children: [
                Expanded(
                  child: Image.network(
                    m["img"],
                    fit: BoxFit.cover,
                  ),
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

// 🔥 DETAIL PAGE
class Detail extends StatelessWidget {
  final int id;
  const Detail(this.id, {super.key});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: api("/anime/$id"),
      builder: (c, s) {
        if (s.hasError) return Scaffold(body: Center(child: Text("Error")));
        if (!s.hasData) {
          return const Scaffold(
              body: Center(child: CircularProgressIndicator()));
        }

        final a = s.data["data"];

        final title = a["titles"]?["en"] ??
            a["titles"]?["jp"] ??
            "No Title";

        final desc = a["descriptions"]?["en"] ?? "No description";

        final links = (a["sources"] as List?) ?? [];

        return Scaffold(
          appBar: AppBar(title: Text(title)),
          body: ListView(
            padding: const EdgeInsets.all(12),
            children: [
              Image.network(a["cover_image"]),
              const SizedBox(height: 10),
              Text(desc),
              const SizedBox(height: 12),

              // 🔥 STREAM / LINKS
              if (links.isNotEmpty) ...[
                const Text("Watch / Sources"),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: links
                      .map<Widget>((x) => OutlinedButton(
                            onPressed: () => openUrl(x["url"]),
                            child: Text(x["name"] ?? "Open"),
                          ))
                      .toList(),
                )
              ]
            ],
          ),
        );
      },
    );
  }
}
