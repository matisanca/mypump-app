import Foundation

/// Todo lo que lee el alumno en «Fotos de inicio», en un solo lugar: para cambiar un texto se cambia acá, en el gemelo
/// `TextosFotosInicio.kt` y en la web, sin tocar lógica (`apps/shared/vectores/fotos_inicio.json` hace fallar las pruebas si
/// difieren). Las fotos son privadas: ningún texto nombra a otra cosa que a Mati.
public enum TextosFotosInicio {
    // Entrada
    public static let tarjetaTitulo = "Tus fotos de inicio"
    public static let tarjetaBajada = "Tres fotos para que Mati vea de dónde arrancás"
    public static let tarjetaEmpezar = "Empezar"
    public static let tarjetaSeguir = "Seguir"
    public static let tarjetaLista = "Listas. Mati ya las tiene"
    public static let entradaMisDatos = "Mis fotos de inicio"
    public static let privacidad = "Las ve solo Mati. No se publican ni salen de la app"
    // Consejos
    public static let consejosTitulo = "Antes de sacarlas"
    public static let consejoLuz = "De frente a una ventana o con la luz prendida. Sin contraluz"
    public static let consejoDistancia = "El teléfono a unos 2 metros: tenés que entrar de la cabeza a los pies"
    public static let consejoAltura = "La cámara derecha, a la altura del pecho"
    public static let consejoRopa = "En short o ropa interior, y con top deportivo si usás"
    public static let consejoFondo = "Una pared lisa atrás, sin cosas en el medio"
    public static let consejoEspejo = "Mejor sin espejo: apoyá el teléfono o pedile a alguien que te la saque"
    public static let consejoTemporizador = "Si estás solo, usá el temporizador de la cámara y después elegí la foto de la galería"
    public static let consejoPostura = "Relajado, sin sacar músculo ni meter la panza"
    // Poses
    public static let poseFrente = "De frente"
    public static let posePerfil = "De perfil"
    public static let poseEspalda = "De espalda"
    public static let instruccionFrente = "Parate derecho mirando a la cámara, con los brazos un poco separados del cuerpo y los pies al ancho de la cadera"
    public static let instruccionPerfil = "De costado a la cámara, mirando al frente y con los brazos al costado del cuerpo"
    public static let instruccionEspalda = "De espaldas a la cámara, en la misma postura que de frente"
    public static let falta = "Falta"
    public static let lista = "Lista"
    public static let subiendo = "Subiendo…"
    public static let esperandoSenal = "Esperando señal"
    // Sacar y revisar
    public static let botonFoto = "Sacar o elegir foto"
    public static let botonUsar = "Usar esta foto"
    public static let botonUsarIgual = "Usar igual"
    public static let botonOtra = "Sacar otra"
    public static let seVeBien = "Se ve bien"
    public static let problemaChica = "Tiene poca resolución. Sacala de nuevo con la cámara del teléfono"
    public static let problemaApaisada = "Salió acostada. Sacala con el teléfono en vertical"
    public static let problemaOscura = "Salió oscura. Buscá más luz, de frente a una ventana"
    public static let problemaMovida = "Salió movida. Apoyá el teléfono o usá el temporizador"
    public static func problemaVieja(_ dias: Int) -> String { "Es de hace \(dias) días. Mati necesita una de esta semana" }
    public static let ilegible = "No se pudo leer esa foto. Probá con otra"
    public static let fotoRechazada = "Una foto no se pudo usar. Sacala de nuevo"
    public static let noSeGuardo = "No se pudo guardar la foto en el teléfono. Probá de nuevo"
    public static let sinSenal = "Sin señal: queda guardada y se sube sola"
    // Resumen
    public static func cuenta(_ n: Int) -> String { "\(n) de 3" }
    public static func faltan(_ n: Int) -> String { n == 1 ? "Te falta 1 foto" : "Te faltan \(n) fotos" }
    public static let listoTitulo = "Listo, Mati ya tiene tus fotos"
    public static let listoBajada = "Si querés repetir alguna, tocala"
    public static let repetir = "Repetir"
    // El físico que te motiva
    public static let motivacionTitulo = "El físico que te motiva"
    public static let opcional = "Opcional"
    public static let motivacionBajada = "Si hay un físico al que te gustaría acercarte, sumá una o más fotos y contale a Mati qué te gusta"
    public static let motivacionAgregar = "Agregar foto"
    public static let motivacionNota = "Qué te gusta de ese físico"
    public static let motivacionGuardar = "Guardar nota"
    public static let motivacionGuardada = "Nota guardada"
    public static let motivacionTope = "Hasta 4 fotos"
    public static let borrarFoto = "Borrar foto"
    public static let notaSinSenal = "Sin señal: la nota queda guardada y se manda sola"
    // Botones
    public static let cerrar = "Cerrar"
    public static let siguiente = "Siguiente"
    public static let listoBoton = "Listo"
    public static let listoTeclado = "Listo"
}
