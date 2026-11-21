"use strict";
/* ---------- Utilidades ---------- */
const $ = s => document.querySelector(s);
const esc = s => String(s).replace(/[&<>"']/g, c => ({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"}[c]));
const cop = new Intl.NumberFormat("es-CO", {style:"currency", currency:"COP", maximumFractionDigits:0});
const num = new Intl.NumberFormat("es-CO", {maximumFractionDigits:1});
const CARGA = 125; // kg de café pergamino seco por carga
const store = {
  get(k, d){ try { const v = localStorage.getItem(k); return v ? JSON.parse(v) : d } catch(e){ return d } },
  set(k, v){ try { localStorage.setItem(k, JSON.stringify(v)) } catch(e){} }
};
async function sha(s){
  try { const b = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(s));
        return [...new Uint8Array(b)].map(x => x.toString(16).padStart(2,"0")).join("") }
  catch(e){ return btoa(unescape(encodeURIComponent(s))) }
}
let seq = Date.now();
const uid = () => ++seq;
function toast(m){ const t = $("#toast"); t.textContent = m; t.classList.add("on"); clearTimeout(toast.t); toast.t = setTimeout(() => t.classList.remove("on"), 2000) }

/* ---------- Estado ---------- */
let users = store.get("cos_users", []), me = store.get("cos_me", null);
let db = {lotes:[], recs:[], ventas:[]};
let ui = {auth:"login", tab:"lotes", armed:null};
const save = () => store.set("cos_db_" + me, db);
const loteName = id => (db.lotes.find(l => l.id === id) || {nombre:"(lote eliminado)"}).nombre;
const valor = v => v.kg / CARGA * v.precio; // valor de una venta

/* ---------- Configuración de cada tabla ---------- */
const VAR = ["Castillo","Caturra","Colombia","Típica","Geisha","Otra"];
const E = {
  lotes:{ t:"Lotes", one:"lote",
    f:[{k:"nombre",l:"Nombre del lote",t:"text"},
       {k:"variedad",l:"Variedad",t:"select",o:() => VAR},
       {k:"ha",l:"Hectáreas",t:"number",min:0.01,max:10000}],
    c:[["Lote", r => `<b>${esc(r.nombre)}</b><div class="m">${esc(r.variedad)}</div>`],
       ["Hectáreas", r => num.format(r.ha), 1]] },
  recs:{ t:"Recolecciones", one:"recolección",
    f:[{k:"fecha",l:"Fecha",t:"date"},
       {k:"lote",l:"Lote",t:"select",o:() => db.lotes.map(l => [l.id, l.nombre])},
       {k:"kg",l:"Kilos recolectados",t:"number",min:0.1,max:100000}],
    c:[["Fecha", r => r.fecha], ["Lote", r => esc(loteName(r.lote))], ["Kilos", r => num.format(r.kg), 1]] },
  ventas:{ t:"Ventas", one:"venta",
    f:[{k:"fecha",l:"Fecha",t:"date"},
       {k:"kg",l:"Kilos de pergamino seco",t:"number",min:0.1,max:1000000},
       {k:"precio",l:"Precio por carga (COP)",t:"number",min:1,max:100000000},
       {k:"comprador",l:"Comprador",t:"text"}],
    c:[["Fecha", r => r.fecha], ["Comprador", r => esc(r.comprador)],
       ["Kilos", r => num.format(r.kg), 1], ["Valor", r => cop.format(valor(r)), 1]] }
};

/* ---------- Autenticación ---------- */
function authView(){
  const reg = ui.auth === "register";
  return `<main class="auth"><h1>Cosecha</h1>
  <p class="sub">Registra tus lotes, recolecciones y ventas de café, y mira cuánto produce y deja cada lote.</p>
  <div class="card"><div class="tabs" role="tablist">
    <button role="tab" aria-selected="${!reg}" onclick="setAuth('login')">Ingresar</button>
    <button role="tab" aria-selected="${reg}" onclick="setAuth('register')">Crear cuenta</button></div>
  <form onsubmit="doAuth(event)" novalidate>
    ${reg ? `<label>Nombre<input name="name" maxlength="40" autocomplete="name"></label>` : ""}
    <label>Correo<input name="email" type="email" maxlength="80" autocomplete="email"></label>
    <label>Contraseña<input name="password" type="password" maxlength="64" autocomplete="${reg ? "new-password" : "current-password"}"></label>
    <div class="err" id="autherr" role="alert"></div>
    <button class="btn pri" style="width:100%;margin-top:8px">${reg ? "Crear cuenta" : "Ingresar"}</button>
  </form></div>
  <p class="m">Tus datos se guardan solo en este navegador.</p></main>`;
}
function setAuth(t){ ui.auth = t; render() }
async function doAuth(ev){
  ev.preventDefault();
  const f = ev.target, e = m => $("#autherr").textContent = m;
  const email = f.email.value.trim().toLowerCase(), pw = f.password.value, reg = ui.auth === "register";
  if(!/^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/.test(email)) return e("Escribe un correo válido, por ejemplo nombre@correo.com.");
  if(pw.length < 8) return e("La contraseña debe tener al menos 8 caracteres.");
  const h = await sha(email + ":" + pw);
  if(reg){
    const name = f.name.value.trim();
    if(name.length < 2) return e("Escribe tu nombre (mínimo 2 letras).");
    if(users.some(u => u.email === email)) return e("Ese correo ya tiene cuenta. Usa la pestaña Ingresar.");
    users.push({name, email, h}); store.set("cos_users", users);
  } else if(!users.some(u => u.email === email && u.h === h)){
    return e("Correo o contraseña incorrectos.");
  }
  me = email; store.set("cos_me", me);
  db = store.get("cos_db_" + me, {lotes:[], recs:[], ventas:[]});
  render();
}
function logout(){ me = null; store.set("cos_me", null); ui.auth = "login"; render() }

/* ---------- Vistas ---------- */
function appView(){
  const u = users.find(x => x.email === me);
  const tabs = [["lotes","Lotes"],["recs","Recolecciones"],["ventas","Ventas"],["reporte","Reporte"]];
  return `<header><div class="in"><span class="brand">Cosecha</span><span class="who">${esc(u ? u.name : me)}</span>
    <button class="btn sm" onclick="logout()">Cerrar sesión</button></div></header>
    <div class="wrap"><nav aria-label="Secciones">${tabs.map(t =>
      `<button ${ui.tab === t[0] ? 'aria-current="page"' : ""} onclick="go('${t[0]}')">${t[1]}</button>`).join("")}</nav>
    <main id="main"></main></div>`;
}
function go(t){ ui.tab = t; ui.armed = null; render() }
function body(){ ui.tab === "reporte" ? reporte() : list(ui.tab) }

function list(k){
  const e = E[k], rows = [...db[k]];
  if(k !== "lotes") rows.sort((a, b) => b.fecha.localeCompare(a.fecha));
  const needLote = k === "recs" && !db.lotes.length;
  let h = `<div class="bar"><h2>${e.t}</h2>${needLote ? "" : `<button class="btn pri" onclick="openForm('${k}')">Agregar ${e.one}</button>`}</div>`;
  if(needLote){
    h += `<div class="card empty"><p>Primero crea al menos un lote para registrar recolecciones.</p><button class="btn pri" onclick="go('lotes')">Ir a Lotes</button></div>`;
  } else if(!rows.length){
    h += `<div class="card empty"><p>Aún no hay registros. Agrega el primero${k === "lotes" ? " o carga datos de ejemplo" : ""}.</p>${k === "lotes" ? `<button class="btn" onclick="demo()">Cargar datos de ejemplo</button>` : ""}</div>`;
  } else {
    h += `<div class="card scroll"><table><thead><tr>${e.c.map(c => `<th class="${c[2] ? "n" : ""}">${c[0]}</th>`).join("")}<th></th></tr></thead><tbody>` +
      rows.map(r => `<tr>${e.c.map(c => `<td class="${c[2] ? "n" : ""}">${c[1](r)}</td>`).join("")}
      <td class="acts"><button class="btn sm" onclick="openForm('${k}',${r.id})">Editar</button>
      <button class="btn sm ${ui.armed === k + r.id ? "arm" : ""}" onclick="del('${k}',${r.id})">${ui.armed === k + r.id ? "Confirmar" : "Eliminar"}</button></td></tr>`).join("") +
      `</tbody></table></div>`;
  }
  $("#main").innerHTML = h;
}

function reporte(){
  const sum = (a, f) => a.reduce((s, x) => s + f(x), 0);
  const kg = sum(db.recs, r => r.kg), sold = sum(db.ventas, v => v.kg), inc = sum(db.ventas, valor), ha = sum(db.lotes, l => l.ha);
  const byLote = db.lotes.map(l => { const k = sum(db.recs.filter(r => r.lote === l.id), r => r.kg); return {n:l.nombre, k, ph:k / l.ha} })
    .sort((a, b) => b.k - a.k);
  const mx = Math.max(1, ...byLote.map(x => x.k));
  const months = {};
  db.ventas.forEach(v => { const m = v.fecha.slice(0, 7); months[m] = (months[m] || 0) + valor(v) });
  const me2 = Object.entries(months).sort((a, b) => a[0].localeCompare(b[0]));
  const mm = Math.max(1, ...me2.map(x => x[1]));
  const mes = m => new Date(m + "-01T12:00:00").toLocaleDateString("es-CO", {month:"long", year:"numeric"});
  $("#main").innerHTML = `<div class="bar"><h2>Reporte de la temporada</h2></div>
  <div class="kpis">
    <div class="kpi"><b>${num.format(kg)} kg</b><span>Recolectados</span></div>
    <div class="kpi"><b>${num.format(sold)} kg</b><span>Vendidos (pergamino seco)</span></div>
    <div class="kpi"><b>${cop.format(inc)}</b><span>Ingresos por ventas</span></div>
    <div class="kpi"><b>${num.format(ha)} ha</b><span>Área en producción</span></div></div>
  <div class="card"><h2 style="font-size:18px">Producción por lote</h2>${byLote.length ? byLote.map(x =>
    `<div class="row"><div class="l"><span>${esc(x.n)}</span><span><b>${num.format(x.k)} kg</b> · ${num.format(x.ph)} kg/ha</span></div><div class="t"><i style="width:${Math.round(x.k / mx * 100)}%"></i></div></div>`).join("")
    : `<p class="m">Crea lotes y registra recolecciones para ver este reporte.</p>`}</div>
  <div class="card"><h2 style="font-size:18px">Ingresos por mes</h2>${me2.length ? me2.map(([m, v]) =>
    `<div class="row"><div class="l"><span>${mes(m)}</span><b>${cop.format(v)}</b></div><div class="t"><i style="width:${Math.round(v / mm * 100)}%"></i></div></div>`).join("")
    : `<p class="m">Registra ventas para ver los ingresos por mes.</p>`}
    <p class="m">Valor de cada venta = kilos ÷ ${CARGA} × precio por carga. Los kilos recolectados y los vendidos pueden estar en estados distintos (cereza o pergamino).</p></div>`;
}

/* ---------- Formulario genérico ---------- */
function openForm(k, id){
  const e = E[k], r = db[k].find(x => x.id === id) || {};
  const today = new Date().toISOString().slice(0, 10);
  $("#modal").innerHTML = `<div class="dlg" role="dialog" aria-modal="true"><h2>${id ? "Editar" : "Agregar"} ${e.one}</h2>
  <form onsubmit="saveForm(event,'${k}',${id || 0})" novalidate>` +
  e.f.map(f => {
    const v = r[f.k] ?? (f.t === "date" ? today : "");
    const inp = f.t === "select"
      ? `<select name="${f.k}">${f.o().map(o => { const [val, lab] = Array.isArray(o) ? o : [o, o];
          return `<option value="${esc(val)}" ${String(val) === String(v) ? "selected" : ""}>${esc(lab)}</option>` }).join("")}</select>`
      : `<input name="${f.k}" type="${f.t}" value="${esc(v)}" ${f.t === "number" ? 'step="any" inputmode="decimal"' : 'maxlength="50"'}>`;
    return `<label>${f.l}${inp}</label>`;
  }).join("") +
  `<div class="err" id="ferr" role="alert"></div>
  <div class="foot"><button type="button" class="btn" onclick="closeForm()">Cancelar</button><button class="btn pri">Guardar</button></div></form></div>`;
  $("#modal").hidden = false;
  const first = $("#modal input,#modal select"); if(first) first.focus();
}
function closeForm(){ $("#modal").hidden = true; $("#modal").innerHTML = "" }
function saveForm(ev, k, id){
  ev.preventDefault();
  const e = E[k], f = ev.target, rec = {}, err = m => $("#ferr").textContent = m;
  for(const fl of e.f){
    let v = f.elements[fl.k].value.trim();
    if(!v) return err(`Completa el campo «${fl.l}».`);
    if(fl.t === "number"){
      v = Number(v);
      if(!isFinite(v) || v < fl.min || v > fl.max) return err(`«${fl.l}» debe estar entre ${fl.min} y ${fl.max}.`);
    } else if(fl.t === "text" && v.length < 2){
      return err(`«${fl.l}» necesita al menos 2 caracteres.`);
    } else if(fl.t === "date" && !/^\d{4}-\d{2}-\d{2}$/.test(v)){
      return err("Elige una fecha válida.");
    }
    if(fl.k === "lote") v = Number(v);
    rec[fl.k] = v;
  }
  if(id) Object.assign(db[k].find(x => x.id === id), rec); else db[k].push({id:uid(), ...rec});
  save(); closeForm(); body(); toast("Guardado");
}
function del(k, id){
  const key = k + id;
  if(ui.armed !== key){ ui.armed = key; body(); clearTimeout(del.t); del.t = setTimeout(() => { ui.armed = null; body() }, 3000); return }
  db[k] = db[k].filter(x => x.id !== id);
  if(k === "lotes") db.recs = db.recs.filter(r => r.lote !== id); // al borrar un lote se borran sus recolecciones
  ui.armed = null; save(); body(); toast("Eliminado");
}

/* ---------- Datos de ejemplo ---------- */
function demo(){
  const a = uid(), b = uid(), c = uid();
  db.lotes = [{id:a,nombre:"La Esperanza",variedad:"Castillo",ha:2.5},{id:b,nombre:"El Mirador",variedad:"Caturra",ha:1.2},{id:c,nombre:"Buenavista",variedad:"Colombia",ha:3}];
  db.recs = [[a,"2026-10-05",320],[a,"2026-10-19",410],[b,"2026-10-12",150],[b,"2026-11-02",180],[c,"2026-10-26",520],[c,"2026-11-09",460]]
    .map(x => ({id:uid(), lote:x[0], fecha:x[1], kg:x[2]}));
  db.ventas = [["2026-10-20",500,2100000,"Cooperativa de caficultores"],["2026-11-10",625,2150000,"Comprador local"]]
    .map(x => ({id:uid(), fecha:x[0], kg:x[1], precio:x[2], comprador:x[3]}));
  save(); body(); toast("Datos de ejemplo cargados");
}

/* ---------- Arranque ---------- */
function render(){
  if(me && !users.some(u => u.email === me)) me = null;
  $("#app").innerHTML = me ? appView() : authView();
  if(me) body();
}
$("#modal").addEventListener("click", e => { if(e.target.id === "modal") closeForm() });
document.addEventListener("keydown", e => { if(e.key === "Escape" && !$("#modal").hidden) closeForm() });
if(me) db = store.get("cos_db_" + me, {lotes:[], recs:[], ventas:[]});
render();
