package com.getcapacitor

import org.json.JSONArray
import org.json.JSONObject

// Lo único de Capacitor que usa el HealthManager del plugin: sus JSObject y JSArray son un JSONObject y un JSONArray. Solo
// para el banco de salud (se compila con las pruebas, nunca con la app).

open class JSObject : JSONObject()

open class JSArray : JSONArray()
