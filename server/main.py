import asyncio
import json
import uvicorn
from datetime import datetime
from fastapi import FastAPI, WebSocket, WebSocketDisconnect
from identity import IdentityService
from groups import GroupService
from messages import MessageService


# Colores y formatos para logs en consola
class C:
    RESET   = "\033[0m";  BOLD    = "\033[1m"
    GREEN   = "\033[92m"; RED     = "\033[91m"
    YELLOW  = "\033[93m"; CYAN    = "\033[96m"
    WHITE   = "\033[97m"; GRAY    = "\033[90m"
    MAGENTA = "\033[95m"


# Funciones de logging
def now() -> str:
    return datetime.now().strftime("%H:%M:%S")

# Separador visual para logs
def sep():
    print(f"{C.GRAY}{'─' * 60}{C.RESET}")


# Logs de eventos
def log_startup():
    print(f"\n{C.WHITE}{C.BOLD}")
    print("  ╔══════════════════════════════════════════════╗")
    print("  ║       SERVIDOR WEBSOCKET — EN LÍNEA          ║")
    print("  ║       Host: 0.0.0.0   |   Puerto: 8000       ║")
    print(f"  ╚══════════════════════════════════════════════╝{C.RESET}")
    print(f"  {C.GREEN}✔  Listo para recibir conexiones{C.RESET}")
    print(f"  {C.GRAY}Iniciado: {now()}{C.RESET}\n")


# Logs de eventos de conexión, desconexión, mensajes, colisiones y errores
def log_connect(group_id, name, ip, total):
    sep()
    print(f"  {C.GREEN}{C.BOLD}▶  NUEVO PARTICIPANTE{C.RESET}")
    print(f"  {C.GRAY}Hora     {C.RESET}: {C.WHITE}{now()}{C.RESET}")
    print(f"  {C.GRAY}Nombre   {C.RESET}: {C.CYAN}{C.BOLD}{name}{C.RESET}")
    print(f"  {C.GRAY}Grupo    {C.RESET}: {C.WHITE}{group_id}{C.RESET}")
    print(f"  {C.GRAY}IP       {C.RESET}: {C.WHITE}{ip}{C.RESET}")
    print(f"  {C.GRAY}En línea {C.RESET}: {C.GREEN}{total} dispositivo(s){C.RESET}")
    sep()


# Logs de desconexión
def log_disconnect(group_id, name, ip, total):
    sep()
    print(f"  {C.RED}{C.BOLD}◀  PARTICIPANTE SALIÓ{C.RESET}")
    print(f"  {C.GRAY}Hora     {C.RESET}: {C.WHITE}{now()}{C.RESET}")
    print(f"  {C.GRAY}Nombre   {C.RESET}: {C.CYAN}{name}{C.RESET}")
    print(f"  {C.GRAY}Grupo    {C.RESET}: {C.WHITE}{group_id}{C.RESET}")
    print(f"  {C.GRAY}IP       {C.RESET}: {C.WHITE}{ip}{C.RESET}")
    print(f"  {C.GRAY}En línea {C.RESET}: {C.YELLOW}{total} dispositivo(s){C.RESET}")
    sep()


# Logs de mensajes
def log_message(group_id, name, action, total):
    print(f"  {C.MAGENTA}●{C.RESET} {C.WHITE}{now()}{C.RESET} "
          f"{C.GRAY}[{group_id}]{C.RESET} "
          f"{C.CYAN}{C.BOLD}{name}{C.RESET}{C.GRAY} →{C.RESET} "
          f"{C.WHITE}{action}{C.RESET} {C.GRAY}({total} en línea){C.RESET}")


# Logs de colisiones de nombres
def log_collision(name, ip):
    sep()
    print(f"  {C.YELLOW}{C.BOLD}⚠  COLISIÓN DE NOMBRE{C.RESET}")
    print(f"  {C.GRAY}Nombre   {C.RESET}: {C.CYAN}{name}{C.RESET}")
    print(f"  {C.GRAY}IP       {C.RESET}: {C.WHITE}{ip}{C.RESET}")
    print(f"  {C.GRAY}Motivo   {C.RESET}: {C.YELLOW}Ya está en uso por otro dispositivo{C.RESET}")
    sep()


# Logs de errores
def log_error(context, detail):
    print(f"  {C.RED}{C.BOLD}✖  ERROR{C.RESET} {C.GRAY}[{context}]{C.RESET}: {C.RED}{detail}{C.RESET}")


# Logs de envío de historial
def log_history(name, count):
    print(f"  {C.GRAY}↩  Historial enviado a {C.CYAN}{name}{C.RESET}"
          f"{C.GRAY}: {count} mensaje(s){C.RESET}")


# Inicialización de servicios y aplicación FastAPI
app          = FastAPI()
identity_svc = IdentityService()
group_svc    = GroupService()
message_svc  = MessageService()


# Evento de inicio del servidor
@app.on_event("startup")
async def on_startup():
    log_startup()


# WebSocket endpoint para manejar conexiones de clientes
@app.websocket("/ws/{group_id}/{name}")
async def websocket_endpoint(ws: WebSocket, group_id: str, name: str):
    await ws.accept()
    ip        = ws.client.host
    device_id = f"{ip}:{ws.client.port}"

    # Validar nombre
    result = identity_svc.register(name, device_id)
    if not result["ok"]:
        log_collision(name, ip)
        await ws.send_text(json.dumps({
            "type"   : "error",
            "message": f"El nombre '{name}' ya está en uso. Por favor elige otro nombre."
        }))
        await ws.close()
        return

    # Unir al grupo
    group_svc.join(group_id, device_id, name, ip, ws)
    total = len(identity_svc.get_all_names())
    log_connect(group_id, name, ip, total)

    # Notificar a los DEMÁS que alguien entró
    await _broadcast(group_id, device_id, {
        "type"   : "event",
        "event"  : "join",
        "sender" : name,
        "members": identity_svc.get_all_names()
    })

    # Confirmar conexión al propio dispositivo
    await ws.send_text(json.dumps({
        "type"   : "event",
        "event"  : "join",
        "sender" : name,
        "members": identity_svc.get_all_names()
    }))

    # Enviar historial al reconectar
    history = message_svc.get_history(group_id)
    await ws.send_text(json.dumps({
        "type"    : "history",
        "messages": history
    }))
    if history:
        log_history(name, len(history))

    # Loop principal
    try:
        while True:
            raw  = await ws.receive_text()
            data = json.loads(raw)

            if data.get("type") == "action":
                action = data.get("action", "").strip()
                if not action:
                    continue

                msg     = message_svc.save(group_id, name, action)
                members = group_svc.get_members(group_id)
                log_message(group_id, name, action, len(members))

                payload = {
                    "type"  : "action",
                    "sender": name,
                    "action": action,
                    "ts"    : msg["ts"]
                }

                # Broadcast a los DEMÁS (excluye al emisor)
                await _broadcast(group_id, device_id, payload)

                # Enviar UNA SOLA VEZ al emisor
                await ws.send_text(json.dumps(payload))



    # Manejar desconexión
    except WebSocketDisconnect:
        group_svc.leave(group_id, device_id)
        identity_svc.unregister(device_id)
        remaining = len(identity_svc.get_all_names())
        log_disconnect(group_id, name, ip, remaining)
        await _broadcast(group_id, device_id, {
            "type"   : "event",
            "event"  : "leave",
            "sender" : name,
            "members": identity_svc.get_all_names()
        })


    # Manejar otros errores
    except Exception as e:
        log_error(name, str(e))
        try:
            await ws.send_text(json.dumps({
                "type"   : "error",
                "message": "Ocurrió un problema. Por favor reconéctate."
            }))
        except Exception:
            pass


# Función para hacer broadcast lo cual significa enviar a todos en un grupo, excluyendo un dispositivo específico
async def _broadcast(group_id: str, exclude_id: str, payload: dict):
    sockets = group_svc.get_websockets(group_id, exclude_id=exclude_id)
    await _broadcast_list(sockets, payload)


# Función para enviar un payload lo cual significa enviar a una lista de websockets, manejando errores
async def _broadcast_list(sockets: list, payload: dict, context: str = "server"):
    if not sockets:
        return
    text    = json.dumps(payload)
    results = await asyncio.gather(
        *[s.send_text(text) for s in sockets],
        return_exceptions=True
    )
    for r in results:
        if isinstance(r, Exception):
            print(f"  {C.YELLOW}⚠  Broadcast fallido [{context}]: {r}{C.RESET}")


# Punto de entrada para ejecutar el servidor
if __name__ == "__main__":
    uvicorn.run("main:app", host="0.0.0.0", port=8000, reload=False)