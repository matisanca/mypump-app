-- ============================================================
-- Seed 01 — Rutina y dieta de prueba para cliente test-001
-- Idempotente: archiva la rutina/dieta activa anterior primero.
-- Aplicar en: Supabase Dashboard → SQL Editor
-- ============================================================

-- Archivar rutina activa anterior (si existe)
UPDATE mypump_rutinas
  SET estado = 'archivada'
WHERE cliente_id = 'test-001' AND estado = 'activa';

-- Insertar rutina de prueba
INSERT INTO mypump_rutinas (
  cliente_id, version, estado, estructura, semana_actual, fecha_inicio
) VALUES (
  'test-001',
  1,
  'activa',
  '{
    "nombre_plan": "Mesociclo Test - Hipertrofia",
    "perfil": {
      "nivel": "intermedio",
      "split": "PPL x2 - 6 días",
      "diasSemana": 6,
      "objetivo": "Hipertrofia",
      "resumen": "Plan de prueba con 2 días simulados"
    },
    "semanas_total": 12,
    "dias": [
      {
        "n": 1,
        "id": "lun",
        "nombre": "TIRÓN A - ANCHO",
        "abreviado": "LUN",
        "bloques": [
          {
            "titulo": "BLOQUE 1 — ESPALDA",
            "subtitulo": "ESPALDA",
            "ejercicios": [
              {
                "id": "ex_jalon",
                "nombre": "Jalón al pecho prono",
                "tipo": "compuesto",
                "series": 4,
                "reps": "8-10",
                "rir_objetivo": "1-2",
                "descanso_segundos": 150,
                "video_url": null,
                "notas_tecnica": "Foco en bajada controlada"
              },
              {
                "id": "ex_remo",
                "nombre": "Remo con barra",
                "tipo": "compuesto",
                "series": 3,
                "reps": "8-10",
                "rir_objetivo": "1-2",
                "descanso_segundos": 150,
                "video_url": null,
                "notas_tecnica": null
              }
            ]
          },
          {
            "titulo": "BLOQUE 2 — BÍCEPS",
            "subtitulo": "BÍCEPS",
            "ejercicios": [
              {
                "id": "ex_curl",
                "nombre": "Curl con barra Z",
                "tipo": "aislamiento",
                "series": 3,
                "reps": "10-12",
                "rir_objetivo": "0-1",
                "descanso_segundos": 90,
                "video_url": null,
                "notas_tecnica": null
              }
            ]
          }
        ]
      },
      {
        "n": 2,
        "id": "mar",
        "nombre": "EMPUJE A - PECHO",
        "abreviado": "MAR",
        "bloques": [
          {
            "titulo": "BLOQUE 1 — PECHO",
            "subtitulo": "PECHO",
            "ejercicios": [
              {
                "id": "ex_press",
                "nombre": "Press banca plano",
                "tipo": "compuesto",
                "series": 4,
                "reps": "6-8",
                "rir_objetivo": "1-2",
                "descanso_segundos": 180,
                "video_url": null,
                "notas_tecnica": "Pausa 1seg en el pecho"
              }
            ]
          }
        ]
      }
    ],
    "mensajes_semana": [
      { "n": 1, "titulo": "Semana 1 - Introducción", "msg": "Arrancamos suave" },
      { "n": 2, "titulo": "Semana 2 - Calibración", "msg": "Ajustamos cargas" },
      { "n": 3, "titulo": "Semana 3 - Sostener", "msg": "Mantenemos volumen" }
    ]
  }'::jsonb,
  3,
  CURRENT_DATE - INTERVAL '14 days'
);

-- Archivar dieta activa anterior (si existe)
UPDATE mypump_dietas
  SET estado = 'archivada'
WHERE cliente_id = 'test-001' AND estado = 'activa';

-- Insertar dieta de prueba (Formato A)
INSERT INTO mypump_dietas (
  cliente_id, version, estado, estructura
) VALUES (
  'test-001',
  1,
  'activa',
  '{
    "macros_target": { "kcal": 3200, "prot": 220, "carb": 380, "fat": 90 },
    "comidas": [
      {
        "id": "c1",
        "name": "Desayuno",
        "options": [
          {
            "name": "A",
            "foods": [
              { "name": "Avena", "qty": 100, "unit": "g", "kcal": 380, "prot": 13, "carb": 67, "fat": 7, "category": "carbohidrato", "swappable": true },
              { "name": "Huevos enteros", "qty": 3, "unit": "unidad", "kcal": 234, "prot": 18, "carb": 0, "fat": 18, "category": "proteina", "swappable": true }
            ]
          }
        ]
      },
      {
        "id": "c2",
        "name": "Almuerzo",
        "options": [
          {
            "name": "A",
            "foods": [
              { "name": "Pechuga de pollo", "qty": 200, "unit": "g", "kcal": 330, "prot": 62, "carb": 0, "fat": 7, "category": "proteina", "swappable": true },
              { "name": "Arroz blanco cocido", "qty": 150, "unit": "g", "kcal": 195, "prot": 4, "carb": 42, "fat": 0, "category": "carbohidrato", "swappable": true }
            ]
          }
        ]
      }
    ]
  }'::jsonb
);
