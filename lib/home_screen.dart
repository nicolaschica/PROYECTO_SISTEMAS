import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'websocket_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _ws = WebSocketService();
  final _serverCtrl = TextEditingController(text: '192.168.1.100');
  final _groupCtrl = TextEditingController(text: 'grupo1');
  final _nameCtrl = TextEditingController();
  final _msgCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();

  StreamSubscription? _streamSub;

  bool _connected = false;
  bool _connecting = false;
  String _myName = '';
  int _onlineCount = 0;
  final List<Map<String, dynamic>> _messages = [];

  // ── Paleta oscura ────────────────────────────────────────────────────
  static const _bg = Color(0xFF0A0A0A);
  static const _surface = Color(0xFF1A1A1A);
  static const _surface2 = Color(0xFF252525);
  static const _accent = Color(0xFF25D366);
  static const _myBubble = Color(0xFF005C4B);
  static const _otherBubble = Color(0xFF1F2C34);
  static const _textPrimary = Color(0xFFE9EDEF);
  static const _textMuted = Color(0xFF8696A0);
  static const _errorColor = Color(0xFFFF4444);
  static const _successColor = Color(0xFF25D366);

  // ── Conectar con Lógica de Timeout ───────────────────────────────────
  void _connect() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      _toast('Por favor escribe tu nombre para continuar', isError: true);
      return;
    }

    setState(() => _connecting = true);

    // Variable de control para el timeout
    bool respuestaRecibida = false;

    // Iniciamos un temporizador de 5 segundos
    Timer(const Duration(seconds: 5), () {
      if (mounted && _connecting && !respuestaRecibida) {
        setState(() {
          _connecting = false;
        });
        _ws.disconnect(); // Cerramos el intento de socket
        _showFriendlyAlert(isNameCollision: false); // Disparamos el "sin conexión" amigable
      }
    });


  // Cancelamos cualquier suscripción previa y limpiamos mensajes de sistema
    await _streamSub?.cancel();
    _streamSub = null;

    _messages.removeWhere((m) => m['type'] == 'system');

    _streamSub = _ws.stream.listen((msg) {
      if (!mounted) return;

      // En cuanto llega el primer mensaje (sea lo que sea), marcamos éxito de red
      respuestaRecibida = true;

      setState(() {
        switch (msg['type']) {
          case 'error':
            _connecting = false;
            _connected = false;
            _addSystem(msg['message'] ?? 'Error desconocido.', isError: true);
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              final errMsg = (msg['message'] as String? ?? '').toLowerCase();
              final isNameCollision =
                  errMsg.contains('nombre') && errMsg.contains('uso');
              _showFriendlyAlert(isNameCollision: isNameCollision);
            });
            break;

          case 'event':
            _connecting = false;
            final ev = msg['event'] as String? ?? '';
            final members = (msg['members'] as List?)?.cast<String>() ?? [];
            _onlineCount = members.length;

            if (ev == 'join' && msg['sender'] == name) {
              _connected = true;
              _myName = name;
              _addSystem(
                '¡Bienvenido al grupo "${_groupCtrl.text}"! '
                'Hay $_onlineCount persona(s) conectada(s).',
                isSuccess: true,
              );
            } else if (ev == 'join') {
              _addSystem('${msg['sender']} se unió al grupo.');
            } else if (ev == 'leave') {
              _addSystem('${msg['sender']} abandonó el grupo.');
            } else if (ev == 'disconnected') {
              _connected = false;
              _onlineCount = 0;
              _addSystem(
                'Perdiste la conexión. Vuelve a conectarte cuando tengas señal.',
                isError: true,
              );
            }
            break;


          // Manejo de mensajes de chat tanto nuevos como históricos
          case 'action':
            _messages.add({
              'type': 'chat',
              'sender': msg['sender'] ?? '',
              'text': msg['action'] ?? '',
              'ts': msg['ts'] ?? '',
              'isMe': (msg['sender'] ?? '') == _myName && _myName.isNotEmpty,
            });
            _scrollToBottom();
            break;


          // Cuando recibimos el historial, lo limpiamos y lo mostramos, indicando cuántos mensajes se recuperaron
          case 'history':
            final history = (msg['messages'] as List? ?? [])
                .cast<Map<String, dynamic>>();
            if (history.isNotEmpty) {
              _messages.removeWhere((m) => m['type'] == 'chat');
              _addSystem(
                'Se recuperaron ${history.length} mensaje(s) '
                'enviados mientras estabas desconectado.',
                isSuccess: true,
              );
              for (final h in history) {
                _messages.add({
                  'type': 'chat',
                  'sender': h['sender'] ?? '',
                  'text': h['action'] ?? '',
                  'ts': h['ts'] ?? '',
                  'isMe': (h['sender'] ?? '') == _myName && _myName.isNotEmpty,
                });
              }
              _scrollToBottom();
            }
            break;
        }
      });
    });


    // Intentamos conectar al WebSocket con los datos proporcionados
    await _ws.connect(_serverCtrl.text.trim(), _groupCtrl.text.trim(), name);
  }



  // ── Desconectar y limpiar estado ─────────────────────────────────────
  void _sendMessage() {
    final text = _msgCtrl.text.trim();
    if (text.isEmpty) return;
    if (!_connected) {
      _toast('No estás conectado al grupo', isError: true);
      return;
    }
    _ws.sendAction(text);
    _msgCtrl.clear();
  }

  void _disconnect() async {
    await _streamSub?.cancel();
    _streamSub = null;
    _ws.disconnect();
    setState(() {
      _connected = false;
      _connecting = false;
      _onlineCount = 0;
      _addSystem('Saliste del grupo correctamente.');
    });
  }

  // ── Alerta amigable (sin conexión) ───────────────────────────────────────
  void _showFriendlyAlert({required bool isNameCollision}) {
    showDialog(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withOpacity(0.6),
      builder: (ctx) => Dialog(
        backgroundColor: const Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 32, 28, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: isNameCollision
                      ? const Color(0xFFFFEBEB)
                      : const Color(0xFFFFF3CD),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isNameCollision
                      ? Icons.person_off_outlined
                      : Icons.wifi_off_rounded,
                  size: 32,
                  color: isNameCollision
                      ? const Color(0xFFE24B4A)
                      : const Color(0xFFE6A817),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                isNameCollision
                    ? 'Ese nombre ya está en uso'
                    : 'Sin conexión',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xFFE9EDEF),
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                isNameCollision
                    ? 'Alguien en el grupo ya usa ese nombre. Prueba con uno diferente.'
                    : '¡Ups! Parece que no pudimos conectarnos. Intentalo nuevamente ',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xFF8696A0),
                  fontSize: 14,
                  height: 1.6,
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 46,
                child: ElevatedButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF25D366),
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    isNameCollision ? 'Elegir otro nombre' : 'Entendido',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Helpers ──────────────────────────────────────────────────────────
  void _addSystem(String text, {bool isError = false, bool isSuccess = false}) {
    _messages.add({
      'type': 'system',
      'text': text,
      'isError': isError,
      'isSuccess': isSuccess,
    });
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _toast(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? _errorColor : _successColor,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  String _formatTime(String ts) {
    if (ts.length < 16) return '';
    try {
      final dt = DateTime.parse(ts).toLocal();
      return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return ts.length >= 16 ? ts.substring(11, 16) : '';
    }
  }

  String _initials(String name) {
    final parts = name.trim().split(' ');
    if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    return name.isNotEmpty ? name[0].toUpperCase() : '?';
  }

  Color _avatarColor(String name) {
    const colors = [
      Color(0xFF6B4EFF),
      Color(0xFFFF6B35),
      Color(0xFF00B4D8),
      Color(0xFFE63946),
      Color(0xFF2EC4B6),
      Color(0xFFFF9F1C),
    ];
    return colors[name.codeUnitAt(0) % colors.length];
  }

  @override
  void dispose() {
    _streamSub?.cancel();
    _ws.disconnect();
    _msgCtrl.dispose();
    _nameCtrl.dispose();
    _serverCtrl.dispose();
    _groupCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Color(0xFF1A1A1A),
        statusBarIconBrightness: Brightness.light,
      ),
    );
    return Theme(
      data: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: _bg,
        colorScheme: const ColorScheme.dark(primary: _accent),
      ),
      child: Scaffold(
        backgroundColor: _bg,
        body: _connected ? _buildChat() : _buildLogin(),
      ),
    );
  }

  // ── UI LOGIN ────────────────────────────────────────────────────────
  Widget _buildLogin() => SafeArea(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 40),
          Center(
            child: Column(
              children: [
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: _accent.withOpacity(0.15),
                    shape: BoxShape.circle,
                    border: Border.all(color: _accent, width: 2),
                  ),
                  child: const Icon(
                    Icons.chat_bubble_outline,
                    color: _accent,
                    size: 36,
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Chat en tiempo real',
                  style: TextStyle(
                    color: _textPrimary,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Conecta con tu grupo al instante',
                  style: TextStyle(color: _textMuted, fontSize: 14),
                ),
              ],
            ),
          ),
          const SizedBox(height: 40),
          _label('IP del servidor'),
          _field(
            controller: _serverCtrl,
            hint: 'Ej: 192.168.1.100',
            icon: Icons.wifi,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
          ),
          const SizedBox(height: 14),
          _label('Nombre del grupo'),
          _field(
            controller: _groupCtrl,
            hint: 'Ej: grupo1',
            icon: Icons.group_outlined,
          ),
          const SizedBox(height: 14),
          _label('Tu nombre'),
          _field(
            controller: _nameCtrl,
            hint: 'Cómo te verán los demás',
            icon: Icons.person_outline,
            caps: TextCapitalization.words,
          ),
          const SizedBox(height: 28),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: _connecting ? null : _connect,
              style: ElevatedButton.styleFrom(
                backgroundColor: _accent,
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: _connecting
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        color: Colors.black,
                        strokeWidth: 2.5,
                      ),
                    )
                  : const Text(
                      'Entrar al grupo',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 16),
          const Center(
            child: Text(
              'Asegúrate de estar en la misma red WiFi',
              style: TextStyle(color: _textMuted, fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    ),
  );

  Widget _label(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      text,
      style: const TextStyle(
        color: _textMuted,
        fontSize: 13,
        fontWeight: FontWeight.w500,
      ),
    ),
  );

  Widget _field({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    TextInputType? keyboardType,
    TextCapitalization caps = TextCapitalization.none,
  }) => TextField(
    controller: controller,
    keyboardType: keyboardType,
    textCapitalization: caps,
    style: const TextStyle(color: _textPrimary, fontSize: 15),
    decoration: InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: _textMuted, fontSize: 14),
      prefixIcon: Icon(icon, color: _textMuted, size: 20),
      filled: true,
      fillColor: _surface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _accent, width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
    ),
  );

  // ── UI CHAT ─────────────────────────────────────────────────────────
  Widget _buildChat() => SafeArea(
    child: Column(
      children: [
        Container(
          color: _surface,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: _accent.withOpacity(0.2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.group, color: _accent, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _groupCtrl.text,
                      style: const TextStyle(
                        color: _textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      _onlineCount == 1
                          ? '1 participante en línea'
                          : '$_onlineCount participantes en línea',
                      style: const TextStyle(color: _accent, fontSize: 12),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.logout, color: _textMuted, size: 20),
                onPressed: () => _disconnect(),
              ),
            ],
          ),
        ),
        Expanded(
          child: _messages.isEmpty
              ? const Center(
                  child: Text(
                    'No hay mensajes todavía',
                    style: TextStyle(color: _textMuted),
                  ),
                )
              : ListView.builder(
                  controller: _scrollCtrl,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  itemCount: _messages.length,
                  itemBuilder: (_, i) => _buildItem(_messages[i]),
                ),
        ),
        Container(
          color: _surface,
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          child: Row(
            children: [
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: _surface2,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: TextField(
                    controller: _msgCtrl,
                    style: const TextStyle(color: _textPrimary, fontSize: 15),
                    onSubmitted: (_) => _sendMessage(),
                    decoration: const InputDecoration(
                      hintText: 'Escribe un mensaje...',
                      hintStyle: TextStyle(color: _textMuted, fontSize: 14),
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 10,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: _sendMessage,
                child: Container(
                  width: 46,
                  height: 46,
                  decoration: const BoxDecoration(
                    color: _accent,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.send, color: Colors.black, size: 20),
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _buildItem(Map<String, dynamic> msg) {
    if (msg['type'] == 'system') {
      final isError = msg['isError'] == true;
      final isSuccess = msg['isSuccess'] == true;
      final color = isError
          ? _errorColor
          : isSuccess
          ? _successColor
          : _textMuted;
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: isError
                  ? _errorColor.withOpacity(0.12)
                  : isSuccess
                  ? _successColor.withOpacity(0.10)
                  : _surface2,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: color.withOpacity(0.3), width: 0.5),
            ),
            child: Text(
              msg['text'],
              textAlign: TextAlign.center,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
        ),
      );
    }

    final isMe = msg['isMe'] == true;
    final sender = msg['sender'] as String? ?? '';
    final text = msg['text'] as String? ?? '';
    final time = _formatTime(msg['ts'] as String? ?? '');

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: isMe
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isMe) ...[
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: _avatarColor(sender),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  _initials(sender),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),
          ],
          Flexible(
            child: Container(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.72,
              ),
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
              decoration: BoxDecoration(
                color: isMe ? _myBubble : _otherBubble,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: Radius.circular(isMe ? 16 : 4),
                  bottomRight: Radius.circular(isMe ? 4 : 16),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!isMe)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 3),
                      child: Text(
                        sender,
                        style: TextStyle(
                          color: _avatarColor(sender),
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  Text(
                    text,
                    style: const TextStyle(
                      color: _textPrimary,
                      fontSize: 15,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Align(
                    alignment: Alignment.bottomRight,
                    child: Text(
                      time,
                      style: const TextStyle(color: _textMuted, fontSize: 11),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (isMe) const SizedBox(width: 38),
        ],
      ),
    );
  }
}
