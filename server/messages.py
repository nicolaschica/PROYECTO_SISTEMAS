import threading
from datetime import datetime


# Manejar historial de mensajes por grupo, con idempotencia para evitar duplicados exactos consecutivos
class MessageService:
    def __init__(self):
        self._lock    = threading.Lock() 
        self._history = {}  # {group_id: [{sender, action, ts}]}



    # Guardar un mensaje en el historial de un grupo, evitando duplicados exactos consecutivos
    def save(self, group_id: str, sender: str, action: str) -> dict:
        with self._lock:
            msg = {
                "sender": sender,
                "action": action,
                "ts"    : datetime.utcnow().isoformat()
            }
            if group_id not in self._history:
                self._history[group_id] = []
            # Idempotencia: evitar duplicado exacto consecutivo
            hist = self._history[group_id]
            if hist and hist[-1]["sender"] == sender and hist[-1]["action"] == action:
                return hist[-1]
            hist.append(msg)
            return msg


    # Obtener el historial de mensajes de un grupo
    def get_history(self, group_id: str) -> list:
        with self._lock:
            return list(self._history.get(group_id, []))
