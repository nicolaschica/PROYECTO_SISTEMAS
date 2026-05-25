import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';

class WebSocketService {
  WebSocketChannel? _channel;
  StreamSubscription? _subscription; // ← guardar referencia al listener
  final _controller = StreamController<Map<String, dynamic>>.broadcast();

  Stream<Map<String, dynamic>> get stream => _controller.stream;

  Future<void> connect(String serverIp, String groupId, String name) async {
    // Cancelar listener anterior antes de crear uno nuevo
    await _subscription?.cancel();
    _subscription = null;
    _channel?.sink.close();
    _channel = null;

    final uri = Uri.parse('ws://$serverIp:8000/ws/$groupId/$name');
    try {
      _channel = WebSocketChannel.connect(uri);

      // Registrar listener y guardar referencia
      _subscription = _channel!.stream.listen(
        (raw) {
          try {
            final data = jsonDecode(raw as String) as Map<String, dynamic>;
            _controller.add(data);
          } catch (_) {
            _controller.add({
              'type'   : 'error',
              'message': 'Error al leer respuesta del servidor.',
            });
          }
        },
        onDone: () {
          _controller.add({'type': 'event', 'event': 'disconnected'});
          _channel = null;
          _subscription = null;
        },
        onError: (_) {
          _controller.add({
            'type'   : 'error',
            'message': 'Se perdió la conexión. Verifica tu red e intenta reconectarte.',
          });
          _channel = null;
          _subscription = null;
        },
        cancelOnError: false,
      );

      // Esperar handshake DESPUÉS del listener
      await _channel!.ready;

    } catch (_) {
      _controller.add({
        'type'   : 'error',
        'message': 'No se pudo encontrar el servidor. Verifica la IP y que estés en la misma red WiFi.',
      });
      _channel = null;
      _subscription = null;
    }
  }

  void sendAction(String action) {
    if (_channel == null) return;
    try {
      _channel!.sink.add(jsonEncode({'type': 'action', 'action': action}));
    } catch (_) {}
  }

  void disconnect() {
    _subscription?.cancel();
    _subscription = null;
    _channel?.sink.close();
    _channel = null;
  }
}