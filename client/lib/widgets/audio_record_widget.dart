import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';

class AudioRecordWidget extends StatefulWidget {
  final void Function(String audioPath) onComplete;
  final VoidCallback? onRecordingStart;
  final VoidCallback? onRecordingEnd;
  final ValueChanged<double>? onDragDelta;
  final VoidCallback? onCancel;
  final bool isCancelZone;

  const AudioRecordWidget({
    super.key,
    required this.onComplete,
    this.onRecordingStart,
    this.onRecordingEnd,
    this.onDragDelta,
    this.onCancel,
    this.isCancelZone = false,
  });

  @override
  State<AudioRecordWidget> createState() => AudioRecordWidgetState();
}

class AudioRecordWidgetState extends State<AudioRecordWidget> {
  final _recorder = AudioRecorder();
  bool _isRecording = false;
  bool _cancelRequested = false;
  double? _startX;

  Future<void> _startRecording() async {
    final hasPermission = await _recorder.hasPermission();
    if (!hasPermission) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Microphone permission required')),
        );
      }
      return;
    }

    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';

    await _recorder.start(
      const RecordConfig(encoder: AudioEncoder.aacLc, bitRate: 64000),
      path: path,
    );

    setState(() {
      _isRecording = true;
      _cancelRequested = false;
      _startX = null;
    });
    widget.onRecordingStart?.call();
  }

  Future<void> _stopRecording() async {
    final path = await _recorder.stop();
    setState(() => _isRecording = false);
    widget.onRecordingEnd?.call();

    if (_cancelRequested || widget.isCancelZone) {
      if (path != null && File(path).existsSync()) {
        File(path).deleteSync();
      }
      widget.onCancel?.call();
      return;
    }

    if (path != null && File(path).existsSync()) {
      widget.onComplete(path);
    }
  }

  void requestCancel() {
    _cancelRequested = true;
  }

  @override
  void dispose() {
    if (_isRecording) {
      _recorder.stop();
    }
    _recorder.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (event) {
        _startX = event.localPosition.dx;
        _startRecording();
      },
      onPointerMove: (event) {
        if (_startX != null) {
          widget.onDragDelta?.call(event.localPosition.dx - _startX!);
        }
      },
      onPointerUp: (_) {
        _startX = null;
        _stopRecording();
      },
      onPointerCancel: (_) {
        _startX = null;
        _cancelRequested = true;
        _stopRecording();
      },
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: _isRecording ? Colors.red.withAlpha(30) : null,
        ),
        child: Icon(
          _isRecording ? Icons.mic : Icons.mic_none,
          color: _isRecording ? Colors.red : Colors.grey,
        ),
      ),
    );
  }
}
