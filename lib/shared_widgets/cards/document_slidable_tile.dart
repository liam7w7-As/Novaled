import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme/app_colors.dart';

class SlidableActionItem {
  final IconData? icon;
  final Widget? customIcon;
  final String label;
  final Color? color;
  final VoidCallback onTap;

  const SlidableActionItem({
    this.icon,
    this.customIcon,
    required this.label,
    this.color,
    required this.onTap,
  });
}

class DocumentSlidableTile extends StatefulWidget {
  final String title;
  final String? subtitle;
  final int displayId;
  final String monto;
  final String fecha;
  final String? vendedor;
  final String? sucursal;
  final Widget? statusWidget;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final List<SlidableActionItem> actions;

  const DocumentSlidableTile({
    super.key,
    required this.title,
    this.subtitle,
    required this.displayId,
    required this.monto,
    required this.fecha,
    this.vendedor,
    this.sucursal,
    this.statusWidget,
    required this.onTap,
    this.onLongPress,
    this.actions = const [],
  });

  @override
  State<DocumentSlidableTile> createState() => _DocumentSlidableTileState();
}

class _DocumentSlidableTileState extends State<DocumentSlidableTile> with SingleTickerProviderStateMixin {
  double _offset = 0;
  late double _maxOffset;

  @override
  void initState() {
    super.initState();
    _maxOffset = -(widget.actions.length * 72.0);
  }

  @override
  void didUpdateWidget(covariant DocumentSlidableTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    _maxOffset = -(widget.actions.length * 72.0);
  }

  Widget _buildBadge({
    required Widget icon,
    required String label,
    bool isDarkBadge = false,
    required bool isDark,
  }) {
    final badgeBg = isDark ? const Color(0xFF262A34) : const Color(0xFFF3F6FB);
    final badgeBorder = isDark ? Colors.white12 : const Color(0xFFE2E8F0);
    final badgeText = isDark ? Colors.white70 : AppColors.textSecondary(isDark);

    final darkBadgeBg = isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0);
    final darkBadgeText = isDark ? Colors.white : const Color(0xFF334155);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
      decoration: BoxDecoration(
        color: isDarkBadge ? darkBadgeBg : badgeBg,
        borderRadius: BorderRadius.circular(999),
        border: isDarkBadge ? null : Border.all(color: badgeBorder, width: 0.8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          icon,
          if (icon is! SizedBox) const SizedBox(width: 4),
          Text(
            label,
            style: GoogleFonts.poppins(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: isDarkBadge ? darkBadgeText : badgeText,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      margin: EdgeInsets.zero,
      child: Stack(
        children: [
          if (_offset != 0 && widget.actions.isNotEmpty)
            Positioned.fill(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: [
                      Color(0xFF8B7CF8),
                      Color(0xFF6C57F6),
                      AppColors.primaryPurple,
                      Color(0xFF4330C8),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(22),
                ),
                clipBehavior: Clip.antiAlias,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: widget.actions.map((action) {
                    return InkWell(
                      onTap: () {
                        setState(() => _offset = 0);
                        action.onTap();
                      },
                      child: Container(
                        width: 72,
                        alignment: Alignment.center,
                        color: action.color ?? Colors.transparent,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            action.customIcon ??
                                Icon(action.icon ?? Icons.more_horiz, color: Colors.white, size: 22),
                            const SizedBox(height: 4),
                            Text(
                              action.label,
                              textAlign: TextAlign.center,
                              style: GoogleFonts.poppins(
                                color: Colors.white,
                                fontWeight: FontWeight.w500,
                                fontSize: 9,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
          GestureDetector(
            onHorizontalDragUpdate: widget.actions.isEmpty
                ? null
                : (details) {
                    setState(() {
                      _offset += details.primaryDelta!;
                      if (_offset < _maxOffset) _offset = _maxOffset;
                      if (_offset > 0) _offset = 0;
                    });
                  },
            onHorizontalDragEnd: widget.actions.isEmpty
                ? null
                : (details) {
                    setState(() {
                      if (_offset < _maxOffset / 2) {
                        _offset = _maxOffset;
                      } else {
                        _offset = 0;
                      }
                    });
                  },
            child: Transform.translate(
              offset: Offset(_offset, 0),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.card(isDark),
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(
                    color: AppColors.border(isDark),
                    width: 0.8,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: isDark ? Colors.black.withValues(alpha: 0.3) : const Color(0x0A000000),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Material(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(22),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(22),
                    onTap: widget.onTap,
                    onLongPress: widget.onLongPress,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            widget.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.poppins(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary(isDark),
                            ),
                          ),
                          if (widget.subtitle != null && widget.subtitle!.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              widget.subtitle!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.poppins(
                                fontSize: 12,
                                color: AppColors.textSecondary(isDark),
                              ),
                            ),
                          ],
                          const SizedBox(height: 10),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Expanded(
                                child: SingleChildScrollView(
                                  scrollDirection: Axis.horizontal,
                                  physics: const BouncingScrollPhysics(),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      // 1. #ID Badge
                                      _buildBadge(
                                        icon: const SizedBox.shrink(),
                                        label: "#${widget.displayId}",
                                        isDarkBadge: true,
                                        isDark: isDark,
                                      ),
                                      const SizedBox(width: 6),
                                      // 2. Amount Badge
                                      _buildBadge(
                                        icon: Icon(
                                          Icons.attach_money_rounded,
                                          size: 13,
                                          color: AppColors.textSecondary(isDark),
                                        ),
                                        label: widget.monto,
                                        isDark: isDark,
                                      ),
                                      const SizedBox(width: 6),
                                      // 3. Date Badge
                                      _buildBadge(
                                        icon: Icon(
                                          Icons.calendar_today_outlined,
                                          size: 12,
                                          color: AppColors.textSecondary(isDark),
                                        ),
                                        label: widget.fecha,
                                        isDark: isDark,
                                      ),
                                      if (widget.vendedor != null && widget.vendedor!.isNotEmpty) ...[
                                        const SizedBox(width: 6),
                                        _buildBadge(
                                          icon: Icon(
                                            Icons.person_outline_rounded,
                                            size: 13,
                                            color: AppColors.textSecondary(isDark),
                                          ),
                                          label: widget.vendedor!,
                                          isDark: isDark,
                                        ),
                                      ],
                                      if (widget.sucursal != null && widget.sucursal!.isNotEmpty) ...[
                                        const SizedBox(width: 6),
                                        _buildBadge(
                                          icon: Icon(
                                            Icons.storefront_outlined,
                                            size: 13,
                                            color: AppColors.textSecondary(isDark),
                                          ),
                                          label: widget.sucursal!,
                                          isDark: isDark,
                                        ),
                                      ],
                                      if (widget.statusWidget != null) ...[
                                        const SizedBox(width: 6),
                                        widget.statusWidget!,
                                      ],
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Icon(
                                Icons.chevron_right_rounded,
                                size: 22,
                                color: isDark ? Colors.white38 : AppColors.textSecondary(isDark),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
