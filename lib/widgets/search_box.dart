// lib/widgets/search_box.dart
import 'package:flutter/material.dart';
import '../theme/colors.dart';

class SearchBox extends StatefulWidget {
  final TextEditingController controller;
  final bool isSearching;
  final bool enabled;
  final Function(String) onSearch;
  final VoidCallback onCancel;

  const SearchBox({
    super.key,
    required this.controller,
    required this.isSearching,
    required this.enabled,
    required this.onSearch,
    required this.onCancel,
  });

  @override
  State<SearchBox> createState() => _SearchBoxState();
}

class _SearchBoxState extends State<SearchBox> {
  final _focusNode = FocusNode();
  bool _isComposing = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onSearchTextChanged);
  }

  void _onSearchTextChanged() {
    if (_focusNode.hasFocus) {
      setState(() {
        _isComposing = widget.controller.text.isNotEmpty;
      });
    }
  }

  void _handleSubmitted(String value) {
    final trimmedValue = value.trim();
    if (trimmedValue.isNotEmpty) {
      FocusScope.of(context).unfocus();
      widget.onSearch(trimmedValue);
      // Reset _isComposing to ensure the field can be edited again
      setState(() {
        _isComposing = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: TextFormField(
        controller: widget.controller,
        focusNode: _focusNode,
        style: const TextStyle(color: AiTubeColors.onBackground),
        enabled: widget.enabled,
        textInputAction: TextInputAction.search,
        onFieldSubmitted: _handleSubmitted,
        onTapOutside: (_) {
          FocusScope.of(context).unfocus();
        },
        decoration: InputDecoration(
          hintText: 'Explore the interdimensional TV! eg. "Elephants on Mars"',
          hintStyle: const TextStyle(color: AiTubeColors.onSurfaceVariant),
          filled: true,
          fillColor: AiTubeColors.surface,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(24),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 12,
          ),
          suffixIcon: widget.isSearching
              ? IconButton(
                  icon: const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  onPressed: widget.onCancel,
                )
              : IconButton(
                  icon: const Icon(
                    Icons.search,
                    color: AiTubeColors.onSurfaceVariant,
                  ),
                  onPressed: () => _handleSubmitted(widget.controller.text),
                ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _focusNode.dispose();
    widget.controller.removeListener(_onSearchTextChanged);
    super.dispose();
  }
}