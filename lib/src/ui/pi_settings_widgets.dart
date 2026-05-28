import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// ── Card wrapper with optional label ─────────────────────────────────────────

class PiCard extends StatelessWidget {
  const PiCard({super.key, required this.child, this.label});

  final Widget child;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (label != null) ...[
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 6),
            child: Text(
              label!,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: cs.primary,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
        ],
        Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: child,
          ),
        ),
      ],
    );
  }
}

// ── Divider inside card ───────────────────────────────────────────────────────

class PiDivider extends StatelessWidget {
  const PiDivider({super.key});

  @override
  Widget build(BuildContext context) {
    return Divider(
      height: 1,
      thickness: 1,
      color:
          Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.5),
    );
  }
}

// ── Text field ────────────────────────────────────────────────────────────────

class PiField extends StatelessWidget {
  const PiField({
    super.key,
    required this.label,
    required this.controller,
    this.enabled = true,
    this.readOnly = false,
    this.hint,
    this.suffix,
    this.keyboard,
    this.formatters,
    this.onChanged,
  });

  final String label;
  final TextEditingController controller;
  final bool enabled;
  final bool readOnly;
  final String? hint;
  final String? suffix;
  final TextInputType? keyboard;
  final List<TextInputFormatter>? formatters;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: TextField(
        controller: controller,
        enabled: enabled,
        readOnly: readOnly,
        keyboardType: keyboard,
        inputFormatters: formatters,
        style: readOnly
            ? TextStyle(color: cs.onSurface.withValues(alpha: 0.6))
            : null,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          suffixText: suffix,
          suffixIcon: readOnly
              ? Tooltip(
                  message: 'Read-only (DHCP)',
                  child: Icon(Icons.lock_outline, size: 16, color: cs.outline),
                )
              : null,
        ),
      ),
    );
  }
}

// ── Error view ────────────────────────────────────────────────────────────────

class PiErrorView extends StatelessWidget {
  const PiErrorView({
    super.key,
    required this.message,
    required this.onRetry,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: cs.error),
            const SizedBox(height: 16),
            Text(message,
                textAlign: TextAlign.center,
                style: TextStyle(color: cs.onSurface)),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
