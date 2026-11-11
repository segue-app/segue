import 'package:flutter/material.dart';

/// Perspective matrix rotated around Y (and X): turns a flat panel in 3D.
Matrix4 perspective({double y = 0, double x = 0, double depth = 0.0011}) =>
    Matrix4.identity()
      ..setEntry(3, 2, depth)
      ..rotateY(y)
      ..rotateX(x);
