# Proyecto Final MLOps 17 — Pipeline de predicción en GCP

**Omar Rodrigo Huaman Rivera** · DataPath, MLOps Engineer 17ª Edición

Automatización de un pipeline de predicción de Machine Learning repartido en
**tres proyectos de Google Cloud**, según la arquitectura del enunciado
`Proyecto.pdf` y el diagrama `Proyecto_Final.png`.

---

## 1. Arquitectura

```
PROYECTO FUENTE                 PROYECTO PROCESAMIENTO            PROYECTO PRODUCCIÓN
dp-...-pf-fuente                dp-...-pf-proc                    dp-...-pf-prd

hist_table.input_data   ──┐
hist_table.selected_f.  ──┤     [Vertex AI Pipeline]
                          └──▶  ① BigqueryQueryJobOp
                                   └─ CALL prc_preparar_universo
                                      └─▶ ds_procesamiento.table_output
                                ② prediction (Python)
                                   ├─ lee table_output
                                   ├─ carga el modelo del bucket     ──▶ ds_produccion.
                                   └─ escribe las predicciones            ba_modelo_propension_inscripcion

                                gs://dp-...-pf-vertex
                                  demo/pipeline_prediction.yaml
                                  demo/data/model/linear_regression.joblib

                                Cloud Run Job  ◀── Cloud Scheduler (pausado)
```

El modelo es un `Lasso` de scikit-learn que predice el **logaritmo del precio de
venta de viviendas** (dataset Ames Housing), con 36 variables ya normalizadas
entre 0 y 1. Es el mismo modelo que recorre el bootcamp desde el Módulo 2.

---

## 2. Las tres cuentas de servicio

Una sola cuenta accede a los datos de los tres proyectos, y cada servicio de
orquestación tiene la suya con el mínimo imprescindible.

| Cuenta | Qué hace | Permisos |
|---|---|---|
| `sa-vertex-pipeline` | Ejecuta el pipeline y toca BigQuery de los 3 proyectos | ver tabla §3 |
| `sa-cloud-run-job` | Lanza el PipelineJob | `aiplatform.user`, `iam.serviceAccountTokenCreator`, `storage.objectViewer`, **`iam.serviceAccountUser` sobre `sa-vertex-pipeline`** |
| `sa-scheduler` | Dispara el Cloud Run Job | `run.invoker` sobre el job, y nada más |
| `sa-github` | CI/CD | `run.admin`, `artifactregistry.writer`, escritura en el bucket, `serviceAccountUser` sobre las dos anteriores |

---

## 3. Por qué cada permiso es necesario

Esta sección responde al punto 5 del enunciado.

### Lectura en el proyecto fuente — `BigQuery Data Viewer`

El componente ① lee `hist_table.input_data` desde el proyecto de procesamiento.
Sin este rol, `validate_data` devuelve `false` y el pipeline entra en la rama de
error. **Se concede solo lectura, deliberadamente**: son tablas que en un
entorno real pertenecen a otro equipo y las puebla un proceso ajeno, por lo que
no corresponde poder editarlas.

### Escritura en el proyecto de producción — `BigQuery Data Editor` + `Data Viewer`

El componente ② inserta las predicciones en `ds_produccion`. Aquí sí hacen falta
los dos roles: la tabla la crea y alimenta nuestro propio proceso, y el editor
es imprescindible para el `INSERT`. El visor acompaña para poder leer el
histórico.

### Lectura del modelo en Cloud Storage — `Storage Object Viewer`

El componente ② descarga `linear_regression.joblib` del bucket. Se amplió a
`objectAdmin` porque Vertex además **escribe los artefactos de cada ejecución**
bajo `pipeline_root`, cosa que un rol de solo lectura impide.

### Tablas temporales en procesamiento — `Data Editor` + `Data Viewer`

`table_output` la crea y trunca el propio pipeline en cada ejecución.

### Suplantación de cuentas — `iam.serviceAccountUser`

Quien ejecuta el Cloud Run Job es `sa-cloud-run-job`, pero el pipeline debe
correr como `sa-vertex-pipeline`, que es la que tiene los accesos a datos. Para
que una cuenta pueda lanzar algo *en nombre de* otra, necesita este rol sobre
ella. Es el permiso que más se olvida y sin él el `job.submit()` falla.

### Herencia

Los permisos de datos se conceden a nivel de **dataset**, no de tabla, y se
heredan a todas las tablas que contiene. En la consola, un permiso heredado
aparece con un icono propio y no se puede editar desde la tabla.

---

## 4. Estructura del repositorio

```
my_app/
  pipeline_prediction.py       definición del pipeline (KFP 2)
  pipeline_prediction.yaml     compilado, se sube al bucket
  requirements.txt
despliegue_cloud_run/
  main.py                      lanza el PipelineJob leyendo variables de entorno
  Dockerfile
  requirements.txt
sql/
  componente1.sql              tabla temporal y stored procedure
permisos/
  01_sa_vertex.sh
  02_sa_cloud_run_y_scheduler.sh
.github/workflows/
  cd_vertex.yaml               compila, sube el pipeline, construye y despliega
```

---

## 5. Nota de migración: el stack del curso quedó obsoleto

El material de clase fija `kfp==1.8.21`. Al lanzar el pipeline, Vertex AI lo
rechaza:

```
SchemaVersion < 2.0.0 are not longer supported.
```

Google retiró el soporte de ese formato, de modo que la migración a **KFP 2** es
obligatoria. Los cambios:

| Clase (kfp 1.8) | Aquí (kfp 2.17) |
|---|---|
| `kfp.v2.dsl`, `@component` | `kfp.dsl`, `@dsl.component` |
| `dsl.Condition` | `dsl.If` |
| `string.Template` sobre un parámetro | componente `build_query` |
| compila a `.json` | compila a `.yaml` |

El tercero es el único cambio de diseño: KFP 2 no permite interpolar parámetros
del pipeline dentro de una cadena, así que la llamada parametrizada al stored
procedure se construye dentro de un componente. La estructura —validación,
condicional de dos ramas, `ExitHandler` con notificación— es la de clase.

---

## 6. Costo

Calculado con el método del PPT `Costos_Pipeline_Prediccion.pptx` (Módulo 8).

| Servicio | Situación | Costo |
|---|---|---|
| BigQuery consultas | 1 TB/mes gratis; aquí se leen megabytes | $0 |
| BigQuery almacenamiento | 10 GB/mes gratis | $0 |
| Cloud Storage | capa gratuita | ~$0 |
| Cloud Scheduler | 3 jobs gratis | $0 |
| Cloud Run Job | ejecuciones de segundos | ~$0 |
| **Vertex AI Pipelines** | e2-standard-4 a $0.160814/h | **~$0.02 por ejecución** |

Medidas de control aplicadas: presupuesto con alertas al 50/90/100 % sobre toda
la cuenta de facturación, Scheduler creado pero **en pausa**, e imagen basada en
`python:3.11-slim` en lugar de `python:3.8` para no agotar la capa gratuita de
Artifact Registry.
