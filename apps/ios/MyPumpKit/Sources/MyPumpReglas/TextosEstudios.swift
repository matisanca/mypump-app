import Foundation

/// Todo lo que lee el alumno en «Estudios y órdenes», en un solo lugar: para cambiar un texto se cambia acá y en el gemelo de
/// Android, sin tocar lógica (`apps/shared/vectores/estudios.json` hace fallar las pruebas si difieren). Fuente:
/// `estudios/CONTRATO_APP.md`. Sin valores, sin interpretación y sin nombrar quién lee los archivos: lo que tarda es «de Mati».
public enum TextosEstudios {
    // Entrada en Mis datos
    public static let entradaMisDatos = "Estudios y órdenes"
    public static func subtituloEntrada(_ pendientes: Int) -> String {
        pendientes <= 0 ? "Todo al día" : pendientes == 1 ? "Te falta 1 estudio" : "Te faltan \(pendientes) estudios"
    }
    // Pantalla
    public static let titulo = "Estudios"
    public static let proximoControl = "Próximo control"
    public static let teFaltaHacer = "Te falta hacer"
    public static let subirResultado = "Subir resultado"
    public static let yaMeLoHice = "Ya me lo hice"
    public static let verOrden = "Ver orden"
    public static let deshacer = "Deshacer"
    public static let subirEstudio = "Subir un estudio"
    public static let tusOrdenes = "Tus órdenes"
    public static let tusEstudios = "Tus estudios"
    public static let ver = "Ver"
    public static let recibido = "Recibido"
    public static let matiLoVio = "Mati lo vio"
    public static let sinFecha = "Sin fecha"
    public static let ordenVencida = "Vencida. Si la necesitás, pedísela a Mati por el chat."
    public static let notaRecibido = "Recibido quiere decir que llegó. Mati lo revisa y te escribe. Si te sentís mal, no esperes: escribile o consultá a un médico."
    public static let vacio = "Acá vas a ver los estudios que te pida Mati, tus órdenes y lo que nos mandes."
    public static let errorDeCarga = "No se pudo cargar. Deslizá para reintentar."
    // Fecha de «Ya me lo hice»
    public static let cuandoTeLoHiciste = "¿Cuándo te lo hiciste?"
    public static let guardar = "Guardar"
    public static let revisaLaFecha = "Revisá la fecha."
    // Subida
    public static let guiaSubida = "Subí todas las hojas juntas, en PDF o en fotos donde se lea bien."
    public static let sacarFotos = "Sacar fotos"
    public static let elegirFotos = "Elegir fotos"
    public static let elegirPDF = "Elegir PDF"
    public static let quitar = "Quitar"
    public static func enviarArchivos(_ n: Int) -> String { n == 1 ? "Enviar 1 archivo" : "Enviar \(n) archivos" }
    public static func topeArchivos(_ n: Int) -> String { "Hasta \(n) archivos por envío." }
    public static func archivoMuyGrande(_ mb: Int) -> String { "Ese archivo pesa más de \(mb) MB." }
    public static func subiendo(_ i: Int, de n: Int) -> String { "Subiendo \(i) de \(n)" }
    public static let sinSenal = "Sin señal. Se envía solo cuando vuelva."
    public static let envioRecibido = "Recibido. Mati lo revisa y te escribe."
    public static let topeDia = "Ya mandaste varios envíos hoy. Probá mañana o escribile a Mati."
    public static let archivoRechazado = "No pudimos leer ese archivo. Probá con una foto o un PDF."
    // Órdenes
    public static let comoPrepararte = "Cómo prepararte"
    public static let dondeHacerlo = "Dónde hacerlo"
    public static let noSePudoAbrir = "No se pudo abrir. Probá de nuevo."
    // Novedades: la tarjeta de arriba, el aviso y la etiqueta. Ninguno dice qué estudio ni por qué.
    public static let estudioNuevo = "Tenés un estudio nuevo para hacer"
    public static let ordenNueva = "Tenés una orden nueva"
    public static let estudioParaHacer = "Tenés un estudio para hacer"
    public static let nuevo = "Nuevo"
    /// Solo para VoiceOver: lo que dice el punto de la pestaña y de la fila.
    public static let novedad = "Novedad"
    // Fuera del contrato: rótulos mínimos que la pantalla necesita (botones de cierre y nombre de cada archivo para VoiceOver).
    public static let cerrar = "Cerrar"
    public static let cancelar = "Cancelar"
    public static func foto(_ n: Int) -> String { "Foto \(n)" }
    public static func pdf(_ n: Int) -> String { "PDF \(n)" }
    public static let noSePudoGuardar = "No se pudo guardar. Probá de nuevo."
    public static let noSePudoEnviar = "No se pudo enviar. Probá de nuevo."
    public static let probarDeNuevo = "Probar de nuevo"
}
