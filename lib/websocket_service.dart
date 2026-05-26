import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';

class WebSocketService {
  WebSocketChannel? _channel;
  StreamSubscription? _subscription; // ← guardar referencia al listener

  // Sirve para emitir manualmente eventos al stream, como errores o desconexiones
  final _controller = StreamController<Map<String, dynamic>>.broadcast();


  // Exponer el stream para que otros puedan escuchar eventos
  Stream<Map<String, dynamic>> get stream => _controller.stream;


  // Método para conectar al servidor WebSocket
  Future<void> connect(String serverIp, String groupId, String name) async {
    // Cancelar listener anterior antes de crear uno nuevo
    await _subscription?.cancel();
    _subscription = null;
    _channel?.sink.close();
    _channel = null;

    // Construir URI y conectar
    final uri = Uri.parse('ws://$serverIp:8000/ws/$groupId/$name');
    try {
      _channel = WebSocketChannel.connect(uri);

      // Registrar listener y guardar referencia
      _subscription = _channel!.stream.listen(
        (raw) {
          try {
            final data = jsonDecode(raw as String) as Map<String, dynamic>;
            _controller.add(data);

            // Si el mensaje es un evento de conexión exitosa, emitir evento específico
          } catch (_) {
            _controller.add({
              'type'   : 'error',
              'message': 'Error al leer respuesta del servidor.',
            });
          }
        },

        // Manejar desconexión y errores
        onDone: () {
          _controller.add({'type': 'event', 'event': 'disconnected'});
          _channel = null;
          _subscription = null;
        },

        // Manejar errores de conexión
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

      // Esperar a que la conexión esté lista
      await _channel!.ready;


    // Manejar timeout de conexión
    } catch (_) {
      _controller.add({
        'type'   : 'error',
        'message': 'No se pudo conectar. Valida la información ingresada e intenta nuevamente.',
      });
      _channel = null;
      _subscription = null;
    }
  }

  // Método para enviar acciones al servidor
  void sendAction(String action) {
    if (_channel == null) return;
    try {
      _channel!.sink.add(jsonEncode({'type': 'action', 'action': action}));
    } catch (_) {}
  }


  // Método para desconectar manualmente
  void disconnect() {
    _subscription?.cancel();
    _subscription = null;
    _channel?.sink.close();
    _channel = null;
  }
}