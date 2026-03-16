import http.client
import json
import os
import posixpath
import secrets
import threading
import time
import urllib.parse
from http import HTTPStatus
from http.cookies import SimpleCookie
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

BASE_DIR = Path.home() / "PersonalCloud"
DATA_ROOT = Path("D:/CloudDrive").resolve()
BACKEND_HOST = "127.0.0.1"
BACKEND_PORT = 8396
LISTEN_HOST = "0.0.0.0"
LISTEN_PORT = 8394
CREDENTIALS_FILE = BASE_DIR / "credentials.txt"
SESSION_COOKIE = "pc_upload_session"
SESSION_TTL = 12 * 60 * 60
MAX_UPLOAD = 20 * 1024 * 1024 * 1024
CHUNK_BYTES = 1 * 1024 * 1024
MAX_CHUNK_BYTES = 32 * 1024 * 1024
UPLOAD_PARTS_DIR = DATA_ROOT / ".pc-upload-parts"
HOP_HEADERS = {"connection", "keep-alive", "proxy-authenticate", "proxy-authorization", "te", "trailers", "transfer-encoding", "upgrade"}
SESSIONS = {}
LOCK = threading.Lock()


def load_password():
    for line in CREDENTIALS_FILE.read_text(encoding="ascii", errors="ignore").splitlines():
        if line.startswith("Senha:"):
            return line.split(":", 1)[1].strip()
    raise RuntimeError("Senha nao encontrada")


USERNAME = "cloud"
PASSWORD = load_password()


def cleanup_sessions():
    now = time.time()
    with LOCK:
        expired = [token for token, expiry in SESSIONS.items() if expiry < now]
        for token in expired:
            SESSIONS.pop(token, None)


def create_session():
    token = secrets.token_urlsafe(32)
    with LOCK:
        SESSIONS[token] = time.time() + SESSION_TTL
    return token


def valid_session(token):
    cleanup_sessions()
    with LOCK:
        expiry = SESSIONS.get(token)
        if not expiry:
            return False
        SESSIONS[token] = time.time() + SESSION_TTL
        return True


def drop_session(token):
    with LOCK:
        SESSIONS.pop(token, None)


def safe_target(raw_path):
    value = urllib.parse.unquote(raw_path or "").replace("\\", "/").strip()
    if not value:
        raise ValueError("Caminho vazio")
    normalized = posixpath.normpath("/" + value).lstrip("/")
    if normalized in ("", "."):
        raise ValueError("Caminho invalido")
    target = (DATA_ROOT / normalized).resolve()
    target.relative_to(DATA_ROOT)
    return target


def safe_upload_id(raw_value):
    value = (raw_value or "").strip()
    allowed = set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_")
    if not value or len(value) > 120 or any(ch not in allowed for ch in value):
        raise ValueError("Identificador de upload invalido.")
    return value


def relative_target(target):
    return str(target.relative_to(DATA_ROOT)).replace("\\", "/")


def partial_paths(upload_id):
    return UPLOAD_PARTS_DIR / f"{upload_id}.part", UPLOAD_PARTS_DIR / f"{upload_id}.json"


def stream_to_file(stream, destination, size, mode):
    remaining = size
    with open(destination, mode) as fh:
        while remaining > 0:
            chunk = stream.read(min(1024 * 1024, remaining))
            if not chunk:
                break
            fh.write(chunk)
            remaining -= len(chunk)
    if remaining != 0:
        raise IOError("Upload interrompido")


PAGE = """<!doctype html>
<html lang="pt-BR"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Upload com progresso</title>
<style>
body{margin:0;font-family:Segoe UI,system-ui,sans-serif;background:#f4efe5;color:#1f2933}
.wrap{max-width:1040px;margin:24px auto;padding:0 16px}
.hero,.card{background:#fff;border-radius:24px;box-shadow:0 14px 36px rgba(0,0,0,.08);padding:22px}
.hero{background:linear-gradient(135deg,#1463ff,#18a05e);color:#fff}
.grid{display:grid;grid-template-columns:320px 1fr;gap:18px;margin-top:18px}
label{display:block;margin:12px 0 6px;font-size:12px;font-weight:700;letter-spacing:.08em;text-transform:uppercase;color:#5d6b78}
input[type=text],input[type=password]{width:100%;padding:12px 14px;border:1px solid #d9cdbb;border-radius:14px;background:#fff;font:inherit}
button,a.btn{display:inline-flex;align-items:center;justify-content:center;gap:8px;padding:12px 16px;border-radius:14px;border:0;background:#1463ff;color:#fff;font:inherit;font-weight:700;text-decoration:none;cursor:pointer}
button.alt,a.alt{background:#fff;color:#1f2933;border:1px solid #d9cdbb}
button:disabled{opacity:.55;cursor:not-allowed}
.actions{display:flex;flex-wrap:wrap;gap:10px;margin-top:14px}
.drop{margin-top:14px;min-height:170px;border:2px dashed #8fb0ec;border-radius:22px;display:grid;place-items:center;text-align:center;background:#eef4ff;padding:18px}
.drop.drag{background:#dbe8ff}
.pill{display:inline-flex;padding:8px 12px;border-radius:999px;background:#fff1c7;color:#7a5200;font-size:13px;font-weight:700}
.ok{background:#d8f5e4;color:#14663f}.err{background:#fee4e2;color:#b42318}
.stats{display:grid;grid-template-columns:repeat(3,1fr);gap:12px;margin-top:16px}
.stat{background:#fff;border:1px solid #eadfce;border-radius:18px;padding:14px}.stat strong{display:block;font-size:24px;margin-top:6px}
.bar{height:14px;border-radius:999px;background:#dbe3ee;overflow:hidden;margin-top:10px}.fill{height:100%;width:0;background:linear-gradient(90deg,#1463ff,#1eb96d)}
.queue{margin-top:18px;border:1px solid #eadfce;border-radius:20px;overflow:hidden;background:#fff}.head,.row{display:grid;grid-template-columns:2fr 1.3fr 120px;gap:12px;padding:14px 16px;align-items:center}
.head{background:#f9f4ea;font-size:12px;font-weight:700;color:#5d6b78;text-transform:uppercase;letter-spacing:.08em}.row{border-top:1px solid #f0e7da}.name{font-weight:700;word-break:break-word}.sub{font-size:13px;color:#5d6b78;margin-top:4px;word-break:break-word}.state{text-align:right;font-size:13px;font-weight:700}.state.ok{color:#14663f}.state.err{color:#b42318}
.hidden{display:none!important}.muted{font-size:14px;color:#5d6b78}
@media(max-width:900px){.grid{grid-template-columns:1fr}} @media(max-width:640px){.stats{grid-template-columns:1fr}.head,.row{grid-template-columns:1fr}.state{text-align:left}}
</style></head><body><div class="wrap">
<section class="hero"><h1 style="margin:0 0 8px;font-size:40px;line-height:1">Upload com progresso</h1><p style="margin:0;max-width:650px">Envie arquivos para a sua nuvem com progresso por arquivo e progresso geral. Arquivos grandes sao enviados em partes menores para evitar travamentos na URL publica.</p></section>
<section class="grid">
<aside class="card">
<h2 style="margin-top:0">Acesso</h2><div id="status" class="pill">Verificando sessao...</div>
<label>Usuario</label><input id="user" type="text" value="cloud" autocomplete="username">
<label>Senha</label><input id="pass" type="password" autocomplete="current-password">
<div class="actions"><button id="login">Entrar</button><button id="logout" class="alt hidden" type="button">Sair</button></div>
<label>Pasta de destino</label><input id="dest" type="text" value="/Uploads">
<div class="muted">Exemplos: /Uploads ou /Fotos/Viagem</div>
<label><input id="overwrite" type="checkbox"> Sobrescrever se ja existir</label>
<div class="actions"><button id="pickFiles" class="alt" type="button">Selecionar arquivos</button><button id="pickFolder" class="alt" type="button">Selecionar pasta</button><a class="btn alt" href="/" target="_blank" rel="noreferrer">Abrir arquivos</a></div>
<input id="files" class="hidden" type="file" multiple><input id="folders" class="hidden" type="file" webkitdirectory directory multiple>
<div class="actions"><button id="send">Enviar tudo</button><button id="clear" class="alt" type="button">Limpar fila</button></div>
</aside>
<main class="card">
<h2 style="margin-top:0">Fila de envio</h2><p class="muted">Arraste arquivos ou pastas para a area abaixo. O envio acontece um por vez, em partes de 1 MB, para o progresso ficar legivel e confiavel mesmo na URL publica.</p>
<div id="drop" class="drop"><div><strong>Arraste os arquivos aqui</strong><div class="muted">Ou use os botoes ao lado.</div></div></div>
<div class="stats"><div class="stat">Arquivos<strong id="count">0</strong></div><div class="stat">Tamanho total<strong id="total">0 B</strong></div><div class="stat">Enviado<strong id="sent">0 B</strong></div></div>
<div class="bar"><div id="overall" class="fill"></div></div><p id="overallText" class="muted">Nenhum upload em andamento.</p>
<div class="queue"><div class="head"><div>Arquivo</div><div>Progresso</div><div>Status</div></div><div id="rows"></div></div>
</main></section></div>
<script>
const CHUNK_BYTES=1*1024*1024;
const s={auth:false,uploading:false,queue:[],done:0,total:0};
const r={status:status,user:user,pass:pass,login:login,logout:logout,dest:dest,overwrite:overwrite,pickFiles:pickFiles,pickFolder:pickFolder,files:files,folders:folders,send:send,clear:clear,drop:drop,count:count,total:total,sent:sent,overall:overall,overallText:overallText,rows:rows};
function fmt(n){if(!n)return"0 B";const u=["B","KB","MB","GB","TB"];let i=0,v=n;while(v>=1024&&i<u.length-1){v/=1024;i++}return `${v.toFixed(v>=10||i===0?0:1)} ${u[i]}`}
function slash(v){return (v||"").split("\\\\").join("/")}
function norm(v){v=slash(v).trim();if(!v)return"/Uploads";v="/"+v.replace(/^\/+/, "").replace(/\/+/g,"/");return v.endsWith("/")&&v.length>1?v.slice(0,-1):v}
function join(base,rel){return `${norm(base).replace(/^\/+/, "")}/${slash(rel).replace(/^\/+/, "")}`.replace(/\/+/g,"/")}
function makeUploadId(){return `${Date.now().toString(36)}-${Math.random().toString(36).slice(2,12)}`}
function setStatus(text,kind=""){r.status.textContent=text;r.status.className=`pill${kind?` ${kind}`:""}`}
function current(){return s.queue.filter(x=>x.state==="uploading").reduce((a,x)=>a+x.current,0)}
function refresh(){const sent=s.done+current();const pct=s.total?Math.min(100,Math.round(sent/s.total*100)):0;r.count.textContent=String(s.queue.length);r.total.textContent=fmt(s.total);r.sent.textContent=fmt(sent);r.overall.style.width=`${pct}%`;r.overallText.textContent=s.uploading?`Enviando ${fmt(sent)} de ${fmt(s.total)} (${pct}%).`:(s.queue.length?"Fila pronta para envio.":"Nenhum upload em andamento.");r.send.disabled=s.uploading||!s.queue.length}
function draw(){r.rows.innerHTML="";for(const item of s.queue){const row=document.createElement("div");row.className="row";row.innerHTML=`<div><div class="name">${item.path}</div><div class="sub">${fmt(item.file.size)} -> ${norm(r.dest.value)}</div></div><div><div class="bar"><div class="fill" style="width:${item.pct}%"></div></div><div class="sub">${item.pct}%</div></div><div class="state ${item.state==="done"?"ok":item.state==="error"?"err":""}">${item.msg}</div>`;r.rows.appendChild(row)}refresh()}
function waitPaint(){return new Promise(resolve=>requestAnimationFrame(()=>resolve()))}
function add(list){for(const file of list){s.queue.push({file,path:file.webkitRelativePath||file.name,pct:0,current:0,state:"pending",msg:"Na fila",parts:Math.max(1,Math.ceil(file.size/CHUNK_BYTES))})}s.total=s.queue.reduce((a,x)=>a+x.file.size,0);draw()}
async function session(){const res=await fetch("/__session__", {credentials:"same-origin"});const data=await res.json();s.auth=data.authenticated;r.logout.classList.toggle("hidden",!s.auth);setStatus(s.auth?"Sessao pronta para upload":"Entre para liberar o upload",s.auth?"ok":"")}
async function doLogin(){r.login.disabled=true;try{const res=await fetch("/__login__", {method:"POST",headers:{"Content-Type":"application/json"},credentials:"same-origin",body:JSON.stringify({username:r.user.value.trim(),password:r.pass.value})});const data=await res.json();if(!res.ok)throw new Error(data.error||"Falha no login");r.pass.value="";await session()}catch(err){setStatus(err.message,"err")}finally{r.login.disabled=false}}
async function doLogout(){await fetch("/__logout__", {method:"POST",credentials:"same-origin"});s.auth=false;r.logout.classList.add("hidden");setStatus("Sessao encerrada")}
function setUploading(v){s.uploading=v;r.clear.disabled=v;r.pickFiles.disabled=v;r.pickFolder.disabled=v;r.dest.disabled=v;r.overwrite.disabled=v;refresh()}
function uploadWhole(item,base,overwrite){return new Promise((resolve,reject)=>{const xhr=new XMLHttpRequest();xhr.open("POST", `/__upload__?path=${encodeURIComponent(join(base,item.path))}&overwrite=${overwrite?"1":"0"}`);xhr.withCredentials=true;xhr.onloadstart=()=>{item.state="uploading";item.msg="Iniciando";draw()};xhr.upload.onprogress=e=>{const total=e.lengthComputable&&e.total?e.total:item.file.size;if(!total)return;item.current=e.loaded;item.pct=Math.min(100,Math.round(e.loaded/total*100));item.state="uploading";item.msg="Enviando";draw()};xhr.onload=()=>{if(xhr.status>=200&&xhr.status<300){item.current=item.file.size;item.pct=100;item.state="uploading";item.msg="Finalizando";draw();resolve();return}let msg="Falha no upload";try{msg=(JSON.parse(xhr.responseText).error)||msg}catch(_){}reject(new Error(msg))};xhr.onerror=()=>reject(new Error("Conexao interrompida"));xhr.send(item.file)})}
function uploadChunk(item,base,overwrite,uploadId,offset,blob,part){return new Promise((resolve,reject)=>{const end=offset+blob.size;const xhr=new XMLHttpRequest();xhr.open("POST", `/__upload_chunk__?path=${encodeURIComponent(join(base,item.path))}&overwrite=${overwrite?"1":"0"}&upload_id=${encodeURIComponent(uploadId)}&offset=${offset}&total_size=${item.file.size}&complete=${end>=item.file.size?"1":"0"}`);xhr.withCredentials=true;xhr.onloadstart=()=>{item.current=offset;item.pct=Math.min(100,Math.round(item.current/item.file.size*100));item.state="uploading";item.msg=item.parts>1?`Parte ${part}/${item.parts}`:"Enviando";draw()};xhr.upload.onprogress=e=>{const loaded=offset+e.loaded;item.current=Math.min(item.file.size,loaded);item.pct=Math.min(100,Math.round(item.current/item.file.size*100));item.state="uploading";item.msg=item.parts>1?`Parte ${part}/${item.parts}`:"Enviando";draw()};xhr.onload=()=>{if(xhr.status===201||xhr.status===202){try{const data=JSON.parse(xhr.responseText||"{}");if(typeof data.received==="number"){item.current=data.received;item.pct=Math.min(100,Math.round(item.current/item.file.size*100));item.state="uploading";item.msg=data.complete?"Finalizando":(item.parts>1?`Parte ${part}/${item.parts}`:"Enviando");draw()}}catch(_){}resolve();return}let msg="Falha no upload";try{msg=(JSON.parse(xhr.responseText).error)||msg}catch(_){}reject(new Error(msg))};xhr.onerror=()=>reject(new Error("Conexao interrompida"));xhr.send(blob)})}
async function uploadChunkWithRetry(item,base,overwrite,uploadId,offset,blob,part){let lastError;for(let attempt=1;attempt<=3;attempt++){try{return await uploadChunk(item,base,overwrite,uploadId,offset,blob,part)}catch(err){lastError=err;if(attempt===3)break;item.state="uploading";item.current=offset;item.pct=Math.min(100,Math.round(item.current/item.file.size*100));item.msg=`Reconectando ${attempt}/3`;draw();await waitPaint();await new Promise(resolve=>setTimeout(resolve,attempt*1500))}}throw lastError}
async function uploadOne(item,base,overwrite){if(item.file.size===0){await uploadWhole(item,base,overwrite);item.current=0;item.pct=100;item.state="done";item.msg="Concluido";s.done+=item.file.size;draw();return}const uploadId=makeUploadId();let offset=0;let part=0;while(offset<item.file.size){part+=1;const blob=item.file.slice(offset, Math.min(offset+CHUNK_BYTES,item.file.size));item.state="uploading";item.current=offset;item.pct=Math.min(100,Math.round(item.current/item.file.size*100));item.msg=item.parts>1?`Parte ${part}/${item.parts}`:"Enviando";draw();await waitPaint();await uploadChunkWithRetry(item,base,overwrite,uploadId,offset,blob,part);offset+=blob.size;item.current=offset;item.pct=Math.min(100,Math.round(item.current/item.file.size*100));item.state="uploading";item.msg=offset<item.file.size?`Parte ${part}/${item.parts}`:"Finalizando";draw();await waitPaint()}item.current=item.file.size;item.pct=100;item.state="done";item.msg="Concluido";s.done+=item.file.size;draw()}
async function sendAll(){if(!s.auth){setStatus("Entre antes de enviar arquivos.","err");return}if(!s.queue.length){setStatus("Adicione arquivos na fila primeiro.","err");return}setUploading(true);setStatus("Upload em andamento...","ok");s.done=s.queue.filter(x=>x.state==="done").reduce((a,x)=>a+x.file.size,0);const base=norm(r.dest.value);const overwrite=r.overwrite.checked;try{for(const item of s.queue){if(item.state==="done")continue;item.pct=0;item.current=0;item.state="pending";item.msg="Na fila"}draw();for(const item of s.queue){if(item.state==="done")continue;await uploadOne(item,base,overwrite)}setStatus("Todos os arquivos foram enviados.","ok")}catch(err){setStatus(err.message,"err")}finally{setUploading(false)}}
function clearQueue(){s.queue=[];s.done=0;s.total=0;r.files.value="";r.folders.value="";draw()}
r.pickFiles.onclick=()=>r.files.click();r.pickFolder.onclick=()=>r.folders.click();r.files.onchange=e=>add(e.target.files);r.folders.onchange=e=>add(e.target.files);r.login.onclick=doLogin;r.logout.onclick=doLogout;r.send.onclick=sendAll;r.clear.onclick=clearQueue;
["dragenter","dragover"].forEach(t=>r.drop.addEventListener(t,e=>{e.preventDefault();r.drop.classList.add("drag")}));
["dragleave","drop"].forEach(t=>r.drop.addEventListener(t,e=>{e.preventDefault();r.drop.classList.remove("drag")}));
r.drop.addEventListener("drop", e=>add(e.dataTransfer.files));draw();session().catch(()=>setStatus("Nao foi possivel validar a sessao.","err"));
</script></body></html>"""


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def do_GET(self): self.dispatch()
    def do_POST(self): self.dispatch()
    def do_PUT(self): self.dispatch()
    def do_DELETE(self): self.dispatch()
    def do_PATCH(self): self.dispatch()
    def do_HEAD(self): self.dispatch()
    def do_OPTIONS(self): self.dispatch()

    def log_message(self, fmt, *args):
        print(f"{time.strftime('%Y-%m-%d %H:%M:%S')} - {self.address_string()} - {fmt % args}")

    def dispatch(self):
        parsed = urllib.parse.urlparse(self.path)
        path = parsed.path
        if path == "/upload-progress" and self.command == "GET":
            return self.html(PAGE)
        if path == "/__session__" and self.command == "GET":
            return self.handle_session()
        if path == "/__login__" and self.command == "POST":
            return self.handle_login()
        if path == "/__logout__" and self.command == "POST":
            return self.handle_logout()
        if path == "/__upload__" and self.command == "POST":
            return self.handle_upload(parsed)
        if path == "/__upload_chunk__" and self.command == "POST":
            return self.handle_upload_chunk(parsed)
        return self.proxy()

    def html(self, html):
        body = html.encode("utf-8")
        self.send_response(HTTPStatus.OK)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(body)

    def reply_json(self, status, payload, headers=None):
        body = json.dumps(payload).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        if headers:
            for key, value in headers.items():
                self.send_header(key, value)
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(body)

    def read_json(self):
        size = int(self.headers.get("Content-Length", "0") or "0")
        return json.loads(self.rfile.read(size).decode("utf-8")) if size else {}

    def session_token(self):
        raw = self.headers.get("Cookie", "")
        if not raw:
            return None
        cookie = SimpleCookie()
        cookie.load(raw)
        morsel = cookie.get(SESSION_COOKIE)
        return morsel.value if morsel else None

    def require_session(self):
        token = self.session_token()
        if not token or not valid_session(token):
            self.reply_json(HTTPStatus.UNAUTHORIZED, {"error": "Sessao expirada. Entre novamente."})
            return None
        return token

    def handle_session(self):
        token = self.session_token()
        self.reply_json(HTTPStatus.OK, {"authenticated": bool(token and valid_session(token))})

    def handle_login(self):
        try:
            payload = self.read_json()
        except json.JSONDecodeError:
            return self.reply_json(HTTPStatus.BAD_REQUEST, {"error": "JSON invalido."})
        if payload.get("username") != USERNAME or payload.get("password") != PASSWORD:
            return self.reply_json(HTTPStatus.UNAUTHORIZED, {"error": "Usuario ou senha invalidos."})
        token = create_session()
        self.reply_json(HTTPStatus.OK, {"ok": True}, headers={"Set-Cookie": f"{SESSION_COOKIE}={token}; Path=/; HttpOnly; SameSite=Lax; Max-Age={SESSION_TTL}"})

    def handle_logout(self):
        token = self.session_token()
        if token:
            drop_session(token)
        self.reply_json(HTTPStatus.OK, {"ok": True}, headers={"Set-Cookie": f"{SESSION_COOKIE}=; Path=/; HttpOnly; SameSite=Lax; Max-Age=0"})

    def handle_upload(self, parsed):
        if not self.require_session():
            return
        query = urllib.parse.parse_qs(parsed.query)
        overwrite = query.get("overwrite", ["0"])[0] == "1"
        size = int(self.headers.get("Content-Length", "0") or "0")
        if size < 0 or size > MAX_UPLOAD:
            return self.reply_json(HTTPStatus.REQUEST_ENTITY_TOO_LARGE, {"error": "Arquivo grande demais."})
        try:
            target = safe_target(query.get("path", [""])[0])
        except Exception as exc:
            return self.reply_json(HTTPStatus.BAD_REQUEST, {"error": str(exc)})
        if target.exists() and not overwrite:
            return self.reply_json(HTTPStatus.CONFLICT, {"error": "Arquivo ja existe. Ative sobrescrever."})
        target.parent.mkdir(parents=True, exist_ok=True)
        temp = target.with_name(target.name + ".part")
        remaining = size
        try:
            with open(temp, "wb") as fh:
                while remaining > 0:
                    chunk = self.rfile.read(min(1024 * 1024, remaining))
                    if not chunk:
                        break
                    fh.write(chunk)
                    remaining -= len(chunk)
            if remaining != 0:
                raise IOError("Upload interrompido")
            os.replace(temp, target)
        except Exception as exc:
            if temp.exists():
                temp.unlink(missing_ok=True)
            return self.reply_json(HTTPStatus.INTERNAL_SERVER_ERROR, {"error": f"Falha ao salvar arquivo: {exc}"})
        self.reply_json(HTTPStatus.CREATED, {"ok": True, "path": relative_target(target), "size": target.stat().st_size})

    def handle_upload_chunk(self, parsed):
        if not self.require_session():
            return
        query = urllib.parse.parse_qs(parsed.query)
        overwrite = query.get("overwrite", ["0"])[0] == "1"
        size = int(self.headers.get("Content-Length", "0") or "0")
        try:
            upload_id = safe_upload_id(query.get("upload_id", [""])[0])
            target = safe_target(query.get("path", [""])[0])
            offset = int(query.get("offset", ["0"])[0])
            total_size = int(query.get("total_size", ["0"])[0])
        except Exception as exc:
            return self.reply_json(HTTPStatus.BAD_REQUEST, {"error": str(exc)})
        complete = query.get("complete", ["0"])[0] == "1"
        if size < 0 or size > MAX_CHUNK_BYTES:
            return self.reply_json(HTTPStatus.REQUEST_ENTITY_TOO_LARGE, {"error": "Parte grande demais."})
        if total_size < 0 or total_size > MAX_UPLOAD:
            return self.reply_json(HTTPStatus.REQUEST_ENTITY_TOO_LARGE, {"error": "Arquivo grande demais."})
        if offset < 0 or offset > total_size or offset + size > total_size:
            return self.reply_json(HTTPStatus.BAD_REQUEST, {"error": "Parte fora do limite do arquivo."})

        UPLOAD_PARTS_DIR.mkdir(parents=True, exist_ok=True)
        temp, meta = partial_paths(upload_id)
        expected = {
            "path": relative_target(target),
            "total_size": total_size,
            "overwrite": overwrite,
        }

        try:
            if offset == 0:
                if target.exists() and not overwrite:
                    return self.reply_json(HTTPStatus.CONFLICT, {"error": "Arquivo ja existe. Ative sobrescrever."})
                temp.unlink(missing_ok=True)
                meta.unlink(missing_ok=True)
                meta.write_text(json.dumps(expected), encoding="utf-8")
                stream_to_file(self.rfile, temp, size, "wb")
            else:
                if not meta.exists() or not temp.exists():
                    return self.reply_json(HTTPStatus.CONFLICT, {"error": "Upload parcial nao encontrado. Recomece o envio."})
                stored = json.loads(meta.read_text(encoding="utf-8"))
                if stored != expected:
                    return self.reply_json(HTTPStatus.CONFLICT, {"error": "Upload parcial conflitou com outro envio. Recomece."})
                current_size = temp.stat().st_size
                if current_size != offset:
                    return self.reply_json(HTTPStatus.CONFLICT, {"error": "Upload fora de sequencia. Recomece o envio.", "received": current_size})
                stream_to_file(self.rfile, temp, size, "ab")

            received = temp.stat().st_size if temp.exists() else 0
            if complete or received >= total_size:
                if received != total_size:
                    raise IOError("Tamanho final inconsistente")
                target.parent.mkdir(parents=True, exist_ok=True)
                os.replace(temp, target)
                meta.unlink(missing_ok=True)
                return self.reply_json(HTTPStatus.CREATED, {"ok": True, "complete": True, "received": received, "path": relative_target(target), "size": target.stat().st_size})
        except Exception as exc:
            return self.reply_json(HTTPStatus.INTERNAL_SERVER_ERROR, {"error": f"Falha ao salvar parte: {exc}"})

        self.reply_json(HTTPStatus.ACCEPTED, {"ok": True, "complete": False, "received": received, "path": expected["path"]})

    def proxy(self):
        conn = http.client.HTTPConnection(BACKEND_HOST, BACKEND_PORT, timeout=120)
        headers = {}
        for key, value in self.headers.items():
            lower = key.lower()
            if lower in HOP_HEADERS or lower == "host":
                continue
            headers[key] = value
        headers["Host"] = f"{BACKEND_HOST}:{BACKEND_PORT}"
        body = None
        length = self.headers.get("Content-Length")
        if length:
            body = self.rfile.read(int(length))
        try:
            conn.request(self.command, self.path, body=body, headers=headers)
            res = conn.getresponse()
            payload = res.read()
        except Exception as exc:
            return self.reply_json(HTTPStatus.BAD_GATEWAY, {"error": f"Proxy falhou: {exc}"})
        finally:
            conn.close()
        self.send_response(res.status, res.reason)
        for key, value in res.getheaders():
            lower = key.lower()
            if lower in HOP_HEADERS or lower == "content-length":
                continue
            self.send_header(key, value)
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(payload)


if __name__ == "__main__":
    print(f"Gateway ready on http://{LISTEN_HOST}:{LISTEN_PORT}")
    print(f"Proxying File Browser from http://{BACKEND_HOST}:{BACKEND_PORT}")
    ThreadingHTTPServer((LISTEN_HOST, LISTEN_PORT), Handler).serve_forever()
