#!/bin/bash
# Cuenta de servicio del pipeline de Vertex. UNICA y MULTIPROYECTO.
# "La cuenta de servicio unica que van a tener es la de Vertex... voy a apuntar
#  a todos los proyectos con una sola cuenta de servicio" - Sesion 3 CD, 2:02:45
PROC=dp-mlops17-ohuaman-pf-proc
FUENTE=dp-mlops17-ohuaman-pf-fuente
PRD=dp-mlops17-ohuaman-pf-prd
BUCKET=dp-mlops17-ohuaman-pf-vertex
SA="serviceAccount:sa-vertex-pipeline@${PROC}.iam.gserviceaccount.com"

gcloud iam service-accounts create sa-vertex-pipeline --project="$PROC" \
  --display-name="SA Vertex Pipeline - Proyecto Final"

# Roles de ejecucion en el proyecto de procesamiento (sa_process.txt de clase)
for R in artifactregistry.reader bigquery.jobUser bigquery.readSessionUser \
         bigquery.resourceViewer logging.logWriter monitoring.metricWriter \
         monitoring.viewer iam.serviceAccountOpenIdTokenCreator aiplatform.user; do
  gcloud projects add-iam-policy-binding "$PROC" --member="$SA" --role="roles/$R" --condition=None
done

# Acceso a DATOS, a nivel de dataset.
#   FUENTE     -> solo lectura: son tablas productivas de otro equipo.
#   PRODUCCION -> lectura y escritura: el proceso inserta su resultado.
#   PROCESAMIENTO -> lectura y escritura: tablas temporales propias.
# (se conceden desde la consola o parcheando la metadata del dataset)

# Modelo en Cloud Storage
gcloud storage buckets add-iam-policy-binding "gs://${BUCKET}" --member="$SA" \
  --role="roles/storage.objectAdmin" --project="$PROC"
