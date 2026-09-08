import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme/app_colors.dart';
import '../../local_module/models/item_cotizacion.dart';

class SlidableItemCard extends StatefulWidget {
  final ItemCotizacion item;
  final int index;
  final bool isDark;
  final Color? textColor;
  final Color? labelColor;
  final bool isSelected;
  final VoidCallback onSelect;
  final VoidCallback onClose;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onDuplicate;
  final VoidCallback onMove;

  const SlidableItemCard({
    super.key,
    required this.item,
    required this.index,
    required this.isDark,
    this.textColor,
    this.labelColor,
    this.isSelected = false,
    required this.onSelect,
    required this.onClose,
    required this.onEdit,
    required this.onDelete,
    required this.onDuplicate,
    required this.onMove,
  });

  @override
  State<SlidableItemCard> createState() => _SlidableItemCardState();
}

class _SlidableItemCardState extends State<SlidableItemCard> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;
  double _dragExtent = 0.0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );
    _animation = CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic);
    if (widget.isSelected) {
      _controller.value = 1.0;
    }
  }

  @override
  void didUpdateWidget(SlidableItemCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isSelected != oldWidget.isSelected) {
      if (widget.isSelected) {
        _controller.forward();
      } else {
        _controller.reverse();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final effectiveTextColor = widget.textColor ?? AppColors.textPrimary(widget.isDark);
    final effectiveLabelColor = widget.labelColor ?? AppColors.textSecondary(widget.isDark);
    final cantStr = widget.item.cantidad.toString();
    final precioStr = widget.item.articulo.precio.toStringAsFixed(2);
    final subtotalStr = widget.item.total.toStringAsFixed(2);

    return LayoutBuilder(
      builder: (context, constraints) {
        final totalWidth = constraints.maxWidth;
        final actionWidth = (totalWidth * 0.65).clamp(170.0, 230.0);

        void handleDragUpdate(DragUpdateDetails details) {
          setState(() {
            _dragExtent -= details.primaryDelta!;
            if (_dragExtent < 0) _dragExtent = 0;
            if (_dragExtent > actionWidth) _dragExtent = actionWidth;
            _controller.value = _dragExtent / actionWidth;
          });
        }

        void handleDragEnd(DragEndDetails details) {
          if (_dragExtent > actionWidth / 2 || (details.primaryVelocity ?? 0) < -150) {
            _controller.forward();
            _dragExtent = actionWidth;
            widget.onSelect();
          } else {
            _controller.reverse();
            _dragExtent = 0.0;
            widget.onClose();
          }
        }

        return AnimatedBuilder(
          animation: _animation,
          builder: (context, child) {
            final progress = _animation.value;
            final currentOffset = progress * actionWidth;

            return ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Stack(
                clipBehavior: Clip.hardEdge,
                children: [
                  // Fondo de botones de acción
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        color: widget.isDark ? const Color(0xFF161A22) : Colors.white,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Sección Izquierda: Subtotal
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.only(left: 14, right: 6),
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  "Bs. $subtotalStr",
                                  style: GoogleFonts.poppins(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w600,
                                    color: effectiveLabelColor,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                          ),
                          // Sección Derecha: Acciones con gradiente
                          ClipRRect(
                            borderRadius: const BorderRadius.only(
                              topRight: Radius.circular(20),
                              bottomRight: Radius.circular(20),
                            ),
                            child: Container(
                              width: actionWidth,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    Theme.of(context).primaryColor.withOpacity(0.4),
                                    Theme.of(context).primaryColor,
                                  ],
                                  begin: Alignment.centerLeft,
                                  end: Alignment.centerRight,
                                ),
                              ),
                              child: Row(
                                children: [
                                  // 1. Editar
                                  Expanded(
                                    child: InkWell(
                                      onTap: widget.onEdit,
                                      child: Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Image.asset(
                                            'Iconos/Nuevo/nuevo/2/editar.png',
                                            width: 16,
                                            height: 16,
                                            color: Colors.white,
                                            errorBuilder: (context, error, stackTrace) => const Icon(Icons.edit_outlined, color: Colors.white, size: 16),
                                          ),
                                          const SizedBox(height: 2),
                                          Text("Editar", style: GoogleFonts.poppins(fontSize: 9.5, color: Colors.white, fontWeight: FontWeight.w500)),
                                        ],
                                      ),
                                    ),
                                  ),
                                  // 2. Eliminar
                                  Expanded(
                                    child: InkWell(
                                      onTap: widget.onDelete,
                                      child: Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Image.asset(
                                            'Iconos/Nuevo/nuevo/2/borrar4.png',
                                            width: 16,
                                            height: 16,
                                            color: Colors.white,
                                            errorBuilder: (context, error, stackTrace) => const Icon(Icons.delete_outline, color: Colors.white, size: 16),
                                          ),
                                          const SizedBox(height: 2),
                                          Text("Eliminar", style: GoogleFonts.poppins(fontSize: 9.5, color: Colors.white, fontWeight: FontWeight.w500)),
                                        ],
                                      ),
                                    ),
                                  ),
                                  // 3. Duplicar
                                  Expanded(
                                    child: InkWell(
                                      onTap: widget.onDuplicate,
                                      child: Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Image.asset(
                                            'Iconos/Nuevo/nuevo/2/copia.png',
                                            width: 16,
                                            height: 16,
                                            color: Colors.white,
                                            errorBuilder: (context, error, stackTrace) => const Icon(Icons.copy_rounded, color: Colors.white, size: 16),
                                          ),
                                          const SizedBox(height: 2),
                                          Text("Duplicar", style: GoogleFonts.poppins(fontSize: 9.5, color: Colors.white, fontWeight: FontWeight.w500)),
                                        ],
                                      ),
                                    ),
                                  ),
                                  // 4. Mover
                                  Expanded(
                                    child: InkWell(
                                      onTap: widget.onMove,
                                      child: Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Image.asset(
                                            'Iconos/Nuevo/nuevo/2/mover.png',
                                            width: 16,
                                            height: 16,
                                            color: Colors.white,
                                            errorBuilder: (context, error, stackTrace) => const Icon(Icons.open_with_rounded, color: Colors.white, size: 16),
                                          ),
                                          const SizedBox(height: 2),
                                          Text("Mover", style: GoogleFonts.poppins(fontSize: 9.5, color: Colors.white, fontWeight: FontWeight.w500)),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Tarjeta Frontal Deslizable
                  Transform.translate(
                    offset: Offset(-currentOffset, 0),
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onHorizontalDragUpdate: handleDragUpdate,
                      onHorizontalDragEnd: handleDragEnd,
                      onTap: () {
                        if (progress > 0.5) {
                          _controller.reverse();
                          _dragExtent = 0.0;
                          widget.onClose();
                        } else {
                          _controller.forward();
                          _dragExtent = actionWidth;
                          widget.onSelect();
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          color: widget.isDark ? const Color(0xFF161A22) : Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(widget.isDark ? 0.2 : 0.04),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: Theme.of(context).primaryColor,
                                shape: BoxShape.circle,
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                "${widget.index + 1}",
                                style: GoogleFonts.poppins(
                                  color: Theme.of(context).primaryColor.computeLuminance() > 0.5 ? Colors.black87 : Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14.5,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    widget.item.articulo.nombre,
                                    style: GoogleFonts.poppins(
                                      fontSize: 14.5,
                                      fontWeight: FontWeight.w600,
                                      color: effectiveTextColor,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    "$cantStr x Bs. $precioStr",
                                    style: GoogleFonts.poppins(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w400,
                                      color: effectiveLabelColor,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              "Bs. $subtotalStr",
                              style: GoogleFonts.poppins(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w600,
                                color: effectiveLabelColor,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Icon(
                              progress > 0.5 ? Icons.chevron_right_rounded : Icons.chevron_left_rounded,
                              color: effectiveLabelColor,
                              size: 20,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
