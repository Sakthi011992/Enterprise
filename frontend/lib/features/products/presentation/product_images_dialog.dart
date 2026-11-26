// ignore_for_file: avoid_web_libraries_in_flutter

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/config/app_config.dart';
import '../../../core/files/pick_file.dart';
import '../../../core/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/token_ext.dart';

// ---------------------------------------------------------------------------
// Dialog entry point
// ---------------------------------------------------------------------------

class ProductImagesDialog extends ConsumerStatefulWidget {
  const ProductImagesDialog({super.key, required this.productId, required this.productName});
  final String productId;
  final String productName;
  @override
  ConsumerState<ProductImagesDialog> createState() => _ProductImagesDialogState();
}

class _ProductImagesDialogState extends ConsumerState<ProductImagesDialog>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: SizedBox(
        width: 640,
        height: 540,
        child: Column(
          children: [
            AppBar(
              title: Text('Images — ${widget.productName}'),
              automaticallyImplyLeading: false,
              actions: [
                IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
              ],
              bottom: TabBar(
                controller: _tabs,
                tabs: const [
                  Tab(icon: Icon(Icons.photo_library), text: 'Uploaded'),
                  Tab(icon: Icon(Icons.image_search), text: 'Stock Photos'),
                ],
              ),
            ),
            Expanded(
              child: TabBarView(
                controller: _tabs,
                children: [
                  _UploadedTab(productId: widget.productId),
                  _StockSearchTab(productId: widget.productId),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Uploaded images tab
// ---------------------------------------------------------------------------

class _UploadedTab extends ConsumerStatefulWidget {
  const _UploadedTab({required this.productId});
  final String productId;
  @override
  ConsumerState<_UploadedTab> createState() => _UploadedTabState();
}

class _UploadedTabState extends ConsumerState<_UploadedTab> {
  List<Map> _images = [];
  bool _loading = true;
  bool _uploading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res = await ref.read(dioProvider).get('/products/${widget.productId}/images');
      setState(() => _images = (res.data as List).cast<Map>());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickAndUpload() async {
    final file = await pickImageFile();
    if (file == null) return;
    setState(() => _uploading = true);
    try {
      final formData = FormData.fromMap({
        'file': MultipartFile.fromBytes(file.bytes, filename: file.name,
            contentType: DioMediaType.parse(file.mimeType.startsWith('image/') ? file.mimeType : 'image/jpeg')),
      });
      await ref.read(dioProvider).post('/products/${widget.productId}/images/upload', data: formData);
      await _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Upload failed: $e')));
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _setPrimary(String imageId) async {
    try {
      await ref.read(dioProvider).patch('/products/${widget.productId}/images/$imageId/primary');
      await _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
    }
  }

  Future<void> _delete(String imageId) async {
    try {
      await ref.read(dioProvider).delete('/products/${widget.productId}/images/$imageId');
      await _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    if (_loading) return const Center(child: CircularProgressIndicator());
    return Column(
      children: [
        Padding(
          padding: EdgeInsets.all(t.spacing.sm),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text('${_images.length} image(s)', style: Theme.of(context).textTheme.bodySmall),
            if (_uploading)
              const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
            else
              OutlinedButton.icon(
                icon: const Icon(Icons.upload, size: 16),
                label: const Text('Upload'),
                onPressed: _pickAndUpload,
              ),
          ]),
        ),
        Expanded(
          child: _images.isEmpty
              ? Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.image_outlined, size: 48, color: t.color.content.muted),
                    const SizedBox(height: 12),
                    const Text('No images. Upload one or use stock photos.'),
                  ]),
                )
              : GridView.builder(
                  padding: EdgeInsets.all(t.spacing.sm),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                    childAspectRatio: 1,
                  ),
                  itemCount: _images.length,
                  itemBuilder: (_, i) {
                    final img = _images[i];
                    final isPrimary = img['isPrimary'] as bool? ?? false;
                    final blobPath = img['blobPath'] as String;
                    return Stack(
                      fit: StackFit.expand,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.network(
                            '${AppConfig.apiBaseUrl}/product-images/serve/$blobPath',
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(
                              color: t.color.background.surface,
                              child: const Icon(Icons.broken_image),
                            ),
                          ),
                        ),
                        if (isPrimary)
                          Positioned(
                            top: 4,
                            left: 4,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: t.color.background.accent,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text('Primary',
                                  style: TextStyle(color: t.color.content.onAccent, fontSize: 10)),
                            ),
                          ),
                        Positioned(
                          bottom: 4,
                          right: 4,
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            if (!isPrimary)
                              _ImageAction(
                                icon: Icons.star_outline,
                                tooltip: 'Set primary',
                                onTap: () => _setPrimary(img['id'] as String),
                              ),
                            const SizedBox(width: 4),
                            _ImageAction(
                              icon: Icons.delete_outline,
                              tooltip: 'Delete',
                              onTap: () => _delete(img['id'] as String),
                            ),
                          ]),
                        ),
                      ],
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _ImageAction extends StatelessWidget {
  const _ImageAction({required this.icon, required this.tooltip, required this.onTap});
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
              color: t.color.background.inverse.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(4)),
          child: Icon(icon, color: t.color.content.onInverse, size: 16),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Stock search tab
// ---------------------------------------------------------------------------

class _StockSearchTab extends ConsumerStatefulWidget {
  const _StockSearchTab({required this.productId});
  final String productId;
  @override
  ConsumerState<_StockSearchTab> createState() => _StockSearchTabState();
}

class _StockSearchTabState extends ConsumerState<_StockSearchTab> {
  final _query = TextEditingController();
  List<Map> _results = [];
  bool _searching = false;
  bool _attaching = false;

  Future<void> _search() async {
    if (_query.text.trim().isEmpty) return;
    setState(() => _searching = true);
    try {
      final res = await ref.read(dioProvider).get(
        '/product-images/stock-search',
        queryParameters: {'q': _query.text.trim()},
      );
      final data = res.data as Map;
      setState(() => _results = (data['results'] as List? ?? []).cast<Map>());
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Search failed: $e')));
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _attach(Map photo) async {
    setState(() => _attaching = true);
    try {
      await ref.read(dioProvider).post(
        '/products/${widget.productId}/images/stock',
        data: {
          'imageUrl': photo['imageUrl'],
          'downloadLocation': photo['downloadLocation'],
          'photographerName': photo['photographerName'],
          'photographerUrl': photo['photographerUrl'],
          'sourceUrl': photo['sourceUrl'],
        },
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Stock photo added!')));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
    } finally {
      if (mounted) setState(() => _attaching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Column(
      children: [
        Padding(
          padding: EdgeInsets.all(t.spacing.sm),
          child: Row(children: [
            Expanded(
              child: TextField(
                controller: _query,
                decoration: const InputDecoration(hintText: 'Search Unsplash (e.g. pasta, coffee)'),
                onSubmitted: (_) => _search(),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(onPressed: _searching ? null : _search, child: const Text('Search')),
          ]),
        ),
        if (_searching) const LinearProgressIndicator(),
        Expanded(
          child: _results.isEmpty
              ? Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.image_search, size: 48, color: t.color.content.muted),
                    const SizedBox(height: 12),
                    const Text('Search Unsplash for stock photos.'),
                    const SizedBox(height: 4),
                    Text('Photographer credit is saved automatically.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: t.color.content.secondary)),
                  ]),
                )
              : GridView.builder(
                  padding: EdgeInsets.all(t.spacing.sm),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                    childAspectRatio: 1,
                  ),
                  itemCount: _results.length,
                  itemBuilder: (_, i) {
                    final photo = _results[i];
                    return InkWell(
                      onTap: _attaching ? null : () => _attach(photo),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.network(
                              photo['thumbUrl'] as String? ?? '',
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Container(color: context.ext.subtleFill),
                            ),
                          ),
                          Positioned(
                            bottom: 0,
                            left: 0,
                            right: 0,
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: t.color.background.inverse.withValues(alpha: 0.6),
                                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(8)),
                              ),
                              child: Text(
                                '© ${photo['photographerName']}',
                                style: TextStyle(color: t.color.content.onInverse, fontSize: 9),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                          if (_attaching)
                            const Center(child: CircularProgressIndicator()),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
