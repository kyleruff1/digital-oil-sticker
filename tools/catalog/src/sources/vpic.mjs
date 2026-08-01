// vPIC adapters (DOS-M03-004/005). ONLY type-scoped, make-ID-based endpoints.
// The name-substring endpoints (GetModelsForMakeYear/make/<name>) and
// GetAllMakes are PROHIBITED (junk-make evidence in ADR-0003 / the M00-006
// spike); a static-scan quality gate (Q2) enforces their absence.

const BASE = 'https://vpic.nhtsa.dot.gov/api/vehicles'
export const LIGHT_DUTY_TYPES = ['car', 'mpv', 'truck']

function parseEnvelope(name, body) {
  let j
  try {
    j = JSON.parse(body)
  } catch (e) {
    throw new Error(`${name}: vPIC response is not JSON: ${e.message}`)
  }
  if (!Array.isArray(j.Results)) throw new Error(`${name}: vPIC envelope missing Results`)
  return j
}

export async function fetchVehicleTypeIds(client) {
  const name = 'vpic-variable-values-vehicle-type'
  const { body } = await client.fetchCached(name, `${BASE}/GetVehicleVariableValuesList/vehicle%20type?format=json`)
  const j = parseEnvelope(name, body)
  return j.Results.map(r => ({ id: r.Id, name: r.Name }))
}

export async function fetchMakesForType(client, type) {
  const name = `vpic-makes-for-type-${type}`
  const { body } = await client.fetchCached(name, `${BASE}/GetMakesForVehicleType/${type}?format=json`)
  const j = parseEnvelope(name, body)
  return j.Results.map(r => ({
    make_id: r.MakeId,
    make_name: r.MakeName,
    vehicle_type_id: r.VehicleTypeId,
    vehicle_type_name: r.VehicleTypeName,
  }))
}

export async function fetchTypesForMake(client, makeId) {
  const name = `vpic-types-for-make-${makeId}`
  const { body } = await client.fetchCached(name, `${BASE}/GetVehicleTypesForMakeId/${makeId}?format=json`)
  const j = parseEnvelope(name, body)
  return j.Results.map(r => ({ type_id: r.VehicleTypeId, type_name: r.VehicleTypeName }))
}

export async function fetchModelsForMakeIdYearType(client, makeId, year, type) {
  const name = `vpic-models-${makeId}-${year}-${type}`
  const { body, fromCache } = await client.fetchCached(
    name,
    `${BASE}/GetModelsForMakeIdYear/makeId/${makeId}/modelyear/${year}/vehicleType/${type}?format=json`,
  )
  const j = parseEnvelope(name, body)
  return {
    fromCache,
    count: j.Count,
    models: j.Results.map(r => ({
      vpic_make_id: r.Make_ID ?? r.MakeId,
      make_name: r.Make_Name ?? r.MakeName,
      vpic_model_id: r.Model_ID ?? r.ModelId,
      model_name: r.Model_Name ?? r.ModelName,
      vehicle_type_id: r.VehicleTypeId ?? null,
      vehicle_type_name: r.VehicleTypeName ?? null,
      source_record: name,
    })),
  }
}
