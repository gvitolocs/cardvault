import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class ArtistSuggestion {
  const ArtistSuggestion({
    required this.name,
    required this.normalizedArtist,
    required this.slug,
    required this.knownCount,
    this.imageUrl = '',
  });

  factory ArtistSuggestion.fromJson(Map<String, dynamic> json) {
    return ArtistSuggestion(
      name: '${json['name'] ?? json['artist'] ?? ''}'.trim(),
      normalizedArtist:
          '${json['normalizedArtist'] ?? json['normalized_artist'] ?? ''}'
              .trim(),
      slug: '${json['slug'] ?? ''}'.trim(),
      knownCount: (json['knownCount'] as num?)?.toInt() ??
          (json['cardCount'] as num?)?.toInt() ??
          (json['known_count'] as num?)?.toInt() ??
          0,
      imageUrl: '${json['imageUrl'] ?? json['profileImageUrl'] ?? ''}'.trim(),
    );
  }

  final String name;
  final String normalizedArtist;
  final String slug;
  final int knownCount;
  final String imageUrl;
}

class ArtistSuggestionField extends StatefulWidget {
  const ArtistSuggestionField({
    super.key,
    required this.controller,
    required this.onChanged,
    required this.onSelected,
    this.enabled = true,
    this.labelText = 'Search artists',
    this.helperText,
    this.fillColor = const Color(0xFF111936),
    this.borderRadius = 14,
    this.suggestionsLimit = 12,
    this.fallbackSuggestions = const [],
    this.onCleared,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final ValueChanged<ArtistSuggestion> onSelected;
  final bool enabled;
  final String labelText;
  final String? helperText;
  final Color fillColor;
  final double borderRadius;
  final int suggestionsLimit;
  final List<ArtistSuggestion> fallbackSuggestions;
  final VoidCallback? onCleared;

  @override
  State<ArtistSuggestionField> createState() => _ArtistSuggestionFieldState();
}

class _ArtistSuggestionFieldState extends State<ArtistSuggestionField> {
  final LayerLink _layerLink = LayerLink();
  final OverlayPortalController _overlayController =
      OverlayPortalController(debugLabel: 'artist-suggestions');
  final GlobalKey _fieldKey = GlobalKey();
  final FocusNode _focusNode = FocusNode();

  Timer? _debounce;
  List<ArtistSuggestion> _suggestions = const [];
  bool _loading = false;
  int _requestId = 0;
  double _overlayWidth = 320;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_syncOverlay);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _focusNode.removeListener(_syncOverlay);
    _focusNode.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant ArtistSuggestionField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled && oldWidget.enabled) {
      _removeOverlay();
    }
  }

  void _onChanged(String value) {
    widget.onChanged(value);
    _scheduleSearch(value);
  }

  void _scheduleSearch(String value) {
    _debounce?.cancel();
    final query = value.trim();
    if (query.isEmpty) {
      setState(() {
        _loading = false;
        _suggestions = const [];
      });
      _removeOverlay();
      return;
    }
    setState(() {
      _loading = true;
      _suggestions = _fallbackMatches(query);
    });
    _syncOverlay();
    _debounce = Timer(const Duration(milliseconds: 220), () {
      _loadSuggestions(query);
    });
  }

  Future<void> _loadSuggestions(String query) async {
    final requestId = ++_requestId;
    try {
      final uri =
          Uri.base.resolve('/api/marketplace-artist-suggestions').replace(
        queryParameters: {
          'q': query,
          'limit': '${widget.suggestionsLimit}',
        },
      );
      final response = await http.get(uri).timeout(const Duration(seconds: 6));
      if (!mounted || requestId != _requestId) {
        return;
      }
      if (response.statusCode >= 400) {
        throw StateError('Artist suggestions failed.');
      }
      final payload = jsonDecode(response.body) as Map<String, dynamic>;
      final suggestions = (payload['artists'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map((row) =>
              ArtistSuggestion.fromJson(Map<String, dynamic>.from(row)))
          .where((artist) =>
              artist.name.isNotEmpty && artist.normalizedArtist.isNotEmpty)
          .toList(growable: false);
      setState(() {
        _suggestions = _mergeSuggestions(
          suggestions,
          _fallbackMatches(query),
        );
        _loading = false;
      });
    } catch (_) {
      if (!mounted || requestId != _requestId) {
        return;
      }
      setState(() {
        _suggestions = _fallbackMatches(query);
        _loading = false;
      });
    }
    _syncOverlay();
  }

  List<ArtistSuggestion> _fallbackMatches(String query) {
    final normalizedQuery = query.trim().toLowerCase();
    if (normalizedQuery.isEmpty) {
      return const [];
    }
    final matches = widget.fallbackSuggestions
        .where((artist) => artist.name.toLowerCase().contains(normalizedQuery))
        .toList(growable: false);
    matches.sort((left, right) {
      final rank = _artistMatchRank(left.name, normalizedQuery)
          .compareTo(_artistMatchRank(right.name, normalizedQuery));
      if (rank != 0) return rank;
      final count = right.knownCount.compareTo(left.knownCount);
      if (count != 0) return count;
      return left.name.compareTo(right.name);
    });
    return matches.take(widget.suggestionsLimit).toList(growable: false);
  }

  List<ArtistSuggestion> _mergeSuggestions(
    List<ArtistSuggestion> primary,
    List<ArtistSuggestion> fallback,
  ) {
    if (fallback.isEmpty) {
      return primary.take(widget.suggestionsLimit).toList(growable: false);
    }
    final seen = <String>{};
    final merged = <ArtistSuggestion>[];
    for (final artist in [...primary, ...fallback]) {
      final key = artist.normalizedArtist.isNotEmpty
          ? artist.normalizedArtist
          : artist.name.toLowerCase();
      if (seen.add(key)) {
        merged.add(artist);
      }
      if (merged.length >= widget.suggestionsLimit) {
        break;
      }
    }
    return merged;
  }

  int _artistMatchRank(String name, String query) {
    final lower = name.toLowerCase();
    if (lower == query) return 0;
    if (lower.startsWith(query)) return 1;
    if (lower.split(RegExp(r'\s+')).any((part) => part.startsWith(query))) {
      return 2;
    }
    return 3;
  }

  void _syncOverlay() {
    if (!mounted) return;
    final hasQuery = widget.controller.text.trim().isNotEmpty;
    final shouldShow = widget.enabled &&
        _focusNode.hasFocus &&
        hasQuery &&
        (_loading || _suggestions.isNotEmpty);
    if (!shouldShow) {
      _removeOverlay();
      return;
    }
    _updateOverlaySize();
    if (!_overlayController.isShowing) {
      _overlayController.show();
    }
  }

  void _updateOverlaySize() {
    final context = _fieldKey.currentContext;
    final box = context?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) {
      return;
    }
    _overlayWidth = box.size.width;
  }

  void _removeOverlay() {
    if (_overlayController.isShowing) {
      _overlayController.hide();
    }
  }

  void _selectSuggestion(ArtistSuggestion suggestion) {
    _debounce?.cancel();
    _requestId++;
    final text = suggestion.name;
    widget.controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
    setState(() {
      _loading = false;
      _suggestions = const [];
    });
    _removeOverlay();
    _focusNode.unfocus();
    widget.onSelected(suggestion);
    widget.onChanged(text);
  }

  Widget _buildOverlay(BuildContext context) {
    return CompositedTransformFollower(
      link: _layerLink,
      showWhenUnlinked: false,
      targetAnchor: Alignment.bottomLeft,
      followerAnchor: Alignment.topLeft,
      offset: const Offset(0, 6),
      child: Align(
        alignment: Alignment.topLeft,
        child: Material(
          color: Colors.transparent,
          child: TextFieldTapRegion(
            child: SizedBox(
              width: _overlayWidth,
              child: _ArtistSuggestionPanel(
                suggestions: _suggestions,
                loading: _loading,
                onSelected: _selectSuggestion,
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasQuery = widget.controller.text.trim().isNotEmpty;
    return CompositedTransformTarget(
      link: _layerLink,
      child: OverlayPortal(
        controller: _overlayController,
        overlayChildBuilder: _buildOverlay,
        child: TextField(
          key: _fieldKey,
          controller: widget.controller,
          focusNode: _focusNode,
          enabled: widget.enabled,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            isDense: true,
            prefixIcon: const Icon(
              Icons.search,
              color: Color(0xFF93A4C8),
            ),
            suffixIcon: _loading
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : hasQuery
                    ? IconButton(
                        tooltip: 'Clear artist search',
                        onPressed: () {
                          widget.controller.clear();
                          setState(() => _suggestions = const []);
                          _removeOverlay();
                          widget.onChanged('');
                          widget.onCleared?.call();
                        },
                        icon: const Icon(
                          Icons.close,
                          color: Color(0xFF93A4C8),
                        ),
                      )
                    : null,
            labelText: widget.labelText,
            helperText: widget.helperText,
            labelStyle: const TextStyle(color: Color(0xFFB8C4E6)),
            helperStyle: const TextStyle(color: Color(0xFF93A4C8)),
            filled: true,
            fillColor: widget.fillColor,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(widget.borderRadius),
              borderSide: BorderSide(
                color: Colors.white.withValues(alpha: 0.08),
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(widget.borderRadius),
              borderSide: BorderSide(
                color: Colors.white.withValues(alpha: 0.08),
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(widget.borderRadius),
              borderSide: const BorderSide(color: Color(0xFFFACC15)),
            ),
          ),
          onChanged: _onChanged,
          onTap: () {
            if (widget.controller.text.trim().isNotEmpty &&
                _suggestions.isEmpty) {
              _scheduleSearch(widget.controller.text);
            } else {
              _syncOverlay();
            }
          },
        ),
      ),
    );
  }
}

class _ArtistSuggestionPanel extends StatelessWidget {
  const _ArtistSuggestionPanel({
    required this.suggestions,
    required this.loading,
    required this.onSelected,
  });

  final List<ArtistSuggestion> suggestions;
  final bool loading;
  final ValueChanged<ArtistSuggestion> onSelected;

  @override
  Widget build(BuildContext context) {
    final height = suggestions.isEmpty ? 58.0 : (suggestions.length * 58.0) + 8;
    return Container(
      constraints: BoxConstraints(maxHeight: height.clamp(58.0, 320.0)),
      decoration: BoxDecoration(
        color: const Color(0xFF0B1020),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.32),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: loading && suggestions.isEmpty
          ? const Center(
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 4),
              shrinkWrap: true,
              itemCount: suggestions.length,
              itemBuilder: (context, index) {
                final suggestion = suggestions[index];
                return InkWell(
                  onTap: () => onSelected(suggestion),
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.brush_outlined,
                          color: Color(0xFFFACC15),
                          size: 18,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            suggestion.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        if (suggestion.knownCount > 0) ...[
                          const SizedBox(width: 8),
                          Text(
                            '${suggestion.knownCount} known',
                            style: const TextStyle(
                              color: Color(0xFF93A4C8),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}
