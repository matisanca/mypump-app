import SwiftUI
import SafariServices

/// Respaldo científico (App Store 1.4.1): las mismas 14 fuentes de la web (`FUENTES` en cliente.html), agrupadas por la
/// afirmación que respaldan. Cada una se abre en Safari dentro de la app, y la URL además se puede seleccionar y copiar.
struct FuentesView: View {
    @Environment(\.dismiss) private var cerrar
    @State private var abierta: FuenteCientifica?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Tu plan lo arma Mati, que es médico. Estas son las guías y los trabajos publicados en los que se apoyan los números y las recomendaciones que ves acá.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 0, leading: 4, bottom: 4, trailing: 4))
                }
                ForEach(FuenteCientifica.grupos) { grupo in
                    Section(grupo.titulo) {
                        ForEach(grupo.fuentes) { fuente in
                            VStack(alignment: .leading, spacing: Espacio.xs) {
                                Text(fuente.referencia).font(.subheadline)
                                Text(fuente.url.absoluteString)
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                                    .lineLimit(2)
                                Button { abierta = fuente } label: {
                                    Label("Abrir fuente", systemImage: "safari")
                                        .font(.footnote.weight(.semibold))
                                }
                                .buttonStyle(.borderless)
                                .tint(Color.marcaTexto)
                                .padding(.top, 2)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
                Section {
                    Text("MyPump es una herramienta para seguir tu plan de entrenamiento y nutrición, pensada para personas sanas. No es un dispositivo médico y no reemplaza la consulta con un profesional de la salud. Si tenés alguna condición médica, estás embarazada o tomás medicación, consultá con tu médico antes de empezar o de cambiar tu plan, y avisale a Mati para adaptarlo. Si algo te hace sentir mal, pará y consultá.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4))
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Respaldo científico")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Listo") { cerrar() }.fontWeight(.semibold)
                }
            }
            .sheet(item: $abierta) { fuente in
                NavegadorInterno(url: fuente.url).ignoresSafeArea()
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
}

/// Safari dentro de la app (SFSafariViewController): el cliente lee la fuente y vuelve sin perder dónde estaba.
struct NavegadorInterno: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let vc = SFSafariViewController(url: url)
        vc.preferredControlTintColor = UIColor(hex: 0x3F6212)
        vc.dismissButtonStyle = .done
        return vc
    }

    func updateUIViewController(_ vc: SFSafariViewController, context: Context) {}
}

struct FuenteCientifica: Identifiable, Hashable {
    let referencia: String
    let url: URL
    var id: String { url.absoluteString }

    struct Grupo: Identifiable {
        let titulo: String
        let fuentes: [FuenteCientifica]
        var id: String { titulo }
    }

    private init(_ referencia: String, _ url: String) {
        self.referencia = referencia
        self.url = URL(string: url)!
    }

    static let grupos: [Grupo] = [
        Grupo(titulo: "Cómo se calcula tu objetivo de calorías", fuentes: [
            .init("Mifflin MD, St Jeor ST, Hill LA, et al. A new predictive equation for resting energy expenditure in healthy individuals. Am J Clin Nutr. 1990;51(2):241-247.",
                  "https://pubmed.ncbi.nlm.nih.gov/2305711/"),
            .init("National Institutes of Health (NIDDK). Body Weight Planner — modelo de balance energético.",
                  "https://www.niddk.nih.gov/health-information/weight-management/body-weight-planner"),
        ]),
        Grupo(titulo: "De dónde salen tus carbohidratos y tus grasas", fuentes: [
            .init("National Academies of Sciences, Engineering, and Medicine (Institute of Medicine). Dietary Reference Intakes for Energy, Carbohydrate, Fiber, Fat, Fatty Acids, Cholesterol, Protein, and Amino Acids. 2005.",
                  "https://www.nationalacademies.org/publications/10490"),
            .init("Aragon AA, Schoenfeld BJ, Wildman R, et al. International Society of Sports Nutrition position stand: diets and body composition. J Int Soc Sports Nutr. 2017;14:16.",
                  "https://pmc.ncbi.nlm.nih.gov/articles/PMC5470183/"),
        ]),
        Grupo(titulo: "Cuánta proteína y por qué", fuentes: [
            .init("Jäger R, Kerksick CM, Campbell BI, et al. International Society of Sports Nutrition position stand: protein and exercise. J Int Soc Sports Nutr. 2017;14:20.",
                  "https://pmc.ncbi.nlm.nih.gov/articles/PMC5477153/"),
            .init("Thomas DT, Erdman KA, Burke LM. Position of the Academy of Nutrition and Dietetics, Dietitians of Canada, and the American College of Sports Medicine: Nutrition and Athletic Performance. Med Sci Sports Exerc. 2016;48(3):543-568.",
                  "https://pubmed.ncbi.nlm.nih.gov/26920240/"),
        ]),
        Grupo(titulo: "Elección de alimentos y porciones", fuentes: [
            .init("Organización Mundial de la Salud. Alimentación sana (nota descriptiva).",
                  "https://www.who.int/news-room/fact-sheets/detail/healthy-diet"),
            .init("U.S. Departments of Agriculture and Health and Human Services. Dietary Guidelines for Americans, 2025-2030.",
                  "https://odphp.health.gov/our-work/nutrition-physical-activity/dietary-guidelines/current-dietary-guidelines"),
        ]),
        Grupo(titulo: "Hidratación", fuentes: [
            .init("National Academies of Sciences, Engineering, and Medicine (Institute of Medicine). Dietary Reference Intakes for Water, Potassium, Sodium, Chloride, and Sulfate. 2005.",
                  "https://www.nationalacademies.org/publications/10925"),
        ]),
        Grupo(titulo: "Entrenamiento: intensidad, volumen y progresión", fuentes: [
            .init("American College of Sports Medicine. Position stand: Progression models in resistance training for healthy adults. Med Sci Sports Exerc. 2009;41(3):687-708.",
                  "https://pubmed.ncbi.nlm.nih.gov/19204579/"),
            .init("Garber CE, Blissmer B, Deschenes MR, et al. American College of Sports Medicine position stand: Quantity and quality of exercise for developing and maintaining fitness in apparently healthy adults. Med Sci Sports Exerc. 2011;43(7):1334-1359.",
                  "https://pubmed.ncbi.nlm.nih.gov/21694556/"),
            .init("Organización Mundial de la Salud. Actividad física (nota descriptiva).",
                  "https://www.who.int/news-room/fact-sheets/detail/physical-activity"),
            .init("MedlinePlus (U.S. National Library of Medicine). Exercise and Physical Fitness.",
                  "https://medlineplus.gov/exerciseandphysicalfitness.html"),
        ]),
        Grupo(titulo: "Guía local (Argentina)", fuentes: [
            .init("Ministerio de Salud de la Nación. Guías Alimentarias para la Población Argentina (GAPA).",
                  "https://www.argentina.gob.ar/sites/default/files/bancos/2020-08/guias-alimentarias-para-la-poblacion-argentina.pdf"),
        ]),
    ]
}
