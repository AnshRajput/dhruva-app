/// Create/edit character form (Loop 5). One screen for both modes —
/// `characterId == null` is create, set is edit — since every field maps
/// 1:1 onto `CharacterRepository.createCharacter`/`updateCharacter`.
///
/// Live validation: name + persona are the only required fields (chat-spec.
/// md-adjacent brief's "live validation (name+persona required)") — the Save
/// button is disabled the moment either is empty (controller listeners
/// trigger a rebuild), and a `Form`'s `validate()` is still run on submit as
/// defense-in-depth against a programmatic bypass.
library;

import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../core/theme/dhruva_theme_extension.dart';
import '../../../data/characters/character_repository.dart';
import '../../../data/chat/models/sampling_params.dart';
import '../state/characters_controller.dart';
import '../state/installed_models_provider.dart';
import '../widgets/character_avatar.dart';
import '../widgets/emoji_picker_sheet.dart';
import '../widgets/sampling_editor.dart';

class CharacterFormScreen extends ConsumerStatefulWidget {
  /// Null = create a new character; set = edit that character.
  final int? characterId;
  const CharacterFormScreen({super.key, this.characterId});

  @override
  ConsumerState<CharacterFormScreen> createState() =>
      _CharacterFormScreenState();
}

class _CharacterFormScreenState extends ConsumerState<CharacterFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _personaCtrl = TextEditingController();
  final _greetingCtrl = TextEditingController();
  final List<TextEditingController> _dialogueCtrls = [];

  String? _avatarEmoji;
  String? _avatarPath;
  int? _defaultModelId;
  bool _overrideSampling = false;
  SamplingParams _sampling = const SamplingParams();

  var _loadedExisting = false;
  var _saving = false;

  bool get _isEdit => widget.characterId != null;

  @override
  void initState() {
    super.initState();
    _nameCtrl.addListener(_onRequiredFieldChanged);
    _personaCtrl.addListener(_onRequiredFieldChanged);
  }

  void _onRequiredFieldChanged() => setState(() {});

  bool get _canSave =>
      !_saving &&
      _nameCtrl.text.trim().isNotEmpty &&
      _personaCtrl.text.trim().isNotEmpty;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _personaCtrl.dispose();
    _greetingCtrl.dispose();
    for (final c in _dialogueCtrls) {
      c.dispose();
    }
    super.dispose();
  }

  void _populateFrom(CharacterInfo character) {
    _nameCtrl.text = character.name;
    _personaCtrl.text = character.personaSystemPrompt;
    _greetingCtrl.text = character.greeting ?? '';
    _avatarEmoji = character.avatarEmoji;
    _avatarPath = character.avatarPath;
    _defaultModelId = character.defaultModelId;
    if (character.samplingParams != null) {
      _overrideSampling = true;
      _sampling = character.samplingParams!;
    }
    _dialogueCtrls.addAll(
      character.exampleDialogues.map((d) => TextEditingController(text: d)),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.characterId != null && !_loadedExisting) {
      final asyncCharacter = ref.watch(
        characterByIdProvider(widget.characterId!),
      );
      return asyncCharacter.when(
        data: (character) {
          if (character == null) {
            return Scaffold(
              appBar: AppBar(title: const Text('Character')),
              body: const Center(child: Text('Character not found.')),
            );
          }
          if (character.isBuiltIn) {
            return _BuiltInBlockedView(character: character);
          }
          _populateFrom(character);
          _loadedExisting = true;
          return _buildForm(context);
        },
        loading: () =>
            const Scaffold(body: Center(child: CircularProgressIndicator())),
        error: (error, stack) => Scaffold(
          appBar: AppBar(title: const Text('Character')),
          body: const Center(child: Text('Could not load this character.')),
        ),
      );
    }
    return _buildForm(context);
  }

  Widget _buildForm(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<DhruvaTokens>()!;

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? 'Edit character' : 'New character'),
        actions: [
          TextButton(
            onPressed: _canSave ? _save : null,
            child: const Text('Save'),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: EdgeInsets.all(tokens.spacing.md),
          children: [
            Center(
              child: Column(
                children: [
                  CharacterAvatar(
                    avatarEmoji: _avatarEmoji,
                    avatarPath: _avatarPath,
                    size: 72,
                  ),
                  SizedBox(height: tokens.spacing.sm),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: tokens.spacing.sm,
                    children: [
                      OutlinedButton(
                        onPressed: _pickEmoji,
                        child: const Text('Choose emoji'),
                      ),
                      OutlinedButton(
                        onPressed: _pickImageAvatar,
                        child: const Text('Choose image'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            SizedBox(height: tokens.spacing.lg),
            TextFormField(
              controller: _nameCtrl,
              decoration: const InputDecoration(
                labelText: 'Name',
                hintText: 'e.g. Coach',
              ),
              validator: (value) =>
                  (value == null || value.trim().isEmpty) ? 'Required' : null,
            ),
            SizedBox(height: tokens.spacing.md),
            TextFormField(
              controller: _personaCtrl,
              minLines: 4,
              maxLines: 10,
              decoration: const InputDecoration(
                labelText: 'Persona (system prompt)',
                hintText: 'You are ... Speak in a ... tone. Your goal is ...',
                alignLabelWithHint: true,
              ),
              validator: (value) =>
                  (value == null || value.trim().isEmpty) ? 'Required' : null,
            ),
            SizedBox(height: tokens.spacing.md),
            TextFormField(
              controller: _greetingCtrl,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Greeting (optional)',
                hintText: 'The first message this character sends',
                alignLabelWithHint: true,
              ),
            ),
            SizedBox(height: tokens.spacing.lg),
            Text('Example dialogues', style: theme.textTheme.titleSmall),
            SizedBox(height: tokens.spacing.xs),
            for (var i = 0; i < _dialogueCtrls.length; i++)
              Padding(
                padding: EdgeInsets.only(bottom: tokens.spacing.sm),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _dialogueCtrls[i],
                        minLines: 2,
                        maxLines: 4,
                        decoration: const InputDecoration(
                          hintText: 'User: ...\nAssistant: ...',
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Remove example',
                      icon: const Icon(Icons.close),
                      onPressed: () => setState(() {
                        _dialogueCtrls.removeAt(i).dispose();
                      }),
                    ),
                  ],
                ),
              ),
            OutlinedButton.icon(
              onPressed: () =>
                  setState(() => _dialogueCtrls.add(TextEditingController())),
              icon: const Icon(Icons.add),
              label: const Text('Add example'),
            ),
            SizedBox(height: tokens.spacing.lg),
            Text('Default model (optional)', style: theme.textTheme.titleSmall),
            SizedBox(height: tokens.spacing.xs),
            _ModelDropdown(
              selectedModelId: _defaultModelId,
              onChanged: (id) => setState(() => _defaultModelId = id),
            ),
            SizedBox(height: tokens.spacing.lg),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Override sampling defaults'),
              subtitle: const Text(
                "Off = uses the conversation's own defaults",
              ),
              value: _overrideSampling,
              onChanged: (v) => setState(() => _overrideSampling = v),
            ),
            if (_overrideSampling)
              SamplingEditor(
                value: _sampling,
                onChanged: (v) => setState(() => _sampling = v),
              ),
            SizedBox(height: tokens.spacing.xl),
          ],
        ),
      ),
    );
  }

  Future<void> _pickEmoji() async {
    final emoji = await showEmojiPickerSheet(context);
    if (emoji == null) return;
    setState(() {
      _avatarEmoji = emoji;
      _avatarPath = null;
    });
  }

  Future<void> _pickImageAvatar() async {
    const typeGroup = XTypeGroup(
      label: 'Image',
      extensions: ['png', 'jpg', 'jpeg'],
    );
    final picked = await openFile(acceptedTypeGroups: [typeGroup]);
    if (picked == null) return;
    final supportDir = await getApplicationSupportDirectory();
    final avatarsDir = Directory(p.join(supportDir.path, 'character_avatars'));
    await avatarsDir.create(recursive: true);
    final destPath = p.join(
      avatarsDir.path,
      '${DateTime.now().microsecondsSinceEpoch}${p.extension(picked.path)}',
    );
    await File(picked.path).copy(destPath);
    if (!mounted) return;
    setState(() {
      _avatarPath = destPath;
      _avatarEmoji = null;
    });
  }

  Future<void> _save() async {
    if (_formKey.currentState?.validate() != true) return;
    setState(() => _saving = true);
    final controller = ref.read(charactersControllerProvider.notifier);
    final exampleDialogues = _dialogueCtrls
        .map((c) => c.text.trim())
        .where((s) => s.isNotEmpty)
        .toList(growable: false);
    final samplingParams = _overrideSampling ? _sampling : null;

    final int? resultId;
    if (_isEdit) {
      resultId = await controller.updateCharacter(
        id: widget.characterId!,
        name: _nameCtrl.text.trim(),
        avatarEmoji: _avatarEmoji,
        avatarPath: _avatarPath,
        personaSystemPrompt: _personaCtrl.text.trim(),
        greeting: _greetingCtrl.text.trim().isEmpty
            ? null
            : _greetingCtrl.text.trim(),
        exampleDialogues: exampleDialogues,
        defaultModelId: _defaultModelId,
        samplingParams: samplingParams,
      );
    } else {
      resultId = await controller.create(
        name: _nameCtrl.text.trim(),
        avatarEmoji: _avatarEmoji,
        avatarPath: _avatarPath,
        personaSystemPrompt: _personaCtrl.text.trim(),
        greeting: _greetingCtrl.text.trim().isEmpty
            ? null
            : _greetingCtrl.text.trim(),
        exampleDialogues: exampleDialogues,
        defaultModelId: _defaultModelId,
        samplingParams: samplingParams,
      );
    }
    if (!mounted) return;
    setState(() => _saving = false);
    if (resultId != null) {
      if (_isEdit) {
        context.pop();
      } else {
        context.pushReplacement('/characters/$resultId');
      }
    }
  }
}

class _ModelDropdown extends ConsumerWidget {
  final int? selectedModelId;
  final ValueChanged<int?> onChanged;

  const _ModelDropdown({
    required this.selectedModelId,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final modelsAsync = ref.watch(installedModelsProvider);
    return switch (modelsAsync) {
      AsyncData(:final value) => DropdownButtonFormField<int?>(
        initialValue: selectedModelId,
        isExpanded: true,
        items: [
          const DropdownMenuItem<int?>(value: null, child: Text('None')),
          for (final model in value)
            DropdownMenuItem<int?>(
              value: model.id,
              child: Text(model.repoId, overflow: TextOverflow.ellipsis),
            ),
        ],
        onChanged: onChanged,
      ),
      _ => const LinearProgressIndicator(),
    };
  }
}

class _BuiltInBlockedView extends ConsumerWidget {
  final CharacterInfo character;
  const _BuiltInBlockedView({required this.character});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final tokens = theme.extension<DhruvaTokens>()!;
    return Scaffold(
      appBar: AppBar(title: Text(character.name)),
      body: Center(
        child: Padding(
          padding: EdgeInsets.all(tokens.spacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                "Built-in characters can't be edited directly.",
                style: theme.textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
              SizedBox(height: tokens.spacing.sm),
              Text(
                'Duplicate it to make your own editable copy.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: tokens.spacing.lg),
              FilledButton(
                onPressed: () async {
                  final newId = await ref
                      .read(charactersControllerProvider.notifier)
                      .duplicate(character);
                  if (newId != null && context.mounted) {
                    context.pushReplacement('/characters/$newId/edit');
                  }
                },
                child: const Text('Duplicate to edit'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
