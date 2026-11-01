/// Settings > About me (`/settings/about-me`): name, what you do, how you like
/// to write, email signature. Saved locally with one button; Ask, Actions and
/// drafts prepend a short "About the user" block built from it
/// (`core/profile/user_profile.dart`). A live preview shows exactly what gets
/// added, so nothing is hidden.
///
/// States: loading (skeleton), error (says the saved details could not be
/// read and still lets the user fill the form), empty (a form with examples as
/// hints), saved (snackbar).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/profile/user_profile.dart';
import '../../../core/theme/dhruva_theme_extension.dart';
import '../widgets/settings_widgets.dart';

class AboutMeScreen extends ConsumerStatefulWidget {
  const AboutMeScreen({super.key});

  @override
  ConsumerState<AboutMeScreen> createState() => _AboutMeScreenState();
}

class _AboutMeScreenState extends ConsumerState<AboutMeScreen> {
  final _name = TextEditingController();
  final _role = TextEditingController();
  final _tone = TextEditingController();
  final _signature = TextEditingController();

  /// What is saved (or, before the first load finishes, empty). Drives the
  /// "unsaved changes" state of the Save button.
  UserProfile _saved = const UserProfile();
  bool _seeded = false;
  bool _seeding = false;

  @override
  void initState() {
    super.initState();
    for (final c in [_name, _role, _tone, _signature]) {
      c.addListener(() {
        if (!_seeding) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _role.dispose();
    _tone.dispose();
    _signature.dispose();
    super.dispose();
  }

  UserProfile get _draft => UserProfile(
    name: _name.text,
    role: _role.text,
    tone: _tone.text,
    signature: _signature.text,
  );

  void _seed(UserProfile p) {
    if (_seeded) return;
    _seeded = true;
    _seeding = true; // no setState while building
    _saved = p;
    _name.text = p.name;
    _role.text = p.role;
    _tone.text = p.tone;
    _signature.text = p.signature;
    _seeding = false;
  }

  Future<void> _save() async {
    final draft = _draft;
    await ref.read(userProfileProvider.notifier).save(draft);
    if (!mounted) return;
    setState(() => _saved = draft);
    FocusScope.of(context).unfocus();
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Saved on this phone.')));
  }

  void _clear() {
    for (final c in [_name, _role, _tone, _signature]) {
      c.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<DhruvaTokens>()!;
    final profile = ref.watch(userProfileProvider);

    Widget body;
    switch (profile) {
      case AsyncData(:final value):
        _seed(value);
        body = _form(theme, tokens);
      case AsyncError():
        _seed(const UserProfile());
        body = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SettingsNote(
              "Couldn't read your saved details. You can fill them in again "
              'and save.',
            ),
            SizedBox(height: tokens.spacing.sm),
            _form(theme, tokens),
          ],
        );
      default:
        body = const _Skeleton(key: ValueKey('about-me-loading'));
    }

    return SettingsPage(
      title: 'About me',
      subtitle:
          'Help drafts and answers sound like you. Stays on this phone and '
          'is only added to your own prompts.',
      children: [body],
    );
  }

  Widget _form(ThemeData theme, DhruvaTokens tokens) {
    final dirty = _draft != _saved;
    final context0 = buildUserContext(_draft);
    final pad = EdgeInsets.symmetric(horizontal: tokens.spacing.base);
    final gap = SizedBox(height: tokens.spacing.base);
    return Padding(
      padding: pad,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            key: const ValueKey('about-me-name'),
            controller: _name,
            maxLength: maxNameChars,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.next,
            autofillHints: const [AutofillHints.name],
            decoration: const InputDecoration(
              labelText: 'Name',
              hintText: 'What should it call you?',
              counterText: '',
            ),
          ),
          gap,
          TextField(
            key: const ValueKey('about-me-role'),
            controller: _role,
            maxLength: maxRoleChars,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: 'What you do',
              hintText: 'For example: nurse, runs a bakery, student',
              counterText: '',
            ),
          ),
          gap,
          Text('How you like to write', style: theme.textTheme.titleSmall),
          SizedBox(height: tokens.spacing.sm),
          Wrap(
            spacing: tokens.spacing.sm,
            children: [
              for (final preset in writingTonePresets)
                ChoiceChip(
                  key: ValueKey('about-me-tone-$preset'),
                  label: Text(preset),
                  selected: _tone.text.trim() == preset,
                  onSelected: (on) => _tone.text = on ? preset : '',
                ),
            ],
          ),
          SizedBox(height: tokens.spacing.sm),
          TextField(
            key: const ValueKey('about-me-tone'),
            controller: _tone,
            maxLength: maxToneChars,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: 'Or describe it',
              hintText: 'For example: friendly, no exclamation marks',
              counterText: '',
            ),
          ),
          gap,
          TextField(
            key: const ValueKey('about-me-signature'),
            controller: _signature,
            maxLength: maxSignatureChars,
            minLines: 3,
            maxLines: 5,
            keyboardType: TextInputType.multiline,
            decoration: const InputDecoration(
              labelText: 'Email signature',
              hintText: 'Thanks,\nAsha',
              alignLabelWithHint: true,
              counterText: '',
            ),
          ),
          gap,
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  key: const ValueKey('about-me-save'),
                  onPressed: dirty ? _save : null,
                  child: const Text('Save'),
                ),
              ),
              SizedBox(width: tokens.spacing.sm),
              TextButton(
                key: const ValueKey('about-me-clear'),
                onPressed: _draft.isEmpty ? null : _clear,
                child: const Text('Clear'),
              ),
            ],
          ),
          if (context0.isNotEmpty) ...[
            SizedBox(height: tokens.spacing.lg),
            Text(
              'What gets added to your prompts',
              style: theme.textTheme.titleSmall,
            ),
            SizedBox(height: tokens.spacing.sm),
            DecoratedBox(
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(tokens.radius.lg),
              ),
              child: Padding(
                padding: EdgeInsets.all(tokens.spacing.base),
                child: Text(
                  context0,
                  key: const ValueKey('about-me-preview'),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Loading placeholder: four field-shaped blocks, no spinner.
class _Skeleton extends StatelessWidget {
  const _Skeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<DhruvaTokens>()!;
    Widget block(double h) => Container(
      height: h,
      margin: EdgeInsets.only(bottom: tokens.spacing.base),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(tokens.radius.sm),
      ),
    );
    return Semantics(
      label: 'Loading your details',
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: tokens.spacing.base),
        child: Column(children: [block(56), block(56), block(56), block(96)]),
      ),
    );
  }
}
