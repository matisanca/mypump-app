'use strict';
(function () {
  var $ = function (id) { return document.getElementById(id); };
  var NOMBRES = { servicio_ar: 'Contrato de coaching', servicio_ext: 'Contrato de coaching', consentimiento_ar: 'Consentimiento de atención médica' };
  function fecha(iso) {
    try { return new Date(iso).toLocaleString('es-AR', { dateStyle: 'long', timeStyle: 'medium', timeZone: 'America/Argentina/Buenos_Aires' }) + ' (hora de Argentina)'; }
    catch (e) { return iso; }
  }
  function mostrar(r) {
    var caja = $('resultado');
    caja.textContent = '';
    function linea(t, clase) { var p = document.createElement('p'); p.textContent = t; if (clase) p.className = clase; caja.appendChild(p); }
    if (!r || !r.existe) { linea('No hay ningún documento registrado con esos datos.', 'mal'); return; }
    if (r.coincide === 'firmado') linea('Coincide: es el documento firmado que tenemos registrado, sin cambios.', 'bien');
    else if (r.coincide === 'revocacion') linea('Coincide: es la constancia de revocación registrada, sin cambios.', 'bien');
    else if (r.coincide === 'sin_firmar') linea('Es el documento sin firmar (el que se mostró antes de firmar).', 'aviso');
    else if (r.coincide === 'no') linea('La huella NO coincide con el documento registrado: ese PDF no es el original o fue modificado.', 'mal');
    linea((NOMBRES[r.tipo] || 'Documento') + ' · estado: ' + r.estado);
    if (r.firmado_en) linea('Firmado el ' + fecha(r.firmado_en));
    if (r.revocado_en) linea('Revocado el ' + fecha(r.revocado_en));
    (r.sellos || []).forEach(function (s) { linea('Sello de tiempo externo (' + s.tsa + '): ' + fecha(s.hora)); });
  }
  $('verificar').addEventListener('click', function () {
    var archivo = $('pdf').files[0];
    var pedido;
    if (archivo) {
      var f = new FormData(); f.append('archivo', archivo);
      pedido = fetch('/api/verificar/pdf', { method: 'POST', body: f });
    } else {
      pedido = fetch('/api/verificar', { method: 'POST', headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ id: $('id').value.trim(), sha256: $('sha').value.trim() }) });
    }
    $('resultado').textContent = 'Verificando…';
    pedido.then(function (r) { return r.json(); }).then(mostrar).catch(function () { $('resultado').textContent = 'No se pudo verificar. Probá de nuevo.'; });
  });
})();
