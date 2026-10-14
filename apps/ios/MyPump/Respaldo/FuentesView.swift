import SwiftUI
import SafariServices

/// "Respaldo científico" (App Store 1.4.1, cliente.html:4711-4837): las guías y trabajos en los que se apoyan los números
/// y las recomendaciones, agrupados por la afirmación que respaldan, cada uno con su link (navegador interno) y la URL
/// como texto seleccionable, y el aviso legal al final. Se abre desde el renglón pegado a los números de Dieta y desde
/// el pie de Dieta, Entreno y Mi Día.
struct FuentesView: View {
    @Environment(\.dismiss) private var cerrar
    @State private var abierta: URL?

    struct Fuente: Identifiable {
        let ref: String
        let url: String
        var id: String { url }
    }

    static let grupos: [(titulo: String, fuentes: [Fuente])] = [
        ("Cómo se calcula tu objetivo de calorías", [
            Fuente(ref: "Mifflin MD, St Jeor ST, Hill LA, et al. A new predictive equation for resting energy expenditure in healthy individuals. Am J Clin Nutr. 1990;51(2):241-247.",
                   url: "https://pubmed.ncbi.nlm.nih.gov/2305711/"),
            Fuente(ref: "National Institutes of Health (NIDDK). Body Weight Planner — modelo de balance energético.",
                   url: "https://www.niddk.nih.gov/health-information/weight-management/body-weight-planner"),
        ]),
        ("De dónde salen tus carbohidratos y tus grasas", [
            Fuente(ref: "National Academies of Sciences, Engineering, and Medicine (Institute of Medicine). Dietary Reference Intakes for Energy, Carbohydrate, Fiber, Fat, Fatty Acids, Cholesterol, Protein, and Amino Acids. 2005.",
                   url: "https://www.nationalacademies.org/publications/10490"),
            Fuente(ref: "Aragon AA, Schoenfeld BJ, Wildman R, et al. International Society of Sports Nutrition position stand: diets and body composition. J Int Soc Sports Nutr. 2017;14:16.",
                   url: "https://pmc.ncbi.nlm.nih.gov/articles/PMC5470183/"),
        ]),
        ("Cuánta proteína y por qué", [
            Fuente(ref: "Jäger R, Kerksick CM, Campbell BI, et al. International Society of Sports Nutrition position stand: protein and exercise. J Int Soc Sports Nutr. 2017;14:20.",
                   url: "https://pmc.ncbi.nlm.nih.gov/articles/PMC5477153/"),
            Fuente(ref: "Thomas DT, Erdman KA, Burke LM. Position of the Academy of Nutrition and Dietetics, Dietitians of Canada, and the American College of Sports Medicine: Nutrition and Athletic Performance. Med Sci Sports Exerc. 2016;48(3):543-568.",
                   url: "https://pubmed.ncbi.nlm.nih.gov/26920240/"),
        ]),
        ("Elección de alimentos y porciones", [
            Fuente(ref: "Organización Mundial de la Salud. Alimentación sana (nota descriptiva).",
                   url: "https://www.who.int/news-room/fact-sheets/detail/healthy-diet"),
            Fuente(ref: "U.S. Departments of Agriculture and Health and Human Services. Dietary Guidelines for Americans, 2025-2030.",
                   url: "https://odphp.health.gov/our-work/nutrition-physical-activity/dietary-guidelines/current-dietary-guidelines"),
        ]),
        ("Hidratación", [
            Fuente(ref: "National Academies of Sciences, Engineering, and Medicine (Institute of Medicine). Dietary Reference Intakes for Water, Potassium, Sodium, Chloride, and Sulfate. 2005.",
                   url: "https://www.nationalacademies.org/publications/10925"),
        ]),
        ("Entrenamiento: intensidad, volumen y progresión", [
            Fuente(ref: "American College of Sports Medicine. Position stand: Progression models in resistance training for healthy adults. Med Sci Sports Exerc. 2009;41(3):687-708.",
                   url: "https://pubmed.ncbi.nlm.nih.gov/19204579/"),
            Fuente(ref: "Garber CE, Blissmer B, Deschenes MR, et al. American College of Sports Medicine position stand: Quantity and quality of exercise for developing and maintaining fitness in apparently healthy adults. Med Sci Sports Exerc. 2011;43(7):1334-1359.",
                   url: "https://pubmed.ncbi.nlm.nih.gov/21694556/"),
            Fuente(ref: "Organización Mundial de la Salud. Actividad física (nota descriptiva).",
                   url: "https://www.who.int/news-room/fact-sheets/detail/physical-activity"),
            Fuente(ref: "MedlinePlus (U.S. National Library of Medicine). Exercise and Physical Fitness.",
                   url: "https://medlineplus.gov/exerciseandphysicalfitness.html"),
        ]),
        ("Guía local (Argentina)", [
            Fuente(ref: "Ministerio de Salud de la Nación. Guías Alimentarias para la Población Argentina (GAPA).",
                   url: "https://www.argentina.gob.ar/sites/default/files/bancos/2020-08/guias-alimentarias-para-la-poblacion-argentina.pdf"),
        ]),
    ]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Tu plan lo arma Mati, que es médico. Estas son las guías y los trabajos publicados en los que se apoyan los números y las recomendaciones que ves acá.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 0, leading: 4, bottom: 0, trailing: 4))
                }
                ForEach(Self.grupos, id: \.titulo) { g in
                    Section(g.titulo) {
                        ForEach(g.fuentes) { f in fila(f) }
                    }
                }
                Section {
                    Text("MyPump es una herramienta para seguir tu plan de entrenamiento y nutrición, pensada para personas sanas. No es un dispositivo médico y no reemplaza la consulta con un profesional de la salud. Si tenés alguna condición médica, estás embarazada o tomás medicación, consultá con tu médico antes de empezar o de cambiar tu plan, y avisale a Mati para adaptarlo. Si algo te hace sentir mal, pará y consultá.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Respaldo científico")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Listo") { cerrar() } } }
            .sheet(item: Binding(get: { abierta.map(URLIdentificable.init) }, set: { abierta = $0?.url })) { u in
                NavegadorInterno(url: u.url).ignoresSafeArea()
            }
        }
        .presentationDragIndicator(.visible)
    }

    private func fila(_ f: Fuente) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(f.ref).font(.subheadline)
            Text(f.url).font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled).lineLimit(2)
            Button {
                abierta = URL(string: f.url)
            } label: {
                Label("Abrir fuente", systemImage: "safari").font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.borderless)
            .tint(Color.marcaTexto)
        }
        .padding(.vertical, 4)
    }
}

private struct URLIdentificable: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

/// SFSafariViewController: el navegador del sistema dentro de la app (fuentes, relojes).
struct NavegadorInterno: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let c = SFSafariViewController(url: url)
        c.preferredControlTintColor = UIColor(Color.marcaTexto)
        c.dismissButtonStyle = .close
        return c
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}

/// La fila al pie de Dieta, Entreno y Mi Día (GEN-09): "Respaldo científico del plan" con las siglas de cada escena.
struct PieRespaldo: View {
    enum Origen { case dieta, entreno, miDia }
    let origen: Origen
    @State private var abierta = false

    private var subtitulo: String {
        switch origen {
        case .dieta: "Mifflin-St Jeor · ISSN · NASEM · OMS · Guías Alimentarias (Argentina)"
        case .entreno: "ACSM · OMS · MedlinePlus (NIH)"
        case .miDia: "NASEM · OMS · MedlinePlus (NIH)"
        }
    }

    var body: some View {
        Button { abierta = true } label: {
            HStack(spacing: 12) {
                Image(systemName: "book.closed.fill").foregroundStyle(Color.marcaTexto)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Respaldo científico del plan").font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                    Text(subtitulo).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.leading)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
            }
            .padding(14)
            .background(Color.tarjeta, in: .rect(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("respaldo-cientifico")
        .sheet(isPresented: $abierta) { FuentesView() }
    }
}

/// El renglón pegado a los números ("Objetivos calculados con…· Ver fuentes") que abre las fuentes.
struct RenglonFuentes: View {
    @State private var abierta = false

    var body: some View {
        Button { abierta = true } label: { RespaldoCientifico() }
            .buttonStyle(.plain)
            .accessibilityHint("Abre las fuentes científicas")
            .sheet(isPresented: $abierta) { FuentesView() }
    }
}
