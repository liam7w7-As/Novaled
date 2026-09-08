import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme/app_colors.dart';

class UniversalSearchBar extends StatefulWidget {
  final TextEditingController? controller;
  final String hintText;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onFilterPressed;
  final bool showFilterButton;
  final int activeFilterCount;
  final EdgeInsetsGeometry margin;

  const UniversalSearchBar({
    super.key,
    this.controller,
    this.hintText = "Buscar por cliente o #...",
    this.onChanged,
    this.onFilterPressed,
    this.showFilterButton = false,
    this.activeFilterCount = 0,
    this.margin = const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
  });

  @override
  State<UniversalSearchBar> createState() => _UniversalSearchBarState();
}

class _UniversalSearchBarState extends State<UniversalSearchBar> {
  late TextEditingController _ctrl;
  bool _internalController = false;

  @override
  void initState() {
    super.initState();
    if (widget.controller == null) {
      _ctrl = TextEditingController();
      _internalController = true;
    } else {
      _ctrl = widget.controller!;
    }
  }

  @override
  void dispose() {
    if (_internalController) {
      _ctrl.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      margin: widget.margin,
      decoration: BoxDecoration(
        color: AppColors.card(isDark),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.border(isDark),
          width: 0.8,
        ),
        boxShadow: [
          BoxShadow(
            color: isDark ? Colors.black.withValues(alpha: 0.2) : const Color(0x06000000),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          const SizedBox(width: 14),
          const Icon(Icons.search_rounded, color: AppColors.primaryPurple, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: _ctrl,
              onChanged: (val) {
                setState(() {});
                widget.onChanged?.call(val);
              },
              style: GoogleFonts.poppins(
                fontSize: 14,
                color: AppColors.textPrimary(isDark),
              ),
              decoration: InputDecoration(
                hintText: widget.hintText,
                hintStyle: GoogleFonts.poppins(
                  fontSize: 14,
                  color: AppColors.textSecondary(isDark),
                ),
                border: InputBorder.none,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 13),
              ),
            ),
          ),
          if (_ctrl.text.isNotEmpty)
            IconButton(
              icon: Icon(Icons.close_rounded, size: 18, color: AppColors.textSecondary(isDark)),
              onPressed: () {
                _ctrl.clear();
                setState(() {});
                widget.onChanged?.call('');
              },
            ),
          if (widget.showFilterButton) ...[
            Container(
              height: 24,
              width: 1,
              color: AppColors.border(isDark),
            ),
            IconButton(
              icon: Stack(
                clipBehavior: Clip.none,
                children: [
                  const Icon(Icons.tune_rounded, color: AppColors.primaryPurple, size: 20),
                  if (widget.activeFilterCount > 0)
                    Positioned(
                      top: -4,
                      right: -4,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(
                          color: AppColors.stateRedError,
                          shape: BoxShape.circle,
                        ),
                        child: Text(
                          "${widget.activeFilterCount}",
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              onPressed: widget.onFilterPressed,
            ),
          ],
          const SizedBox(width: 6),
        ],
      ),
    );
  }
}
