import threading


# Manejar registro de nombres únicos para dispositivos
class IdentityService:
    def __init__(self):
        self._lock  = threading.Lock()
        self._names = {}  # {name: device_id}


    # Registrar un nombre único para un dispositivo
    def register(self, name: str, device_id: str) -> dict:
        with self._lock:
            if name in self._names:
                if self._names[name] == device_id:
                    return {"ok": True, "message": "Ya registrado"}
                return {"ok": False, "message": f"Nombre '{name}' ya está en uso"}
            self._names[name] = device_id
            return {"ok": True, "message": "Registrado exitosamente"}


    # Eliminar el registro de un dispositivo
    def unregister(self, device_id: str):
        with self._lock:
            to_remove = [n for n, d in self._names.items() if d == device_id]
            for name in to_remove:
                del self._names[name]

    # Obtener todos los nombres registrados
    def get_all_names(self) -> list:
        with self._lock:
            return list(self._names.keys())
