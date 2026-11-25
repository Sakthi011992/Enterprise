import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/auth/session_controller.dart';

final _featuredProvider = FutureProvider<List<Map>>((ref) async {
  final res = await ref.watch(dioProvider).get('/kiosk/featured', queryParameters: {'storeId': 'default'});
  return (res.data as List).cast<Map>();
});

class KioskDisplayScreen extends ConsumerStatefulWidget {
  const KioskDisplayScreen({super.key});
  @override
  ConsumerState<KioskDisplayScreen> createState() => _KioskDisplayScreenState();
}

class _KioskDisplayScreenState extends ConsumerState<KioskDisplayScreen> {
  final _controller = PageController();
  Timer? _timer;
  int _page = 0;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 8), (_) {
      final featured = ref.read(_featuredProvider).valueOrNull;
      if (featured == null || featured.isEmpty) return;
      final next = (_page + 1) % featured.length;
      _controller.animateToPage(next,
          duration: const Duration(milliseconds: 600), curve: Curves.easeInOut);
      setState(() => _page = next);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _logout() async {
    await ref.read(sessionProvider.notifier).logout();
    if (mounted) context.go('/login');
  }

  @override
  Widget build(BuildContext context) {
    final featured = ref.watch(_featuredProvider);
    final t = context.tokens;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          featured.when(
            loading: () => const Center(child: CircularProgressIndicator(color: Colors.white)),
            error: (e, _) => Center(
                child: Text('Error: $e', style: const TextStyle(color: Colors.white))),
            data: (items) => items.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.restaurant_menu, size: 80, color: Colors.white54),
                        const SizedBox(height: 24),
                        Text("Today's Specials",
                            style: Theme.of(context).textTheme.headlineLarge?.copyWith(color: Colors.white)),
                        const SizedBox(height: 8),
                        const Text('Check back soon for featured items!',
                            style: TextStyle(color: Colors.white54)),
                      ],
                    ),
                  )
                : PageView.builder(
                    controller: _controller,
                    itemCount: items.length,
                    onPageChanged: (i) => setState(() => _page = i),
                    itemBuilder: (_, i) => _FeaturedSlide(item: items[i]),
                  ),
          ),
          // Top overlay: title + page indicator
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.fromLTRB(32, 48, 32, 16),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.black87, Colors.transparent],
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    "Today's Specials",
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  featured.when(
                    loading: () => const SizedBox.shrink(),
                    error: (_, __) => const SizedBox.shrink(),
                    data: (items) => items.length > 1
                        ? Row(
                            children: List.generate(
                              items.length,
                              (i) => AnimatedContainer(
                                duration: const Duration(milliseconds: 300),
                                margin: const EdgeInsets.symmetric(horizontal: 4),
                                width: i == _page ? 20 : 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(4),
                                  color: i == _page ? Colors.white : Colors.white38,
                                ),
                              ),
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),
                ],
              ),
            ),
          ),
          // Bottom-right logout
          Positioned(
            bottom: 24,
            right: 24,
            child: TextButton.icon(
              onPressed: _logout,
              icon: const Icon(Icons.logout, color: Colors.white38, size: 16),
              label: const Text('Exit', style: TextStyle(color: Colors.white38)),
            ),
          ),
        ],
      ),
    );
  }
}

class _FeaturedSlide extends StatelessWidget {
  const _FeaturedSlide({required this.item});
  final Map item;

  @override
  Widget build(BuildContext context) {
    final product = item['product'] as Map? ?? {};
    final imageUrl = product['imageUrl'] as String?;
    final label = item['label']?.toString() ?? product['name']?.toString() ?? '';
    final price = product['price'];

    return Stack(
      fit: StackFit.expand,
      children: [
        // Background image / placeholder
        if (imageUrl != null)
          Image.network(imageUrl, fit: BoxFit.cover)
        else
          Container(
            color: Colors.grey.shade900,
            child: const Icon(Icons.restaurant, size: 120, color: Colors.white10),
          ),
        // Bottom gradient + text
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: Container(
            padding: const EdgeInsets.fromLTRB(40, 60, 40, 60),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [Colors.black87, Colors.transparent],
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 48,
                    fontWeight: FontWeight.bold,
                    height: 1.1,
                  ),
                ),
                if (price != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    '₹$price',
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 32,
                    ),
                  ),
                ],
                if (product['description'] != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    product['description'] as String,
                    style: const TextStyle(color: Colors.white54, fontSize: 20),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}
