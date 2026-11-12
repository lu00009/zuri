import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class RecoveryCodeDialog extends StatefulWidget {
  final String recoveryCode;
  final VoidCallback onConfirmed;

  const RecoveryCodeDialog({
    super.key,
    required this.recoveryCode,
    required this.onConfirmed,
  });

  static Future<void> show({
    required BuildContext context,
    required String recoveryCode,
    required VoidCallback onConfirmed,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => RecoveryCodeDialog(
        recoveryCode: recoveryCode,
        onConfirmed: onConfirmed,
      ),
    );
  }

  @override
  State<RecoveryCodeDialog> createState() => _RecoveryCodeDialogState();
}

class _RecoveryCodeDialogState extends State<RecoveryCodeDialog> {
  bool _hasSaved = false;
  bool _hasCopied = false;

  void _copyToClipboard() {
    Clipboard.setData(ClipboardData(text: widget.recoveryCode));
    setState(() {
      _hasCopied = true;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Recovery code copied to clipboard!'),
        backgroundColor: Colors.green,
        duration: Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Please confirm you have saved your recovery code to continue.'),
              backgroundColor: Colors.amber,
            ),
          );
        }
      },
      child: AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
        contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
        actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.vpn_key_outlined, color: theme.colorScheme.primary, size: 24),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Save Your Recovery Code',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Zuri protects your privacy and does not use paid email OTPs. This 16-character code is the ONLY way to recover your account if you ever forget your password.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 16),

                // Recovery Code Card
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: theme.colorScheme.primary.withValues(alpha: 0.4),
                      width: 1.5,
                    ),
                  ),
                  child: Column(
                    children: [
                      Text(
                        widget.recoveryCode,
                        key: const Key('recovery_code_text'),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 2,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                      const SizedBox(height: 10),
                      OutlinedButton.icon(
                        key: const Key('copy_recovery_code_button'),
                        onPressed: _copyToClipboard,
                        icon: Icon(_hasCopied ? Icons.check : Icons.copy_rounded, size: 16),
                        label: Text(_hasCopied ? 'Copied!' : 'Copy Code'),
                        style: OutlinedButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Warning Banner
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.amber.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.amber.withValues(alpha: 0.4)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.warning_amber_rounded, color: Colors.amber, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Store this code in a password manager or secure notes. It will NOT be shown again.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: isDark ? const Color(0xFFFDE68A) : const Color(0xFF92400E),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Confirmation Checkbox
                CheckboxListTile(
                  key: const Key('recovery_code_saved_checkbox'),
                  contentPadding: EdgeInsets.zero,
                  value: _hasSaved,
                  onChanged: (val) {
                    setState(() {
                      _hasSaved = val ?? false;
                    });
                  },
                  title: Text(
                    'I have safely saved my recovery code',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  controlAffinity: ListTileControlAffinity.leading,
                ),
              ],
            ),
          ),
        ),
        actions: [
          FilledButton(
            key: const Key('recovery_code_continue_button'),
            onPressed: _hasSaved
                ? () {
                    Navigator.of(context).pop();
                    widget.onConfirmed();
                  }
                : null,
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(44),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('I\'ve Saved It, Continue'),
          ),
        ],
      ),
    );
  }
}

