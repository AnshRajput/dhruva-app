/// Loop-2 developer harness: load a GGUF, stream a completion, cancel, unload.
///
/// Deliberately plain, unstyled Material — theming is Loop 4. This is a dev
/// tool, not product UI, so it holds its own [EngineService] directly rather
/// than going through Riverpod (which lands with the real features).
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../engine_bindings/engine_service.dart';
import '../../engine_bindings/llama_engine_service.dart';

/// Best-effort defaults for THIS dev machine (see app/.dev-native/). Editable
/// in the UI; nothing depends on these paths existing.
const _defaultLibDir =
    '/Users/ansh/AppuInsideEngineering/dhruva-app/app/.dev-native/macos';
const _defaultModel =
    '/Users/ansh/AppuInsideEngineering/dhruva-app/app/.dev-native/models/'
    'SmolLM2-135M-Instruct-Q4_K_M.gguf';

class DebugChatScreen extends StatefulWidget {
  const DebugChatScreen({super.key});

  @override
  State<DebugChatScreen> createState() => _DebugChatScreenState();
}

class _DebugChatScreenState extends State<DebugChatScreen> {
  final _libPathCtrl = TextEditingController(
    text: '$_defaultLibDir/libllama.dylib',
  );
  final _modelPathCtrl = TextEditingController(text: _defaultModel);
  final _promptCtrl = TextEditingController(text: 'The capital of France is');
  final _outputCtrl = ScrollController();

  EngineService? _engine;
  StreamSubscription<EngineEvent>? _genSub;

  var _loading = false;
  var _generating = false;
  var _output = '';
  String? _error;
  String? _status;

  int _tokenCount = 0;
  final _stopwatch = Stopwatch();

  @override
  void dispose() {
    unawaited(_genSub?.cancel());
    unawaited(_engine?.dispose());
    _libPathCtrl.dispose();
    _modelPathCtrl.dispose();
    _promptCtrl.dispose();
    _outputCtrl.dispose();
    super.dispose();
  }

  bool get _isLoaded => _engine?.isLoaded ?? false;

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _status = 'loading model…';
    });
    try {
      await _engine?.dispose();
      final libPath = _libPathCtrl.text.trim();
      // Dev-tool exception: constructs the concrete impl directly. Real
      // features get EngineService via Riverpod DI (later loop).
      final engine = LlamaEngineService(
        libraryPath: libPath.isEmpty ? null : libPath,
      );
      await engine.load(
        _modelPathCtrl.text.trim(),
        params: const EngineLoadParams(contextSize: 2048),
      );
      setState(() {
        _engine = engine;
        _status = 'model loaded';
      });
    } on EngineFailure catch (e) {
      setState(() {
        _engine = null;
        _error = '${e.runtimeType}: ${e.message}';
        _status = null;
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _unload() async {
    await _genSub?.cancel();
    _genSub = null;
    await _engine?.unload();
    setState(() {
      _generating = false;
      _status = 'model unloaded';
    });
  }

  Future<void> _generate() async {
    final engine = _engine;
    if (engine == null || !engine.isLoaded) return;
    setState(() {
      _generating = true;
      _output = '';
      _error = null;
      _status = 'generating…';
      _tokenCount = 0;
    });
    _stopwatch
      ..reset()
      ..start();

    _genSub = engine
        .generate(
          prompt: _promptCtrl.text,
          params: const EngineGenerateParams(maxTokens: 256, temperature: 0.7),
        )
        .listen(
          (event) {
            switch (event) {
              case EngineToken():
                setState(() {
                  _output += event.text;
                  _tokenCount++;
                });
                _autoScroll();
              case EngineCompletion():
                _stopwatch.stop();
                setState(() {
                  _generating = false;
                  _status =
                      'done: ${event.reason.name} · '
                      '${event.tokenCount} tokens · ${_tokPerSec()} tok/s';
                });
            }
          },
          onError: (Object e) {
            _stopwatch.stop();
            setState(() {
              _generating = false;
              _error = e is EngineFailure
                  ? '${e.runtimeType}: ${e.message}'
                  : e.toString();
              _status = null;
            });
          },
          onDone: () {
            if (mounted && _generating) {
              setState(() => _generating = false);
            }
          },
        );
  }

  Future<void> _cancel() async {
    await _engine?.cancel();
    _stopwatch.stop();
    setState(() {
      _generating = false;
      _status = 'cancelled · $_tokenCount tokens · ${_tokPerSec()} tok/s';
    });
  }

  String _tokPerSec() {
    final s = _stopwatch.elapsedMilliseconds / 1000.0;
    if (s <= 0) return '0.0';
    return (_tokenCount / s).toStringAsFixed(1);
  }

  void _autoScroll() {
    if (!_outputCtrl.hasClients) return;
    _outputCtrl.jumpTo(_outputCtrl.position.maxScrollExtent);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Dhruva · Engine Debug')),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _libPathCtrl,
              decoration: const InputDecoration(
                labelText: 'Native library path (blank = process symbols)',
                isDense: true,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _modelPathCtrl,
              decoration: const InputDecoration(
                labelText: 'GGUF model path',
                isDense: true,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                FilledButton(
                  onPressed: _loading || _isLoaded ? null : _load,
                  child: Text(_loading ? 'Loading…' : 'Load'),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: _isLoaded && !_generating ? _unload : null,
                  child: const Text('Unload'),
                ),
                const SizedBox(width: 12),
                Icon(
                  _isLoaded ? Icons.check_circle : Icons.circle_outlined,
                  color: _isLoaded ? Colors.green : Colors.grey,
                  size: 18,
                ),
                const SizedBox(width: 4),
                Text(_isLoaded ? 'loaded' : 'not loaded'),
              ],
            ),
            const Divider(height: 24),
            TextField(
              controller: _promptCtrl,
              minLines: 1,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Prompt',
                isDense: true,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                FilledButton(
                  onPressed: _isLoaded && !_generating ? _generate : null,
                  child: const Text('Generate'),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: _generating ? _cancel : null,
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 12),
                if (_generating)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            if (_status != null)
              Text(_status!, style: Theme.of(context).textTheme.bodySmall),
            if (_error != null)
              Container(
                margin: const EdgeInsets.only(top: 8),
                padding: const EdgeInsets.all(8),
                color: const Color(0x33FF0000),
                child: Text(
                  _error!,
                  style: const TextStyle(color: Color(0xFFB00020)),
                ),
              ),
            const SizedBox(height: 8),
            Expanded(
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: SingleChildScrollView(
                  controller: _outputCtrl,
                  child: SelectableText(
                    _output.isEmpty ? '(output appears here)' : _output,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Convenience for tests / manual runs: true if the default dev binaries and
/// model are present on this machine.
bool devArtifactsPresent() =>
    File('$_defaultLibDir/libllama.dylib').existsSync() &&
    File(_defaultModel).existsSync();
