// Gene - Nov, 28, 2026: In-place re-login dialog triggered on HTTP 401 expiry while preserving local SQLite database, ps_crud queue, and pending_attachments.
import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:signals_flutter/signals_flutter.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/theme/app_theme.dart';
import '../signals/auth_signals.dart';

class ReauthDialog extends StatefulWidget {
  final AuthSignals authSignals;

  const ReauthDialog({super.key, required this.authSignals});

  @override
  State<ReauthDialog> createState() => _ReauthDialogState();
}

class _ReauthDialogState extends State<ReauthDialog> {
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _submitting = false;
  String? _errorText;
  Timer? _cooldownTimer;
  void Function()? _disposeCooldownEffect;
  int _cooldownSeconds = 0;

  @override
  void initState() {
    super.initState();
    _disposeCooldownEffect = effect(() {
      _syncCooldown(widget.authSignals.rateLimitUntil.value);
    });
  }

  void _syncCooldown(DateTime? until) {
    _cooldownTimer?.cancel();
    _cooldownTimer = null;
    if (until == null) {
      if (mounted && _cooldownSeconds != 0) {
        setState(() => _cooldownSeconds = 0);
      }
      return;
    }
    int compute() {
      final diff = until.difference(DateTime.now()).inSeconds;
      return diff > 0 ? diff : 0;
    }

    final initial = compute();
    if (mounted) {
      setState(() => _cooldownSeconds = initial);
    } else {
      _cooldownSeconds = initial;
    }
    if (initial <= 0) {
      widget.authSignals.rateLimitUntil.value = null;
      return;
    }
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      final rem = compute();
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() => _cooldownSeconds = rem);
      if (rem <= 0) {
        timer.cancel();
        _cooldownTimer = null;
        widget.authSignals.rateLimitUntil.value = null;
      }
    });
  }

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    _disposeCooldownEffect?.call();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_cooldownSeconds > 0) return;
    final password = _passwordController.text;
    if (password.isEmpty) {
      setState(() => _errorText = 'Enter your password to resume syncing.');
      return;
    }
    final username =
        widget.authSignals.currentUser.value?.username.trim() ?? '';
    if (username.isEmpty) {
      setState(() => _errorText = 'No active account username available.');
      return;
    }
    setState(() {
      _submitting = true;
      _errorText = null;
    });
    final ok = await widget.authSignals.reauthenticate(
      username: username,
      password: password,
    );
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() {
      _submitting = false;
      _errorText = widget.authSignals.authError.value ??
          'Sign-in failed. Your offline work remains safely stored.';
    });
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.authSignals.currentUser.value;
    final reason = widget.authSignals.reauthReason.value ??
        'Your session expired. Sign in again to upload queued field updates.';

    return AlertDialog(
      key: const ValueKey('reauth_dialog'),
      title: Row(
        children: [
          Icon(
            CupertinoIcons.lock_shield,
            size: 24,
            color: AppTheme.brandInkOf(context),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Session Expired',
              style: context.text.titleLarge,
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(reason, style: context.text.bodyMedium),
            if (user != null) ...[
              const SizedBox(height: 10),
              Text(
                'Account: ${user.username}',
                style: context.text.labelLarge,
              ),
            ],
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('reauth_password_field'),
              controller: _passwordController,
              obscureText: _obscurePassword,
              enabled: !_submitting,
              onSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                labelText: 'Password',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppTheme.radiusInput),
                ),
                suffixIcon: IconButton(
                  tooltip: _obscurePassword ? 'Show password' : 'Hide password',
                  icon: Icon(
                    _obscurePassword
                        ? CupertinoIcons.eye
                        : CupertinoIcons.eye_slash,
                    size: 20,
                  ),
                  onPressed: () =>
                      setState(() => _obscurePassword = !_obscurePassword),
                ),
              ),
            ),
            if (_errorText != null) ...[
              const SizedBox(height: 8),
              Text(
                _errorText!,
                style: context.text.bodySmall!.copyWith(
                  color: AppTheme.dangerInkOf(context),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const ValueKey('reauth_offline_button'),
          onPressed: _submitting
              ? null
              : () {
                  widget.authSignals.clearReauthPrompt();
                  Navigator.of(context).pop(false);
                },
          child: const Text('Work Offline'),
        ),
        FilledButton(
          key: const ValueKey('reauth_submit_button'),
          onPressed: (_submitting || _cooldownSeconds > 0) ? null : _submit,
          child: _submitting
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(
                  _cooldownSeconds > 0
                      ? 'Wait ${_cooldownSeconds}s'
                      : 'Sign In',
                ),
        ),
      ],
    );
  }
}
