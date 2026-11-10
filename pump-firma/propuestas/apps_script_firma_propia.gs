// PROPUESTA, SIN APLICAR — cambio del Apps Script «Onboarding y contratos» para usar la firma propia (pump-firma).
// Lo aplica Mati (o la sesión de operaciones con su OK) desde el editor de Apps Script. Nada de esto está en vivo.
//
// Qué cambia: UNA función nueva y TRES líneas al principio de enviarContratoBoldSign. Nada más:
//   · los mensajes de WhatsApp al alumno NO cambian («te va a llegar por correo electrónico» sigue siendo cierto:
//     pump-firma manda un correo por documento con el enlace para firmar, como hacía BoldSign);
//   · `boldSignEnviado`, las columnas de la planilla y lo que viaja al bot quedan igual (true = los documentos se crearon);
//   · la decisión de quién lleva contrato (necesitaContrato) y de quién es residente argentino sigue siendo la de hoy.
//
// Propiedades del script (Configuración del proyecto → Propiedades del script):
//   FIRMA_PROPIA          "1" para usar pump-firma. Sin la propiedad (o con otro valor) sigue BoldSign, tal cual hoy.
//   FIRMA_PROPIA_URL      https://firma.mypumpteam.com
//   FIRMA_PROPIA_SECRETO  el mismo valor que FIRMA_SECRETO_INTERNO del servicio
// Volver atrás: borrar la propiedad FIRMA_PROPIA. No hace falta tocar el código.

// ── 1) Al principio de enviarContratoBoldSign(nombre, apellido, email, plan, datos), antes del `try {` ──
//
//   if (PropertiesService.getScriptProperties().getProperty("FIRMA_PROPIA") === "1") {
//     return enviarContratoFirmaPropia_(nombre, apellido, email, plan, datos || {});
//   }

// ── 2) Función nueva (pegar al lado de enviarContratoBoldSign) ──
function enviarContratoFirmaPropia_(nombre, apellido, email, plan, datos) {
  var props = PropertiesService.getScriptProperties();
  var base = props.getProperty("FIRMA_PROPIA_URL");
  var secreto = props.getProperty("FIRMA_PROPIA_SECRETO");
  if (!base || !secreto) return { ok: false, error: "faltan FIRMA_PROPIA_URL o FIRMA_PROPIA_SECRETO" };
  var residente = esResidenteArgentino(datos);
  var hoy = Utilities.formatDate(new Date(), "UTC", "yyyy-MM-dd");
  var cuerpo = {
    // el mismo formulario enviado dos veces el mismo día no crea documentos nuevos
    alta_ref: "form-" + String(email).toLowerCase().trim() + "-" + String(datos.numeroWA || "").replace(/\D/g, "") + "-" + hoy,
    origen: "apps_script",
    nombre: nombre, apellido: apellido, email: email, whatsapp: datos.numeroWA || "",
    dni: dniPlausible(datos.dni), domicilio: datos.domicilio || "", pais: datos.pais || "",
    residente_argentina: residente,           // la decisión la toma este script, como hoy; el servicio no la recalcula
    plan: plan || "", objetivo: datos.objetivo || "", precio: datos.precio || ""
  };
  var ultimo = "";
  for (var intento = 1; intento <= 3; intento++) {
    try {
      var resp = UrlFetchApp.fetch(base.replace(/\/+$/, "") + "/api/interno/crear", {
        method: "post", contentType: "application/json", payload: JSON.stringify(cuerpo),
        headers: { "X-Pump-Firma-Secreto": secreto }, muteHttpExceptions: true
      });
      var code = resp.getResponseCode();
      var r = {};
      try { r = JSON.parse(resp.getContentText()); } catch (e) {}
      if (code === 200 && r.ok) {
        Logger.log("Firma propia: " + r.documentos.length + " documento(s) para " + email);
        return { ok: true };
      }
      if (code === 200) {   // el servicio contestó que no puede: falta un dato del formulario. No sirve reintentar.
        var e0 = (r.errores && r.errores[0]) || { error: r.error || "sin detalle" };
        return { ok: false, error: "Firma propia: " + e0.error + (e0.campos ? " (" + e0.campos.join(", ") + ")" : "") };
      }
      ultimo = "HTTP " + code;
    } catch (err) {
      ultimo = err.message;
    }
    if (intento < 3) Utilities.sleep(2000 * intento);
  }
  return { ok: false, error: "Firma propia: " + ultimo };
}
// Nota: en Argentina, con plan, objetivo o precio vacíos el servicio NO crea el contrato (hoy BoldSign lo mandaba para
// que el alumno lo completara). El estado de la planilla lo va a mostrar como «⚠️ Completo — revisar»: se corrige el
// dato y se reenvía el formulario. Es a propósito: el alumno no escribe el precio de su propio contrato.
