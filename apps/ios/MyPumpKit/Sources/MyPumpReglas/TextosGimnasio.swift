import Foundation

/// Todo lo que lee el alumno en «Gimnasio por fotos», en un solo lugar: para cambiar un texto se cambia acá y en el gemelo
/// `TextosGimnasio.kt`, sin tocar lógica (`apps/shared/vectores/gimnasio.json` hace fallar las pruebas si difieren).
/// Lista para el OK de Mati en `privado/TEXTOS_PARA_OK.md`. Crédito: «Adaptado por Mati», nunca IA; la única excepción es
/// el aviso de terceros que exige Apple.
public enum TextosGimnasio {
    // Entrada
    public static let tarjetaTitulo = "Tu gimnasio"
    public static let entradaMisDatos = "Mi gimnasio"
    public static let confirmarTarjeta = "Confirmanos qué de esto hay en tu gimnasio"
    // Inicio
    public static let inicioTitulo = "Mostranos tu gimnasio"
    public static let inicioBajada = "Sacale fotos a lo que hay y adaptamos tu plan a tus máquinas"
    public static let avisoTerceros = "Para reconocer los equipos, tus fotos las procesan servicios externos de inteligencia artificial, sin tu nombre. Mati y tu entrenador deciden los cambios"
    public static let botonEmpezar = "Entendido, empezar"
    public static let consejoPermiso = "Si tu gimnasio no deja, pedí permiso o sacalas en un horario tranquilo"
    // Zonas
    public static let noHay = "No hay en mi gimnasio"
    public static let noHayCorto = "No hay"
    public static let sinFotos = "Sin fotos"
    public static let opcional = "Opcional"
    public static let consejoCamara = "La máquina entera, de costado. Si hay alguien, esperá a que se vaya: no sacamos fotos con gente"
    public static let agregarFoto = "Sacar o elegir foto"
    public static let borrarFoto = "Borrar foto"
    public static let subiendo = "Subiendo…"
    public static let esperandoSenal = "Esperando señal"
    public static let revisarYEnviar = "Revisar y enviar"
    public static let tope = "Llegaste al máximo de 80 fotos"
    public static let fotoRechazada = "Una foto no se pudo usar. Sacala de nuevo"
    public static let noSeGuardo = "No se pudo guardar la foto en el teléfono. Probá de nuevo"
    public static let sinSenal = "Se cortó la conexión. Probá de nuevo cuando tengas señal."
    public static let cuentaFotos1 = "1 foto"
    public static func cuentaFotos(_ n: Int) -> String { n == 1 ? cuentaFotos1 : "\(n) fotos" }
    // Enviar
    public static let revisarTitulo = "Revisar y enviar"
    public static let notaPlaceholder = "Algo que no se vea en las fotos"
    public static let botonEnviar = "Enviar a Mati"
    public static func faltanZonas(_ n: Int) -> String { n == 1 ? "Te falta 1 zona" : "Te faltan \(n) zonas" }
    public static func subiendoFotos(_ hechas: Int, de total: Int) -> String { "Subiendo tus fotos: \(hechas) de \(total)" }
    public static let enviandoSeguir = "Queda guardado y se envía solo cuando vuelva la señal"
    public static let sinNovedad = "Sumá una foto o marcá algo que ya no esté"
    public static let errorGenerico = "No se pudo enviar. Probá de nuevo"
    // Estados
    public static let recibido = "Recibido. Mati y tu entrenador lo están viendo. Te avisamos por WhatsApp"
    public static func adaptadoPorMati(_ fecha: String) -> String { "Adaptado por Mati el \(fecha)" }
    public static let sinCambios = "Mati revisó tu gimnasio y tu rutina encaja tal cual"
    // Preguntas
    public static func necesitamosFotos(_ n: Int) -> String { n == 1 ? "Necesitamos 1 foto más" : "Necesitamos \(n) fotos más" }
    public static func preguntaDe(_ i: Int, _ n: Int) -> String { "Pregunta \(i) de \(n)" }
    public static let anterior = "Anterior"
    public static let siguiente = "Siguiente"
    public static let noSe = "No sé"
    public static let si = "Sí"
    public static let no = "No"
    public static let noPuedoFoto = "No puedo sacarla"
    public static let marcarTodas = "Marcá todas las que haya: lo que no marques cuenta como que no está"
    public static let elegirKilos = "Kilos"
    public static let kilosInvalidos = "Poné un número entre 1 y 400"
    // Mi gimnasio
    public static let faltaAlgo = "Falta algo"
    public static let yaNoEsta = "Esto ya no está"
    public static let cambieDeGimnasio = "Cambié de gimnasio"
    public static let marcarLoQueNoEsta = "Marcá lo que ya no está"
}
