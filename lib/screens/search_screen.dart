import 'dart:async';
import 'package:flutter/material.dart';
import '../models/product.dart';
import '../services/api_service.dart';
import '../services/search_history_service.dart';
import '../widgets/product_card.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final ApiService _api = ApiService();
  final SearchHistoryService _history = SearchHistoryService();
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  Timer? _debounce;

  SearchSuggestions? _suggestions;
  List<Product> _results = [];
  int _total = 0;
  bool _loading = false;
  bool _searched = false;
  String _activeQuery = '';

  @override
  void initState() {
    super.initState();
    _history.load().then((_) => setState(() {}));
    _focusNode.requestFocus();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    final query = value.trim();
    _debounce?.cancel();

    if (query.isEmpty) {
      setState(() {
        _suggestions = null;
        _results = [];
        _searched = false;
        _activeQuery = '';
      });
      return;
    }

    _debounce = Timer(const Duration(milliseconds: 300), () {
      _loadSuggestions(query);
    });
  }

  Future<void> _loadSuggestions(String query) async {
    try {
      final suggestions = await _api.getSearchSuggestions(query);
      if (_controller.text.trim() == query) {
        setState(() => _suggestions = suggestions);
      }
    } catch (_) {}
  }

  Future<void> _executeSearch(String query) async {
    if (query.trim().isEmpty) return;
    _focusNode.unfocus();
    _history.add(query);

    setState(() {
      _loading = true;
      _searched = true;
      _activeQuery = query;
      _suggestions = null;
      _controller.text = query;
      _controller.selection = TextSelection.fromPosition(TextPosition(offset: query.length));
    });

    try {
      final response = await _api.searchProducts(query, limit: 100);
      setState(() {
        _results = response.products;
        _total = response.total;
        _loading = false;
      });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  void _clearSearch() {
    _controller.clear();
    setState(() {
      _suggestions = null;
      _results = [];
      _searched = false;
      _activeQuery = '';
    });
    _focusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(70),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 16, 8),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () => Navigator.pop(context),
                ),
                Expanded(
                  child: TextField(
                    controller: _controller,
                    focusNode: _focusNode,
                    onChanged: _onChanged,
                    onSubmitted: _executeSearch,
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                      hintText: 'Search products, brands, categories...',
                      hintStyle: TextStyle(color: Colors.grey[400], fontSize: 15),
                      prefixIcon: const Icon(Icons.search, size: 22),
                      suffixIcon: _controller.text.isNotEmpty
                          ? IconButton(icon: Icon(Icons.close, color: Colors.grey[500]), onPressed: _clearSearch)
                          : null,
                      filled: true,
                      fillColor: Colors.white,
                      contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: Colors.grey[300]!)),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Colors.blue, width: 2)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    // Show results
    if (_searched) return _buildResults();

    // Show suggestions dropdown
    if (_suggestions != null && !_suggestions!.isEmpty) return _buildSuggestions();

    // Show recent searches + popular
    return _buildIdleState();
  }

  Widget _buildIdleState() {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      children: [
        // Recent searches
        if (_history.history.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Recent searches', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                GestureDetector(
                  onTap: () async { await _history.clear(); setState(() {}); },
                  child: Text('Clear all', style: TextStyle(fontSize: 13, color: Colors.grey[500])),
                ),
              ],
            ),
          ),
          ..._history.history.map((query) => _recentTile(query)),
        ],

        // Trending / popular
        const Padding(
          padding: EdgeInsets.only(top: 20, bottom: 12),
          child: Text('Popular searches', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _trendingChip('Milk'),
            _trendingChip('Rice'),
            _trendingChip('Atta'),
            _trendingChip('Oil'),
            _trendingChip('Tea'),
            _trendingChip('Sugar'),
            _trendingChip('Salt'),
            _trendingChip('Biscuits'),
            _trendingChip('Dal'),
            _trendingChip('Coffee'),
            _trendingChip('Ghee'),
            _trendingChip('Soap'),
          ],
        ),
      ],
    );
  }

  Widget _recentTile(String query) {
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: Icon(Icons.history, size: 20, color: Colors.grey[400]),
      title: Text(query, style: const TextStyle(fontSize: 14)),
      trailing: IconButton(
        icon: Icon(Icons.close, size: 16, color: Colors.grey[400]),
        onPressed: () async { await _history.remove(query); setState(() {}); },
      ),
      onTap: () => _executeSearch(query),
    );
  }

  Widget _trendingChip(String label) {
    return ActionChip(
      label: Text(label),
      labelStyle: TextStyle(fontSize: 13, color: Colors.grey[700]),
      backgroundColor: Colors.white,
      side: BorderSide(color: Colors.grey[300]!),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      onPressed: () => _executeSearch(label),
    );
  }

  Widget _buildSuggestions() {
    final s = _suggestions!;
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      children: [
        // Product name suggestions
        ...s.names.map((name) => _suggestionTile(
          icon: Icons.search,
          text: name,
          onTap: () => _executeSearch(name),
        )),

        // Brand suggestions
        if (s.brands.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 4),
            child: Text('Brands', style: TextStyle(fontSize: 12, color: Colors.grey[500], fontWeight: FontWeight.w600)),
          ),
          ...s.brands.map((brand) => _suggestionTile(
            icon: Icons.storefront,
            text: brand,
            subtitle: 'Brand',
            onTap: () => _executeSearch(brand),
          )),
        ],

        // Category suggestions
        if (s.categories.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 4),
            child: Text('Categories', style: TextStyle(fontSize: 12, color: Colors.grey[500], fontWeight: FontWeight.w600)),
          ),
          ...s.categories.map((cat) => _suggestionTile(
            icon: Icons.category,
            text: cat,
            subtitle: 'Category',
            onTap: () => _executeSearch(cat),
          )),
        ],
      ],
    );
  }

  Widget _suggestionTile({
    required IconData icon,
    required String text,
    String? subtitle,
    required VoidCallback onTap,
  }) {
    final query = _controller.text.trim().toLowerCase();
    final matchStart = text.toLowerCase().indexOf(query);

    Widget titleWidget;
    if (matchStart >= 0 && query.isNotEmpty) {
      titleWidget = RichText(
        text: TextSpan(
          style: TextStyle(fontSize: 14, color: Colors.grey[800]),
          children: [
            TextSpan(text: text.substring(0, matchStart)),
            TextSpan(text: text.substring(matchStart, matchStart + query.length),
                style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black)),
            TextSpan(text: text.substring(matchStart + query.length)),
          ],
        ),
      );
    } else {
      titleWidget = Text(text, style: const TextStyle(fontSize: 14));
    }

    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, size: 20, color: Colors.grey[400]),
      title: titleWidget,
      trailing: subtitle != null
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(8)),
              child: Text(subtitle, style: TextStyle(fontSize: 10, color: Colors.grey[500])),
            )
          : Icon(Icons.north_west, size: 16, color: Colors.grey[400]),
      onTap: onTap,
    );
  }

  Widget _buildResults() {
    if (_loading) return const Center(child: CircularProgressIndicator());

    if (_results.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.search_off, size: 64, color: Colors.grey[300]),
            const SizedBox(height: 16),
            Text('No results for "$_activeQuery"', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Colors.grey[700])),
            const SizedBox(height: 8),
            Text('Try a different spelling or keyword', style: TextStyle(fontSize: 14, color: Colors.grey[500])),
          ]),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Text('$_total results for "$_activeQuery"',
              style: TextStyle(fontSize: 13, color: Colors.grey[600])),
        ),
        Expanded(
          child: LayoutBuilder(builder: (context, constraints) {
            final cols = constraints.maxWidth > 900 ? 4 : constraints.maxWidth > 600 ? 3 : 2;
            return GridView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: _results.length,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: cols, childAspectRatio: 0.72, crossAxisSpacing: 10, mainAxisSpacing: 10),
              itemBuilder: (context, index) => ProductCard(product: _results[index]),
            );
          }),
        ),
      ],
    );
  }
}
