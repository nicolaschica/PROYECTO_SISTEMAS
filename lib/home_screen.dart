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
  final _ws         = WebSocketService();
  final _serverCtrl = TextEditingController(text: '20.20.1.185');
  final _groupCtrl  = TextEditingController(text: 'grupo1');
  final _nameCtrl   = TextEditingController();
  final _msgCtrl    = TextEditingController();
  final _scrollCtrl = ScrollController();

  // ── FIX DUPLICADOS: referencia única al listener ──────────────────
  StreamSubscription? _streamSub;
  bool   _connected   = false;
  bool   _connecting  = false;
  String _myName      = '';
  int    _onlineCount = 0;
  final List<Map<String, dynamic>> _messages = [];

  static const _bg          = Color(0xFF0A0A0A);
  static const _surface     = Color(0xFF1A1A1A);
  static const _surface2    = Color(0xFF252525);
  static const _accent      = Color(0xFF25D366);
  static const _myBubble    = Color(0xFF005C4B);
  static const _otherBubble = Color(0xFF1F2C34);
  static const _textPrimary = Color(0xFFE9EDEF);
  static const _textMuted   = Color(0xFF8696A0);
  static const _errorColor  = Color(0xFFFF4444);
  static const _successColor = Color(0xFF25D366);

  // ── CONECTAR ─────────────────────────────────────────────────────────
  void _connect() async {
    final ip    = _serverCtrl.text.trim();
    final group = _groupCtrl.text.trim();
    final name  = _nameCtrl.text.trim();

    // Validar campos vacíos con alerta personalizada para cada uno
    if (ip.isEmpty) {
      _showFieldAlert(
        icon: Icons.wifi_off_rounded,
        iconColor: const Color(0xFFE6A817),
        title: 'Campo vacío',
        message: 'Ingresa la dirección',
        buttonText: 'Entendido',
      );
      return;
    }
    if (group.isEmpty) {
      _showFieldAlert(
        icon: Icons.group_off_outlined,
        iconColor: const Color(0xFF00B4D8),
        title: 'Nombre de grupo vacío',
        message: 'Escribe el nombre del grupo al que quieres unirte.\nEjemplo: grupo1',
        buttonText: 'Entendido',
      );
      return;
    }
    if (name.isEmpty) {
      _showFieldAlert(
        icon: Icons.person_off_outlined,
        iconColor: const Color(0xFFE24B4A),
        title: 'Tu nombre está vacío',
        message: 'Necesitas un nombre para que los demás sepan quién eres en el grupo.',
        buttonText: 'Ponerle nombre',
      );
      return;
    }

    setState(() => _connecting = true);

    // FIX: cancelar suscripción anterior y limpiar TODOS los mensajes
    await _streamSub?.cancel();
    _streamSub = null;
    _messages.clear();

    // Registrar listener y guardar referencia única
    _streamSub = _ws.stream.listen((msg) {
      if (!mounted) return;
      setState(() {
        switch (msg['type']) {
          
          // Manejar errores enviados desde el WebSocket
          case 'error':
            _connecting = false;
            _connected  = false;
            _addSystemMsg(msg['message'] ?? 'Error desconocido.', isError: true);
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              final errMsg = (msg['message'] as String? ?? '').toLowerCase();
              final isNameCollision =
                  errMsg.contains('nombre') && errMsg.contains('uso');
              _showFriendlyAlert(isNameCollision: isNameCollision);
            });
            break;

          // Manejar eventos del servidor
          case 'event':
            _connecting = false;
            final ev      = msg['event'] as String? ?? '';
            final members = (msg['members'] as List?)?.cast<String>() ?? [];
            _onlineCount  = members.length;


            // Si el evento es 'join' y el remitente es el usuario actual, marcar como conectado
            if (ev == 'join' && msg['sender'] == name) {
              _connected = true;
              _myName    = name;
              _addSystemMsg(
                '¡Bienvenido al grupo "$group"! Hay $_onlineCount persona(s) conectada(s).',
                isSuccess: true,
              );
              // Si el evento es 'join' mostrar mensaje de sistema correspondiente
            } else if (ev == 'join') {
              _addSystemMsg('${msg['sender']} se unió al grupo.');
              // Si el evento es 'leave', mostrar mensaje de sistema correspondiente
            } else if (ev == 'leave') {
              _addSystemMsg('${msg['sender']} abandonó el grupo.');
              // Si el evento es 'disconnected', mostrar mensaje de sistema correspondiente y marcar como desconectado
            } else if (ev == 'disconnected') {
              _connected   = false;
              _onlineCount = 0;
              _addSystemMsg(
                'Perdiste la conexión. Vuelve a conectarte cuando tengas señal.',
                isError: true,
              );
            }
            break;

          case 'action':
            _messages.add({
              'type'  : 'message',
              'sender': msg['sender'] ?? '',
              'text'  : msg['action'] ?? '',
              'ts'    : msg['ts']    ?? '',
              'isMe'  : (msg['sender'] ?? '') == _myName && _myName.isNotEmpty,
            });
            _scrollToBottom();
            break;


          // Manejar historial de mensajes al conectar
          case 'history':
            // El servidor envía un evento 'history' con los mensajes que se perdieron mientras el usuario estaba desconectado
            final history = (msg['messages'] as List? ?? [])
                .cast<Map<String, dynamic>>();
            if (history.isNotEmpty) {
              _addSystemMsg(
                'Se recuperaron ${history.length} mensaje(s) enviados mientras estabas desconectado.',
                isSuccess: true,
              );
              // Agregar cada mensaje del historial a la lista de mensajes y marcar si es del usuario actual
              for (final h in history) {
                _messages.add({
                  'type'  : 'message',
                  'sender': h['sender'] ?? '',
                  'text'  : h['action'] ?? '',
                  'ts'    : h['ts']    ?? '',
                  'isMe'  : (h['sender'] ?? '') == _myName && _myName.isNotEmpty,
                });
              }
              _scrollToBottom();
            }
            break;
        }
      });
    });

    // Conectar DESPUÉS de registrar el listener
    await _ws.connect(ip, group, name);
  }

  // ── ENVIAR MENSAJE ────────────────────────────────────────────────────
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

  // ── DESCONECTAR ───────────────────────────────────────────────────────
  void _disconnect() async {
    await _streamSub?.cancel();
    _streamSub = null;
    _ws.disconnect();
    setState(() {
      _connected   = false;
      _connecting  = false;
      _onlineCount = 0;
      _addSystemMsg('Saliste del grupo correctamente.');
    });
  }

  // ── ALERTAS ───────────────────────────────────────────────────────────
  void _showFieldAlert({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String message,
    required String buttonText,
  }) {
    showDialog(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withValues(alpha: 0.6),
      builder: (ctx) => Dialog(
        backgroundColor: const Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 32, 28, 24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 72, height: 72,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 32, color: iconColor),
            ),
            const SizedBox(height: 20),
            Text(title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: Color(0xFFE9EDEF),
                  fontSize: 18,
                  fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Text(message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: Color(0xFF8696A0), fontSize: 14, height: 1.6)),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity, height: 46,
              child: ElevatedButton(
                onPressed: () => Navigator.of(ctx).pop(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF25D366),
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: Text(buttonText,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.bold)),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  void _showFriendlyAlert({required bool isNameCollision}) {
    showDialog(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withValues(alpha: 0.6),
      builder: (ctx) => Dialog(
        backgroundColor: const Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 32, 28, 24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 72, height: 72,
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
              isNameCollision ? 'Ese nombre ya está en uso' : 'Sin conexión',
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: Color(0xFFE9EDEF),
                  fontSize: 18,
                  fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Text(
              isNameCollision
                  ? 'Alguien en el grupo ya usa ese nombre. Prueba con uno diferente.'
                  : 'No pudimos conectarnos. Intentalo nuevamente',
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: Color(0xFF8696A0), fontSize: 14, height: 1.6)),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity, height: 46,
              child: ElevatedButton(
                onPressed: () => Navigator.of(ctx).pop(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF25D366),
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: Text(
                  isNameCollision ? 'Elegir otro nombre' : 'Entendido',
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.bold)),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  // ── HELPERS ───────────────────────────────────────────────────────────
  void _addSystemMsg(String text,
      {bool isError = false, bool isSuccess = false}) {
    _messages.add({
      'type'     : 'system',
      'text'     : text,
      'isError'  : isError,
      'isSuccess': isSuccess,
    });
    _scrollToBottom();
  }


  // Scroll automático al agregar un nuevo mensaje, con verificación de que el widget sigue montado
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


  // Mostrar un SnackBar (es decir, un mensaje emergente) con un mensaje, usando colores diferentes para errores y éxitos
  void _toast(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError ? _errorColor : _successColor,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }


  // Formatear la marca de tiempo del mensaje para mostrar solo la hora y minutos
  String _formatTime(String ts) {
    if (ts.length < 16) return '';
    try {
      final dt = DateTime.parse(ts).toLocal();
      return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return ts.length >= 16 ? ts.substring(11, 16) : '';
    }
  }


  // Generar iniciales para el avatar a partir del nombre, tomando la primera letra de las dos primeras palabras o solo la primera letra si es un nombre simple
  String _initials(String name) {
    final parts = name.trim().split(' ');
    if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    return name.isNotEmpty ? name[0].toUpperCase() : '?';
  }

  Color _avatarColor(String name) {
    const colors = [
      Color(0xFF6B4EFF), Color(0xFFFF6B35), Color(0xFF00B4D8),
      Color(0xFFE63946), Color(0xFF2EC4B6), Color(0xFFFF9F1C),
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

  // refactorizar para separar en widgets más pequeños y mejorar legibilidad
  @override
  Widget build(BuildContext context) {
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Color(0xFF1A1A1A),
      statusBarIconBrightness: Brightness.light,
    ));
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

  // Widgets para construir la interfaz de login y chat, con campos de texto personalizados, botones estilizados y mensajes de sistema diferenciados visualmente
  Widget _buildLogin() => SafeArea(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const SizedBox(height: 40),
        Center(child: Column(children: [
          Container(
            width: 80, height: 80,
            decoration: BoxDecoration(
              color: _accent.withValues(alpha: 0.15),
              shape: BoxShape.circle,
              border: Border.all(color: _accent, width: 2),
            ),
            child: const Icon(Icons.chat_bubble_outline, color: _accent, size: 36),
          ),
          const SizedBox(height: 16),
          const Text('Chat en tiempo real',
              style: TextStyle(color: _textPrimary, fontSize: 24,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          const Text('Conecta con tu grupo al instante',
              style: TextStyle(color: _textMuted, fontSize: 14)),
        ])),
        // const SizedBox(height: 48),
        // _label('IP del servidor'),
        // _darkField(controller: _serverCtrl, hint: 'Ej: 192.168.1.100',
        //     icon: Icons.wifi,
        //     keyboardType: TextInputType.numberWithOptions(decimal: true)),
        const SizedBox(height: 16),
        _label('Nombre del grupo'),
        _darkField(controller: _groupCtrl, hint: 'Ej: grupo1',
            icon: Icons.group_outlined),
        const SizedBox(height: 16),
        _label('Tu nombre'),
        _darkField(controller: _nameCtrl, hint: 'Cómo te verán los demás',
            icon: Icons.person_outline,
            textCapitalization: TextCapitalization.words),
        const SizedBox(height: 32),
        SizedBox(
          width: double.infinity, height: 52,
          child: ElevatedButton(
            onPressed: _connecting ? null : _connect,
            style: ElevatedButton.styleFrom(
              backgroundColor: _accent,
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
            child: _connecting
                ? const SizedBox(width: 22, height: 22,
                    child: CircularProgressIndicator(
                        color: Colors.black, strokeWidth: 2.5))
                : const Text('Entrar al grupo',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ),
        ),
        const SizedBox(height: 16),
        const Center(child: Text(
          'Asegúrate de estar en la misma red',
          style: TextStyle(color: _textMuted, fontSize: 12),
          textAlign: TextAlign.center,
        )),
      ]),
    ),
  );

  Widget _label(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(text, style: const TextStyle(
        color: _textMuted, fontSize: 13, fontWeight: FontWeight.w500)),
  );

  Widget _darkField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    TextInputType? keyboardType,
    TextCapitalization textCapitalization = TextCapitalization.none,
  }) => TextField(
    controller: controller,
    keyboardType: keyboardType,
    textCapitalization: textCapitalization,
    style: const TextStyle(color: _textPrimary, fontSize: 15),
    decoration: InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: _textMuted, fontSize: 14),
      prefixIcon: Icon(icon, color: _textMuted, size: 20),
      filled: true, fillColor: _surface,
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _accent, width: 1.5)),
      contentPadding:
          const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
    ),
  );

  // ── CHAT ──────────────────────────────────────────────────────────────
  Widget _buildChat() => SafeArea(
    child: Column(children: [

      // Header
      Container(
        color: _surface,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(children: [
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(
              color: _accent.withValues(alpha: 0.2), shape: BoxShape.circle),
            child: const Icon(Icons.group, color: _accent, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_groupCtrl.text,
                  style: const TextStyle(color: _textPrimary,
                      fontSize: 16, fontWeight: FontWeight.bold)),
              Text(
                _onlineCount == 1
                    ? '1 participante en línea'
                    : '$_onlineCount participantes en línea',
                style: const TextStyle(color: _accent, fontSize: 12),
              ),
            ],
          )),
          IconButton(
            icon: const Icon(Icons.logout, color: _textMuted, size: 20),
            tooltip: 'Salir del grupo',
            onPressed: () => showDialog(
              context: context,
              builder: (_) => AlertDialog(
                backgroundColor: _surface2,
                title: const Text('¿Salir del grupo?',
                    style: TextStyle(color: _textPrimary)),
                content: const Text(
                    'Perderás la conexión y deberás volver a ingresar.',
                    style: TextStyle(color: _textMuted)),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancelar',
                        style: TextStyle(color: _textMuted))),
                  TextButton(
                    onPressed: () {
                      Navigator.pop(context);
                      _disconnect();
                    },
                    child: const Text('Salir',
                        style: TextStyle(color: _errorColor))),
                ],
              ),
            ),
          ),
        ]),
      ),

      // Mensajes
      Expanded(
        child: _messages.isEmpty
            ? const Center(child: Column(
                mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.chat_bubble_outline,
                      color: Color(0xFF3A3A3A), size: 48),
                  SizedBox(height: 12),
                  Text('Aún no hay mensajes.\n¡Sé el primero en escribir!',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: _textMuted, fontSize: 14)),
                ]))
            : ListView.builder(
                controller: _scrollCtrl,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                itemCount: _messages.length,
                itemBuilder: (_, i) => _buildItem(_messages[i]),
              ),
      ),

      // Input de mensaje (sin botones rápidos)
      Container(
        color: _surface,
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: Row(children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: _surface2,
                borderRadius: BorderRadius.circular(24),
              ),
              child: TextField(
                controller: _msgCtrl,
                style: const TextStyle(color: _textPrimary, fontSize: 15),
                textCapitalization: TextCapitalization.sentences,
                maxLines: 4, minLines: 1,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _sendMessage(),
                decoration: const InputDecoration(
                  hintText: 'Escribe un mensaje...',
                  hintStyle: TextStyle(color: _textMuted, fontSize: 14),
                  border: InputBorder.none,
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: _sendMessage,
            child: Container(
              width: 46, height: 46,
              decoration: const BoxDecoration(
                  color: _accent, shape: BoxShape.circle),
              child: const Icon(Icons.send, color: Colors.black, size: 20),
            ),
          ),
        ]),
      ),
    ]),
  );

  // ── ITEMS DEL CHAT ────────────────────────────────────────────────────
  Widget _buildItem(Map<String, dynamic> msg) {
    if (msg['type'] == 'system') {
      final isError   = msg['isError']   == true;
      final isSuccess = msg['isSuccess'] == true;
      final color = isError ? _errorColor
          : isSuccess ? _successColor
          : _textMuted;
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Center(child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: isError ? _errorColor.withValues(alpha: 0.15)
                : isSuccess ? _successColor.withValues(alpha: 0.12)
                : _surface2,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withValues(alpha: 0.3), width: 0.5),
          ),
          child: Text(msg['text'],
              textAlign: TextAlign.center,
              style: TextStyle(color: color, fontSize: 12,
                  fontStyle: FontStyle.italic)),
        )),
      );
    }


    // Para mensajes normales, determinar si el mensaje es del usuario actual (isMe), obtener el remitente, el texto y formatear la hora
    final isMe   = msg['isMe'] == true;
    final sender = msg['sender'] as String? ?? '';
    final text   = msg['text']  as String? ?? '';
    final time   = _formatTime(msg['ts'] as String? ?? '');


    // Construir la burbuja del mensaje, alineada a la derecha si es del usuario actual y a la izquierda si es de otro, con estilos diferentes para cada caso y 
    //mostrando el avatar e iniciales del remitente en mensajes de otros usuarios
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment:
            isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isMe) ...[
            Container(
              width: 32, height: 32,
              decoration: BoxDecoration(
                  color: _avatarColor(sender), shape: BoxShape.circle),
              child: Center(child: Text(_initials(sender),
                  style: const TextStyle(color: Colors.white,
                      fontSize: 12, fontWeight: FontWeight.bold))),
            ),
            const SizedBox(width: 6),
          ],
          // Construir la burbuja del mensaje
          Flexible(child: Container(
            constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.72),
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
            decoration: BoxDecoration(
              color: isMe ? _myBubble : _otherBubble,
              borderRadius: BorderRadius.only(
                topLeft:     const Radius.circular(16),
                topRight:    const Radius.circular(16),
                bottomLeft:  Radius.circular(isMe ? 16 : 4),
                bottomRight: Radius.circular(isMe ? 4 : 16),
              ),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (!isMe)
                Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: Text(sender,
                      style: TextStyle(color: _avatarColor(sender),
                          fontSize: 12, fontWeight: FontWeight.bold)),
                ),
              Text(text, style: const TextStyle(
                  color: _textPrimary, fontSize: 15, height: 1.3)),
              const SizedBox(height: 3),
              Align(
                alignment: Alignment.bottomRight,
                child: Text(time, style: const TextStyle(
                    color: _textMuted, fontSize: 11)),
              ),
            ]),
          )),
          if (isMe) const SizedBox(width: 38),
        ],
      ),
    );
  }
}