import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:audioplayers/audioplayers.dart';
import '../models/message.dart';
import 'package:intl/intl.dart';

class MessageBubble extends StatefulWidget {
  final Message message;
  final bool isMe;
  final String serverUrl;

  const MessageBubble({
    super.key,
    required this.message,
    required this.isMe,
    required this.serverUrl,
  });

  @override
  State<MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends State<MessageBubble> {
  final _audioPlayer = AudioPlayer();
  bool _isPlaying = false;
  Duration _position = Duration.zero;

  @override
  void initState() {
    super.initState();
    _audioPlayer.onPositionChanged.listen((p) => setState(() => _position = p));
    _audioPlayer.onPlayerComplete.listen((_) => setState(() => _isPlaying = false));
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    super.dispose();
  }

  String get _fileUrl => 'http://${widget.serverUrl}/api/files/${widget.message.filePath}';

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: widget.isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 4),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        child: Column(
          crossAxisAlignment: widget.isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            if (widget.message.isImage)
              _buildImageContent()
            else if (widget.message.isVideo)
              _buildVideoContent()
            else if (widget.message.isAudio)
              _buildAudioContent()
            else if (widget.message.isFile)
              _buildFileContent()
            else
              _buildTextContent(),
            const SizedBox(height: 2),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                DateFormat('HH:mm').format(widget.message.createdAt),
                style: TextStyle(fontSize: 11, color: Colors.grey[500]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTextContent() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: widget.isMe
            ? const Color(0xFF2AABEE)
            : Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(18),
          topRight: const Radius.circular(18),
          bottomLeft: Radius.circular(widget.isMe ? 18 : 4),
          bottomRight: Radius.circular(widget.isMe ? 4 : 18),
        ),
      ),
      child: Text(
        widget.message.text,
        style: TextStyle(
          color: widget.isMe ? Colors.white : null,
          fontSize: 15,
        ),
      ),
    );
  }

  Widget _buildImageContent() {
    return GestureDetector(
      onTap: () => _showMediaPreview(),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: CachedNetworkImage(
          imageUrl: _fileUrl,
          placeholder: (_, __) => Container(
            height: 200,
            color: Colors.grey[300],
            child: const Center(child: CircularProgressIndicator()),
          ),
          errorWidget: (_, __, ___) => Container(
            height: 200,
            color: Colors.grey[300],
            child: const Icon(Icons.broken_image),
          ),
          fit: BoxFit.cover,
        ),
      ),
    );
  }

  Widget _buildVideoContent() {
    return GestureDetector(
      onTap: () => _showMediaPreview(),
      child: Container(
        width: 200,
        height: 150,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: Colors.black,
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            CachedNetworkImage(
              imageUrl: _fileUrl,
              placeholder: (_, __) => const CircularProgressIndicator(color: Colors.white),
              errorWidget: (_, __, ___) => const Icon(Icons.videocam, size: 48, color: Colors.white),
              fit: BoxFit.cover,
              width: double.infinity,
              height: double.infinity,
            ),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: const BoxDecoration(
                color: Colors.black54,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.play_arrow, size: 40, color: Colors.white),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAudioContent() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: widget.isMe
            ? const Color(0xFF2AABEE)
            : Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: Icon(
              _isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled,
              color: widget.isMe ? Colors.white : const Color(0xFF2AABEE),
              size: 32,
            ),
            onPressed: () {
              if (_isPlaying) {
                _audioPlayer.pause();
                setState(() => _isPlaying = false);
              } else {
                _audioPlayer.play(UrlSource(_fileUrl));
                setState(() => _isPlaying = true);
              }
            },
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Voice message',
                style: TextStyle(
                  color: widget.isMe ? Colors.white : null,
                  fontSize: 13,
                ),
              ),
              Text(
                _formatDuration(_position),
                style: TextStyle(
                  color: widget.isMe ? Colors.white70 : Colors.grey,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFileContent() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: widget.isMe
            ? const Color(0xFF2AABEE)
            : Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.insert_drive_file,
            color: widget.isMe ? Colors.white : const Color(0xFF2AABEE),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.message.fileName ?? 'File',
                  style: TextStyle(
                    color: widget.isMe ? Colors.white : null,
                    fontSize: 13,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  widget.message.fileExtension,
                  style: TextStyle(
                    color: widget.isMe ? Colors.white70 : Colors.grey,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Icon(Icons.download, color: widget.isMe ? Colors.white : const Color(0xFF2AABEE), size: 20),
        ],
      ),
    );
  }

  void _showMediaPreview() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
          ),
          body: Center(
            child: InteractiveViewer(
              child: widget.message.isImage
                  ? CachedNetworkImage(imageUrl: _fileUrl, fit: BoxFit.contain)
                  : const Icon(Icons.play_circle_fill, size: 80, color: Colors.white),
            ),
          ),
        ),
      ),
    );
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}
