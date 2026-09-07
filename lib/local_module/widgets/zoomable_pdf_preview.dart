import 'package:flutter/material.dart';

class ZoomablePdfPreview extends StatefulWidget {
  final Widget child;

  const ZoomablePdfPreview({super.key, required this.child});

  @override
  State<ZoomablePdfPreview> createState() => _ZoomablePdfPreviewState();
}

class _ZoomablePdfPreviewState extends State<ZoomablePdfPreview> with SingleTickerProviderStateMixin {
  final TransformationController _transformationController = TransformationController();
  late AnimationController _animationController;
  Animation<Matrix4>? _zoomAnimation;
  bool _canScroll = true;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    )..addListener(() {
        if (_zoomAnimation != null) {
          _transformationController.value = _zoomAnimation!.value;
        }
      });
  }

  @override
  void dispose() {
    _transformationController.dispose();
    _animationController.dispose();
    super.dispose();
  }

  void _runAnimation(Matrix4 targetValue) {
    _zoomAnimation = Matrix4Tween(
      begin: _transformationController.value,
      end: targetValue,
    ).animate(CurvedAnimation(parent: _animationController, curve: Curves.easeOut));
    
    _animationController.reset();
    _animationController.forward();
  }

  void _handleDoubleTap() {
    if (_animationController.isAnimating) return;
    
    final currentMatrix = _transformationController.value;
    final currentScale = currentMatrix.getMaxScaleOnAxis();

    if (currentScale > 1.05) {
      // Zoom out to normal scale (1.0)
      _runAnimation(Matrix4.identity());
      setState(() {
        _canScroll = true;
      });
    } else {
      // Zoom in to 2.0x scale
      final newMatrix = Matrix4.diagonal3Values(2.0, 2.0, 1.0);
      _runAnimation(newMatrix);
      setState(() {
        _canScroll = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onDoubleTap: _handleDoubleTap,
      child: InteractiveViewer(
        transformationController: _transformationController,
        minScale: 1.0,
        maxScale: 4.0,
        panEnabled: !_canScroll, // Only allow panning when zoomed in
        scaleEnabled: true,
        onInteractionUpdate: (details) {
          final scale = _transformationController.value.getMaxScaleOnAxis();
          if (scale > 1.05 && _canScroll) {
            setState(() {
              _canScroll = false;
            });
          } else if (scale <= 1.05 && !_canScroll) {
            setState(() {
              _canScroll = true;
            });
          }
        },
        onInteractionEnd: (details) {
          final scale = _transformationController.value.getMaxScaleOnAxis();
          if (scale < 1.05 && !_canScroll) {
            // Snap back to 1.0x if very close to it
            _runAnimation(Matrix4.identity());
            setState(() {
              _canScroll = true;
            });
          }
        },
        child: IgnorePointer(
          ignoring: !_canScroll,
          child: widget.child,
        ),
      ),
    );
  }
}
