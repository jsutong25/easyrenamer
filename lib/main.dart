// EasyRenamer — macOS & Windows (file_selector + desktop_drop)
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_selector/file_selector.dart';
import 'package:desktop_drop/desktop_drop.dart'; // v0.5.0
import 'package:path/path.dart' as p;
import 'package:flutter_svg/flutter_svg.dart';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'EasyRenamer',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFC3B1E1), // Hex #E6E6FA
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  String? _folderPath;
  List<FileSystemEntity> _allFiles = [];
  List<File> _imageFiles = [];

  // Inputs
  final _baseNameCtrl = TextEditingController(text: 'img');
  final _startIndexCtrl = TextEditingController(text: '1');
  final _padCtrl = TextEditingController(text: '3');
  final _pathCtrl = TextEditingController(); // manual path loader
  SortBy _sortBy = SortBy.name;
  bool _recursive = false;
  bool _useUnderscore = true; // New: Toggle for underscore

  // State
  List<RenameItem> _plan = [];
  bool _isScanning = false;
  bool _isRenaming = false;
  bool _isDragging = false;

  static const _imageExts = {
    '.jpg',
    '.jpeg',
    '.png',
    '.webp',
    '.gif',
    '.bmp',
    '.tif',
    '.tiff',
    '.heic',
    '.raw',
    '.svg',
    '.heif',
    '.ARW',
  };

  @override
  void dispose() {
    _baseNameCtrl.dispose();
    _startIndexCtrl.dispose();
    _padCtrl.dispose();
    _pathCtrl.dispose();
    super.dispose();
  }

  // -------- Actions --------
  Future<void> _pickFolder() async {
    // 1) Normal file_selector dialog
    try {
      final initialDir =
          _folderPath ??
          Platform.environment['HOME'] ??
          '/Users/${Platform.environment['USER']}';

      final picked = await getDirectoryPath(
        confirmButtonText: 'Choose',
        initialDirectory: initialDir,
      );

      if (picked != null) {
        final resolved = _resolveDirPath(picked);
        setState(() {
          _folderPath = resolved;
          _pathCtrl.text = resolved;
          _plan.clear();
          _imageFiles.clear();
          _allFiles.clear();
        });
        await _scanFolder();
        return;
      } else {
        _showSnack('No folder chosen.');
      }
    } catch (e) {
      _showSnack('Primary picker error: $e — trying fallback…');
    }

    // Rest of your fallback code remains the same...
  }

  Future<void> _scanFolder() async {
    final folder = _folderPath;
    if (folder == null) return;
    setState(() => _isScanning = true);
    try {
      final dir = Directory(folder);
      final entities = await dir
          .list(recursive: _recursive, followLinks: false)
          .toList();
      final files = entities.whereType<File>().toList();
      files.sort(
        (a, b) => p
            .basename(a.path)
            .toLowerCase()
            .compareTo(p.basename(b.path).toLowerCase()),
      );

      final imageFiles = <File>[];
      for (final f in files) {
        final ext = p.extension(f.path).toLowerCase();
        if (_imageExts.contains(ext)) imageFiles.add(f);
      }

      setState(() {
        _allFiles = files;
        _imageFiles = imageFiles;
      });

      await _buildPreview();
      if (_imageFiles.isEmpty) {
        _showSnack(
          'Scanned ${_allFiles.length} entries — no images found. Toggle "Include subfolders" or check extensions.',
        );
      }
    } finally {
      if (mounted) setState(() => _isScanning = false);
    }
  }

  Future<void> _buildPreview() async {
    final folder = _folderPath;
    if (folder == null) return;

    final base = _baseNameCtrl.text.trim();
    final startIndex = int.tryParse(_startIndexCtrl.text.trim()) ?? 1;
    final pad = int.tryParse(_padCtrl.text.trim()) ?? 3;

    final files = [..._imageFiles];
    if (_sortBy == SortBy.name) {
      files.sort(
        (a, b) => p
            .basename(a.path)
            .toLowerCase()
            .compareTo(p.basename(b.path).toLowerCase()),
      );
    } else if (_sortBy == SortBy.modified) {
      files.sort(
        (a, b) => a.statSync().modified.compareTo(b.statSync().modified),
      );
    } else if (_sortBy == SortBy.created) {
      files.sort(
        (a, b) => a.statSync().changed.compareTo(b.statSync().changed),
      );
    }

    final existingLower = _allFiles
        .map((e) => p.basename(e.path).toLowerCase())
        .toSet();

    final plan = <RenameItem>[];
    for (var i = 0; i < files.length; i++) {
      final src = files[i];
      final ext = p.extension(src.path);
      final numStr = (startIndex + i).toString().padLeft(pad, '0');

      // NEW: Conditionally add underscore based on checkbox
      final newName = _useUnderscore
          ? '${base}_$numStr$ext' // With underscore: img_001.jpg
          : '$base$numStr$ext'; // Without underscore: img001.jpg

      final targetPath = p.join(folder, newName);

      String? conflict;
      final newLower = newName.toLowerCase();
      final srcLower = p.basename(src.path).toLowerCase();
      if (newLower != srcLower && existingLower.contains(newLower)) {
        conflict = 'Target name already exists';
      }

      plan.add(
        RenameItem(
          source: src,
          targetPath: targetPath,
          newName: newName,
          conflict: conflict,
        ),
      );
    }

    if (mounted) setState(() => _plan = plan);
  }

  Future<void> _renameAll() async {
    if (_plan.isEmpty) return;
    if (_plan.any((e) => e.conflict != null)) {
      _showSnack('Resolve conflicts before renaming.');
      return;
    }

    if (mounted) setState(() => _isRenaming = true);

    try {
      for (final item in _plan) {
        final src = item.source;
        final target = item.targetPath;
        if (p.equals(src.path, target)) continue;

        // Two-step rename to be safer across filesystems
        final temp = p.join(
          p.dirname(target),
          '.tmp_${DateTime.now().microsecondsSinceEpoch}_${p.basename(target)}',
        );
        try {
          await src.rename(temp);
          await File(temp).rename(target);
        } catch (_) {
          await src.rename(target);
        }
      }

      _showSnack('Renamed ${_plan.length} file(s).');
      await _scanFolder();
    } finally {
      if (mounted) setState(() => _isRenaming = false);
    }
  }

  // -------- UI --------
  @override
  Widget build(BuildContext context) {
    final canRename = _plan.isNotEmpty && !_plan.any((e) => e.conflict != null);

    return Scaffold(
      appBar: AppBar(
        title: const Text('EasyRenamer'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16.0), // Right margin
            child: IconButton(
              tooltip: 'Pick Folder',
              onPressed: _isScanning ? null : _pickFolder,
              icon: SvgPicture.asset(
                'assets/add_folder.svg',
                width: 24,
                height: 24,
              ),
            ),
          ),
        ],
      ),
      body: DropTarget(
        onDragEntered: (_) => setState(() => _isDragging = true),
        onDragExited: (_) => setState(() => _isDragging = false),
        onDragDone: (details) async {
          final items = details.files; // List<DropItem> for 0.5.0
          if (items.isEmpty) return;
          String? dirPath;
          for (final item in items) {
            final raw = item.path;
            final cand = _resolveDirPath(raw);
            if (Directory(cand).existsSync()) {
              dirPath = cand;
              break;
            }
            final parent = Directory(p.dirname(cand));
            if (parent.existsSync()) dirPath = parent.path;
          }
          if (dirPath == null) return;
          setState(() {
            _folderPath = dirPath;
            _pathCtrl.text = dirPath ?? '';
            _plan.clear();
            _imageFiles.clear();
            _allFiles.clear();
          });
          await _scanFolder();
        },
        child: Stack(
          children: [
            Row(
              children: [
                // Left panel
                SizedBox(
                  width: 360,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      Text(
                        _folderPath == null
                            ? 'No folder selected'
                            : 'Folder: $_folderPath',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 8),

                      // Manual path loader
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _pathCtrl,
                              decoration: const InputDecoration(
                                labelText: 'Folder path',
                                hintText: '/Users/you/Pictures/Event',
                                border: OutlineInputBorder(),
                              ),
                              onSubmitted: (_) async {
                                final path = _resolveDirPath(
                                  _pathCtrl.text.trim(),
                                );
                                if (!Directory(path).existsSync()) {
                                  _showSnack('Path not found.');
                                  return;
                                }
                                setState(() {
                                  _folderPath = path;
                                  _plan.clear();
                                  _imageFiles.clear();
                                  _allFiles.clear();
                                });
                                await _scanFolder();
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          FilledButton(
                            onPressed: () async {
                              final path = _resolveDirPath(
                                _pathCtrl.text.trim(),
                              );
                              if (!Directory(path).existsSync()) {
                                _showSnack('Path not found.');
                                return;
                              }
                              setState(() {
                                _folderPath = path;
                                _plan.clear();
                                _imageFiles.clear();
                                _allFiles.clear();
                              });
                              await _scanFolder();
                            },
                            child: const Text('Load'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),

                      Row(
                        children: [
                          Checkbox(
                            value: _recursive,
                            onChanged: (v) async {
                              setState(() => _recursive = v ?? false);
                              if (_folderPath != null) await _scanFolder();
                            },
                          ),
                          const Expanded(child: Text('Include subfolders')),
                        ],
                      ),
                      const SizedBox(height: 8),

                      TextField(
                        controller: _baseNameCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Base name',
                          hintText: 'e.g., malaysia_trip',
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (_) => _buildPreview(),
                      ),
                      const SizedBox(height: 12),

                      // NEW: Underscore toggle checkbox
                      Row(
                        children: [
                          Checkbox(
                            value: _useUnderscore,
                            onChanged: (v) {
                              setState(() => _useUnderscore = v ?? true);
                              _buildPreview();
                            },
                          ),
                          const Expanded(
                            child: Text('Add underscore before number'),
                          ),
                          Tooltip(
                            message:
                                'When checked: basename_001.jpg\nWhen unchecked: basename001.jpg',
                            child: const Icon(Icons.help_outline, size: 18),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _startIndexCtrl,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: 'Start #',
                                border: OutlineInputBorder(),
                              ),
                              onChanged: (_) => _buildPreview(),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextField(
                              controller: _padCtrl,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: 'Padding',
                                hintText: 'e.g., 1 -> 3',
                                border: OutlineInputBorder(),
                              ),
                              onChanged: (_) => _buildPreview(),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      DropdownButtonFormField<SortBy>(
                        initialValue: _sortBy,
                        decoration: const InputDecoration(
                          labelText: 'Order files by',
                          border: OutlineInputBorder(),
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: SortBy.name,
                            child: Text('Name'),
                          ),
                          DropdownMenuItem(
                            value: SortBy.modified,
                            child: Text('Modified time'),
                          ),
                          DropdownMenuItem(
                            value: SortBy.created,
                            child: Text('Created time (best-effort)'),
                          ),
                        ],
                        onChanged: (v) {
                          if (v == null) return;
                          setState(() => _sortBy = v);
                          _buildPreview();
                        },
                      ),
                      const SizedBox(height: 20),

                      FilledButton.icon(
                        onPressed: _folderPath == null || _isScanning
                            ? null
                            : _scanFolder,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Rescan'),
                      ),
                      const SizedBox(height: 8),

                      FilledButton.icon(
                        onPressed: canRename && !_isRenaming
                            ? _renameAll
                            : null,
                        icon: const Icon(Icons.drive_file_rename_outline),
                        label: Text(_isRenaming ? 'Renaming…' : 'Rename files'),
                      ),
                    ],
                  ),
                ),

                const VerticalDivider(width: 1),

                // Right preview
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        child: Row(
                          children: [
                            const Text(
                              'Preview',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(width: 12),
                            if (_isScanning)
                              const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                            const Spacer(),
                            Text('${_plan.length} image(s) found'),
                          ],
                        ),
                      ),
                      const Divider(height: 1),
                      Expanded(
                        child: _plan.isEmpty
                            ? const Center(
                                child: Text(
                                  'Drop a folder, paste a path, or click the folder icon.',
                                ),
                              )
                            : ListView.separated(
                                itemCount: _plan.length,
                                separatorBuilder: (_, __) =>
                                    const Divider(height: 1),
                                itemBuilder: (context, i) {
                                  final it = _plan[i];
                                  final baseName = p.basename(it.source.path);
                                  return ListTile(
                                    dense: true,
                                    leading: Text(
                                      (i + 1).toString().padLeft(3, '0'),
                                    ),
                                    title: Text(
                                      baseName,
                                      style: const TextStyle(
                                        fontFamily: 'monospace',
                                      ),
                                    ),
                                    subtitle: Text(
                                      it.newName,
                                      style: const TextStyle(
                                        fontFamily: 'monospace',
                                      ),
                                    ),
                                    trailing: it.conflict == null
                                        ? const Icon(
                                            Icons.check_circle,
                                            color: Colors.green,
                                          )
                                        : Tooltip(
                                            message: it.conflict!,
                                            child: const Icon(
                                              Icons.error,
                                              color: Colors.red,
                                            ),
                                          ),
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (_isDragging)
              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: const Color(0xFFC3B1E1).withValues(alpha: 0.08),
                      border: Border.all(
                        color: const Color(0xFFC3B1E1),
                        width: 2,
                      ),
                    ),
                    child: const Center(
                      child: Text(
                        'Drop a folder to scan',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }
}

// -------- Helpers & Models --------
String _resolveDirPath(String raw) {
  try {
    final dir = Directory(raw);
    if (dir.existsSync()) {
      return dir.resolveSymbolicLinksSync();
    }
  } catch (_) {}
  return raw;
}

class RenameItem {
  final File source;
  final String targetPath;
  final String newName;
  final String? conflict;
  RenameItem({
    required this.source,
    required this.targetPath,
    required this.newName,
    required this.conflict,
  });
}

enum SortBy { name, modified, created }
