import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/api_service.dart';

/// Attribution for the catalogue photographs that came from open databases.
///
/// Those photographs are published under Creative Commons licences, which
/// permit the reuse but require the source to be credited where the image is
/// shown. This screen is that credit, so it has to hold up even when the
/// phone is offline: the licence statement is part of the app, and only the
/// per-photograph list is fetched.
class ImageCreditsScreen extends StatefulWidget {
  const ImageCreditsScreen({super.key});

  @override
  State<ImageCreditsScreen> createState() => _ImageCreditsScreenState();
}

class _ImageCreditsScreenState extends State<ImageCreditsScreen> {
  late Future<List<ImageCreditSource>> _future;

  @override
  void initState() {
    super.initState();
    _future = ApiService().getImageCredits();
  }

  void _reload() => setState(() => _future = ApiService().getImageCredits());

  Future<void> _open(String url) async {
    if (url.isEmpty) return;
    final ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open $url')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(title: const Text('Photo Credits'), centerTitle: true, elevation: 0),
      body: FutureBuilder<List<ImageCreditSource>>(
        future: _future,
        builder: (context, snapshot) {
          final sources = snapshot.data ?? const <ImageCreditSource>[];

          // Flattened so the list builds lazily — there are a few hundred
          // photographs today and the catalogue only grows.
          final rows = <Object>[const _Intro()];
          for (final s in sources) {
            rows.add(s);
            rows.addAll(s.items);
          }
          if (snapshot.connectionState == ConnectionState.waiting) {
            rows.add(const _Status.loading());
          } else if (snapshot.hasError) {
            rows.add(_Status.failed(_reload));
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: rows.length,
            itemBuilder: (context, i) {
              final row = rows[i];
              if (row is _Intro) return row;
              if (row is _Status) return row;
              if (row is ImageCreditSource) return _sourceHeader(row);
              return _creditTile(row as ImageCredit);
            },
          );
        },
      ),
    );
  }

  Widget _sourceHeader(ImageCreditSource source) {
    return Container(
      margin: const EdgeInsets.only(top: 8, bottom: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.photo_library_outlined, color: Colors.blue[700]),
          const SizedBox(width: 12),
          Expanded(
            child: Text(source.name, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
          ),
        ]),
        const SizedBox(height: 8),
        Text(
          '${source.count} ${source.count == 1 ? "photograph" : "photographs"}'
          '${source.licences.isEmpty ? "" : " · ${source.licences.join(", ")}"}',
          style: TextStyle(fontSize: 13, color: Colors.grey[600]),
        ),
        if (source.url.isNotEmpty) ...[
          const SizedBox(height: 4),
          InkWell(
            onTap: () => _open(source.url),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Text(source.url, style: TextStyle(fontSize: 13, color: Colors.blue[700])),
                const SizedBox(width: 4),
                Icon(Icons.open_in_new, size: 14, color: Colors.blue[700]),
              ]),
            ),
          ),
        ],
      ]),
    );
  }

  Widget _creditTile(ImageCredit credit) {
    final by = credit.creator.isEmpty ? '' : '${credit.creator} · ';
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        dense: true,
        title: Text(credit.product, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
        subtitle: Text('$by${credit.licence}', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
        trailing: credit.url.isEmpty ? null : Icon(Icons.open_in_new, size: 16, color: Colors.grey[400]),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        onTap: credit.url.isEmpty ? null : () => _open(credit.url),
      ),
    );
  }
}

/// The licence statement itself. Deliberately part of the app rather than the
/// API response, so the credit is still shown if the list cannot be loaded.
class _Intro extends StatelessWidget {
  const _Intro();

  @override
  Widget build(BuildContext context) {
    const body =
        'Some of the product photographs in this app were not taken by us. They come '
        'from open databases such as Open Food Facts, where people publish their '
        'photographs under Creative Commons licences that allow anyone to reuse them, '
        'on the condition that the source is credited.\n\n'
        'This page is that credit. Each photograph is listed below with the database '
        'it came from and the licence it is published under.\n\n'
        'The photographs have been resized and recompressed so they load quickly on a '
        'phone. Nothing else about them was changed, and they remain available under '
        'their original licences from the sources listed here.';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
      child: const Text(
        body,
        style: TextStyle(fontSize: 14, height: 1.6, color: Color(0xFF333333)),
      ),
    );
  }
}

/// Loading and failure states for the per-photograph list. The credit above
/// stands on its own, so a failure here is a missing detail, not a missing
/// attribution — say so plainly instead of showing an alarming error.
class _Status extends StatelessWidget {
  final VoidCallback? onRetry;

  const _Status.loading() : onRetry = null;
  const _Status.failed(this.onRetry);

  @override
  Widget build(BuildContext context) {
    if (onRetry == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 32),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
      child: Column(children: [
        Icon(Icons.cloud_off, color: Colors.grey[400], size: 32),
        const SizedBox(height: 12),
        Text(
          'The full list of photographs could not be loaded. Check your connection '
          'and try again.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: Colors.grey[600]),
        ),
        const SizedBox(height: 8),
        TextButton(onPressed: onRetry, child: const Text('Retry')),
      ]),
    );
  }
}
