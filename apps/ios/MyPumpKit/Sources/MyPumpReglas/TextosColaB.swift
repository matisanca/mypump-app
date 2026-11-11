import Foundation

/// Los textos de la cola B, iguales en iPhone, Android y la web (`cola-b/CONTRATO_APP.md`). Siempre «Mati»; sin fechas de
/// fin de plan. La prueba `TextosColaBTests` revisa que no se cuele ninguna palabra vedada.
public enum TextosColaB {
    public enum Recorrido {
        public static let tarjetaTitulo = "Tu recorrido con Mati"
        public static let tarjetaPublicado = "Mirá todo lo que hiciste en estos meses."
        public static let tarjetaPedido = "Mati ya recibió tu pedido."
        public static let tarjetaAgendado = "Tu videollamada con Mati ya está agendada."
        public static let ver = "Ver mi recorrido"
        public static let titulo = "Tu recorrido"
        public static let antesTitulo = "Antes de hablar con Mati"
        public static let antesTexto = "Si querés, contale esto. Le sirve para prepararse."
        public static let agendar = "Agendar con Mati"
        public static let agendarPie = "Es una videollamada para ver cómo seguimos."
        public static let enviando = "Enviando…"
        public static let error = "No se pudo enviar. Probá de nuevo."
        public static let listo = "Listo. Mati ya recibió tu pedido."
        public static let listoMati = "Te escribe para coordinar el horario."
        public static let listoApp = "Cuando esté tu horario lo vas a ver arriba de Entreno."
        public static let cerrar = "Cerrar"

        public static func tarjeta(_ e: EstadoRecorrido.Estado) -> String {
            switch e {
            case .publicado: tarjetaPublicado
            case .pedido: tarjetaPedido
            case .agendado: tarjetaAgendado
            }
        }
    }

    public enum Compras {
        public static let boton = "Dónde comprarlo"
        public static let ayuda = "Tocá “Dónde comprarlo” para ver dónde conseguir cada suplemento."
        public static let abrirTienda = "Abrir la tienda"
        public static let pie = "Son lugares que Mati revisó."
        public static let cerrar = "Cerrar"
    }

    public enum Casa {
        public static let interruptor = "Entreno en casa"
        public static let interruptorBajada = "Prendelo si entrenás en tu casa y no en un gimnasio."
        public static let fijo = "Ya lo recibimos. Lo vas a poder cambiar cuando esté listo."
        public static let errorCambiar = "No se pudo cambiar. Probá de nuevo."
        public static let listaTitulo = "¿Qué tenés en casa?"
        public static let listaTexto = "Marcá todo lo que tengas. Con eso Mati arma tu rutina."
        public static let kilos = "Hasta cuántos kilos (opcional)"
        public static let sinEquipo = "No tengo nada de esto"
        public static let nota = "¿Algo más que quieras contarle a Mati?"
        public static let enviar = "Enviar a Mati"
        public static let enviando = "Enviando…"
        public static let errorEnviar = "No se pudo enviar. Probá de nuevo."
        public static let sinDatos = "Marcá lo que tenés, o “No tengo nada de esto”."
        public static let vigenteTitulo = "Entrenás en casa"
        public static let vigenteSinEquipo = "Sin equipo: entrenás con tu cuerpo."
        public static let cambiar = "Cambió lo que tengo en casa"
        public static let tarjeta = "¿Entrenás en casa? Tocá acá"
    }

    /// Todos, para la prueba de palabras vedadas.
    public static let todos: [String] = [
        Recorrido.tarjetaTitulo, Recorrido.tarjetaPublicado, Recorrido.tarjetaPedido, Recorrido.tarjetaAgendado, Recorrido.ver,
        Recorrido.titulo, Recorrido.antesTitulo, Recorrido.antesTexto, Recorrido.agendar, Recorrido.agendarPie, Recorrido.enviando,
        Recorrido.error, Recorrido.listo, Recorrido.listoMati, Recorrido.listoApp, Recorrido.cerrar,
        Compras.boton, Compras.ayuda, Compras.abrirTienda, Compras.pie, Compras.cerrar,
        Casa.interruptor, Casa.interruptorBajada, Casa.fijo, Casa.errorCambiar, Casa.listaTitulo, Casa.listaTexto, Casa.kilos,
        Casa.sinEquipo, Casa.nota, Casa.enviar, Casa.enviando, Casa.errorEnviar, Casa.sinDatos, Casa.vigenteTitulo,
    ] + MyPumpReglas.Recorrido.preguntas.map(\.texto)
}
