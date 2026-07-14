import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';
import 'data.dart';

void main() {
  runApp(const GardApp());
}

class GardApp extends StatelessWidget {
  const GardApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'جرد سريع',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        fontFamily: 'Cairo',
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
  final Map<String, int> _counts = {};
  final List<MapEntry<String, int>> _undo = [];
  final TextEditingController _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _load();
    _searchCtrl.addListener(() {
      setState(() => _query = _searchCtrl.text.trim());
    });
  }

  Future<void> _load() async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString('counts');
    if (raw!= null) {
      final map = Map<String, dynamic>.from(jsonDecode(raw));
      setState(() {
        _counts.clear();
        _counts.addAll(map.map((k, v) => MapEntry(k, (v as num).toInt())));
      });
    }
  }

  Future<void> _save() async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString('counts', jsonEncode(_counts));
  }

  void _add(String barcode, [int by = 1]) {
    setState(() {
      _counts.update(barcode, (v) => v + by, ifAbsent: () => by);
      _undo.add(MapEntry(barcode, by));
    });
    _save();
  }

  void _sub(String barcode, [int by = 1]) {
    setState(() {
      final cur = _counts[barcode]?? 0;
      final next = (cur - by).clamp(0, 1 << 31);
      if (next == 0) {
        _counts.remove(barcode);
      } else {
        _counts[barcode] = next;
      }
      _undo.add(MapEntry(barcode, -by));
    });
    _save();
  }

  void _undoLast() {
    if (_undo.isEmpty) return;
    final last = _undo.removeLast();
    final bc = last.key;
    final by = last.value;
    setState(() {
      _counts.update(bc, (v) => (v - by).clamp(0, 1 << 31), ifAbsent: () => 0);
      if ((_counts[bc]?? 0) <= 0) _counts.remove(bc);
    });
    _save();
  }

  Future<void> _scan() async {
    final cam = await Permission.camera.request();
    if (!cam.isGranted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('لازم تسمح للكاميرا')),
        );
      }
      return;
    }
    if (!mounted) return;
    final result = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const ScanPage()),
    );
    if (result!= null && result.isNotEmpty) _add(result);
  }

  List<String> get _filtered {
    final q = _query.toLowerCase();
    final keys = _counts.keys.toList()..sort();
    if (q.isEmpty) return keys;
    return keys.where((bc) {
      final name = barcodeToName[bc]?? '';
      return bc.contains(q) || name.toLowerCase().contains(q);
    }).toList();
  }

  int get _totalItems => _counts.values.fold(0, (a, b) => a + b);

  Future<void> _resetAll() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('تصفير كل الكميات؟'),
        content: const Text('هترجع كل الأصناف للصفر. متأكد؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('تصفير')),
        ],
      ),
    );
    if (ok == true) {
      setState(() => _counts.clear());
      _undo.clear();
      _save();
    }
  }

  @override
  Widget build(BuildContext context) {
    final list = _filtered;
    return Scaffold(
      appBar: AppBar(
        title: const Text('جرد سريع'),
        actions: [
          IconButton(
            tooltip: 'Undo',
            onPressed: _undo.isEmpty? null : _undoLast,
            icon: const Icon(Icons.undo),
          ),
          IconButton(
            tooltip: 'تصفير',
            onPressed: _counts.isEmpty? null : _resetAll,
            icon: const Icon(Icons.delete_forever),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _scan,
        icon: const Icon(Icons.qr_code_scanner),
        label: const Text('Scan'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: 'ابحث بالباركود أو الاسم',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                suffixIcon: _query.isEmpty
                   ? null
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () => _searchCtrl.clear(),
                      ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Chip(label: Text('أصناف: ${list.length}')),
                const SizedBox(width: 8),
                Chip(label: Text('إجمالي: $_totalItems')),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ListView.separated(
              itemCount: list.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final bc = list[i];
                final name = barcodeToName[bc]?? 'غير معروف';
                final qty = _counts[bc]?? 0;
                return ListTile(
                  title: Text(name, maxLines: 2, overflow: TextOverflow.ellipsis),
                  subtitle: Text(bc),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        onPressed: qty == 0? null : () => _sub(bc),
                        icon: const Icon(Icons.remove_circle_outline),
                      ),
                      Text('$qty', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      IconButton(
                        onPressed: () => _add(bc),
                        icon: const Icon(Icons.add_circle_outline),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class ScanPage extends StatefulWidget {
  const ScanPage({super.key});
  @override
  State<ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends State<ScanPage> {
  final MobileScannerController controller = MobileScannerController();
  bool _done = false;

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('امسح الباركود')),
      body: Stack(
        children: [
          MobileScanner(
            controller: controller,
            onDetect: (cap) {
              if (_done) return;
              final code = cap.barcodes.first.rawValue;
              if (code!= null && code.isNotEmpty) {
                _done = true;
                Navigator.of(context).pop(code);
              }
            },
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                'وجّه الكاميرا للباركود',
                style: TextStyle(color: Colors.white),
              ),
            ),
          )
        ],
      ),
    );
  }
}
