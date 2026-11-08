import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Printable editing shortcuts must never steal C/V/G/Space from text fields.
class EditorShortcuts extends StatelessWidget {
  final Map<ShortcutActivator, VoidCallback> bindings;
  final Widget child;
  const EditorShortcuts({
    super.key,
    required this.bindings,
    required this.child,
  });
  @override
  Widget build(BuildContext context) => Focus(
    onKeyEvent: (node, event) {
      final focused = FocusManager.instance.primaryFocus?.context;
      if (focused?.widget is EditableText ||
          focused?.findAncestorStateOfType<EditableTextState>() != null) {
        return KeyEventResult.ignored;
      }
      for (final binding in bindings.entries) {
        if (binding.key.accepts(event, HardwareKeyboard.instance)) {
          binding.value();
          return KeyEventResult.handled;
        }
      }
      return KeyEventResult.ignored;
    },
    child: child,
  );
}
