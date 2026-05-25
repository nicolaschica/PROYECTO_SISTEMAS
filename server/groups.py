import threading


# Manejar grupos de dispositivos conectados a través de WebSockets
class GroupService:
    def __init__(self):
        self._lock   = threading.Lock()
        self._groups = {}  # {group_id: {device_id: {name, ip, ws}}}
        
        
    # Unirse a un grupo
    def join(self, group_id: str, device_id: str, name: str, ip: str, ws):
        with self._lock:
            if group_id not in self._groups:
                self._groups[group_id] = {}
            self._groups[group_id][device_id] = {"name": name, "ip": ip, "ws": ws}

    # Salir de un grupo
    def leave(self, group_id: str, device_id: str):
        with self._lock:
            if group_id in self._groups:
                self._groups[group_id].pop(device_id, None)

    # Obtener miembros de un grupo
    def get_members(self, group_id: str) -> list:
        with self._lock:
            return list(self._groups.get(group_id, {}).values())

    # Obtener websockets de un grupo, excluyendo un dispositivo específico 
    def get_websockets(self, group_id: str, exclude_id: str = None) -> list:
        with self._lock:
            members = self._groups.get(group_id, {})
            return [m["ws"] for did, m in members.items() if did != exclude_id]
