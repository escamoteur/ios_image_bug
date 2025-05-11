import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:http/http.dart' as http;

/// A sample Flutter app to help debug the issue:
/// "Exception: Image upload failed due to loss of GPU access on iOS Devices on 3.27.1"
/// Related issue: https://github.com/flutter/flutter/issues/161142#issuecomment-2851617663
///
//// added by @escamoteur not sure why this part of adding the assets is needed
/// Setup Instructions:
/// 1. Add `home.png` and `gallery.png` to the `assets/` directory.
/// 2. Update your `pubspec.yaml` to include:
///
/// flutter:
///   assets:
///     - assets/
///     - assets/home.png
///     - assets/gallery.png
///
/// The two screens don't re-fetch images from api if images were already fetched.
/// Use pull to refresh, if needed.
/// Tap a screen for full view.
///
/// **NOTE:**
/// - A log prints when the app fetches images from the API.
/// - The images are not fetched again if they have already been fetched, and the state is maintained.
/// - Unlike in my video, this code uses a 5-column grid to help trigger the potential bug.
class CustomCacheManager {
  static const key = 'customCacheKey';
  static CacheManager instance = CacheManager(
    Config(
      key,
      stalePeriod: const Duration(days: 7),
      maxNrOfCacheObjects: 1000,
      repo: JsonCacheInfoRepository(databaseName: key),
      fileSystem: IOFileSystem(key),
      fileService: HttpFileService(),
    ),
  );
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Debug Unloaded Images Issue',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const MainScreen(),
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});
  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 0;

  final _screens = const [
    ImageGridScreen(isHome: true, key: PageStorageKey('home')),
    ImageGridScreen(isHome: false, key: PageStorageKey('gallery')),
  ];

  void _onItemTapped(int index) {
    setState(() => _selectedIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _selectedIndex, children: _screens),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: _onItemTapped,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
          BottomNavigationBarItem(
            icon: Icon(Icons.photo_library),
            label: 'Gallery',
          ),
        ],
      ),
    );
  }
}

class ImageGridScreen extends StatefulWidget {
  final bool isHome;

  const ImageGridScreen({required this.isHome, super.key});

  @override
  State<ImageGridScreen> createState() => _ImageGridScreenState();
}

class _ImageGridScreenState extends State<ImageGridScreen>
    with AutomaticKeepAliveClientMixin<ImageGridScreen> {
  final List<String> _homeImageUrls = [];
  final List<String> _galleryImageUrls = [];
  int _page = 1;
  bool _isLoading = false;
  final ScrollController _controller = ScrollController();

  @override
  void initState() {
    super.initState();
    _loadImages();
    _controller.addListener(() {
      if (_controller.position.pixels >=
              _controller.position.maxScrollExtent - 200 &&
          !_isLoading) {
        _loadImages();
      }
    });
  }

  Future<void> _loadImages() async {
    if (_isLoading) return;
    setState(() => _isLoading = true);
    print('fetch images from api');
    final String url = 'https://picsum.photos/v2/list?page=$_page&limit=90';
    final response = await http.get(Uri.parse(url));

    if (response.statusCode == 200) {
      final List<dynamic> data = json.decode(response.body);
      final newUrls = data.map((e) => e['download_url'] as String).toList();
      setState(() {
        if (widget.isHome) {
          _homeImageUrls.addAll(newUrls);
        } else {
          _galleryImageUrls.addAll(newUrls);
        }
        _page++;
        _isLoading = false;
      });
    } else {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _onRefresh() async {
    setState(() {
      if (widget.isHome) {
        _homeImageUrls.clear();
      } else {
        _galleryImageUrls.clear();
      }
      _page = 1;
    });
    await _loadImages();
  }

  void _openFullScreen(BuildContext context, String imageUrl) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.black,
      builder: (context) {
        return DraggableScrollableSheet(
          expand: true,
          initialChildSize: 1.0,
          minChildSize: 1.0,
          maxChildSize: 1.0,
          builder: (_, __) {
            return GestureDetector(
              onVerticalDragDown: (_) => Navigator.of(context).pop(),
              child: Container(
                color: Colors.black,
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: InteractiveViewer(
                          child: CachedNetworkImage(
                            cacheManager: CustomCacheManager.instance,
                            key: ValueKey(imageUrl),
                            imageUrl: imageUrl,
                            fit: BoxFit.contain,
                            fadeInDuration: Duration.zero,
                            fadeOutDuration: Duration.zero,
                            placeholder: (context, url) => const Center(
                              child: CircularProgressIndicator(
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  Color(0xFFD6D6D6),
                                ),
                              ),
                            ),
                            errorWidget: (context, url, error) =>
                                const Icon(Icons.error),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Swipe down to close',
                        style: TextStyle(color: Colors.white70, fontSize: 16),
                      ),
                      const SizedBox(height: 32),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final List<String> imageUrls =
        widget.isHome ? _homeImageUrls : _galleryImageUrls;

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _onRefresh,
        child: GridView.builder(
          controller: _controller,
          padding: const EdgeInsets.symmetric(
            vertical: 8,
          ), // Removed lateral padding
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 5,
            crossAxisSpacing: 2,
            mainAxisSpacing: 2,
          ),
          itemCount: imageUrls.length + (_isLoading ? 1 : 0),
          itemBuilder: (context, index) {
            if (index >= imageUrls.length) {
              return const Center(child: CircularProgressIndicator());
            }
            final imageUrl = imageUrls[index];
            return GestureDetector(
              onTap: () => _openFullScreen(context, imageUrl),
              child: CachedNetworkImage(
                cacheManager: CustomCacheManager.instance,
                key: ValueKey(imageUrl),
                imageUrl: imageUrl,
                fit: BoxFit.cover,
                fadeInDuration: Duration.zero,
                fadeOutDuration: Duration.zero,
                memCacheWidth: 300, // Cache images at 300px width
                placeholder: (context, url) => const Center(
                  child: CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(
                      Color(0xFFD6D6D6),
                    ),
                  ),
                ),
                errorWidget: (context, url, error) => const Icon(Icons.error),
              ),
            );
          },
        ),
      ),
    );
  }

  @override
  bool get wantKeepAlive => true;
}
