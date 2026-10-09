import 'package:flutter/material.dart';

/// LayoutBuilder can register fields out of order; use their screen positions.
FormFieldState<Object?> firstInvalidFormField(
  Set<FormFieldState<Object?>> invalid,
) {
  Offset position(FormFieldState<Object?> field) {
    final renderObject = field.context.findRenderObject();
    return renderObject is RenderBox && renderObject.hasSize
        ? renderObject.localToGlobal(Offset.zero)
        : const Offset(double.infinity, double.infinity);
  }

  final fields = invalid.toList()
    ..sort((left, right) {
      final a = position(left);
      final b = position(right);
      final vertical = a.dy.compareTo(b.dy);
      return vertical == 0 ? a.dx.compareTo(b.dx) : vertical;
    });
  return fields.first;
}
