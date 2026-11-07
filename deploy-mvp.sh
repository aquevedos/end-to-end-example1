#!/usr/bin/env bash
####################################################################################
# Script de Despliegue Universal y Modular MVP (Cualquier ruta, correo y proyecto)
#
# Formas de uso:
#   1. Despliegue base rápido (usa tu cuenta y proyecto activos de gcloud):
#      ./deploy-mvp.sh
#
#   2. Pasando solo el Project ID (usa tu cuenta activa de gcloud):
#      ./deploy-mvp.sh "tu-project-id"
#
#   3. Despliegue en OTRO correo y OTRO proyecto (aislando su estado automáticamente):
#      ./deploy-mvp.sh "otro-correo@dominio.com" "otro-project-id"
#
#   4. Encender Cloud Composer y/o Colab Runtime (al inicio o en una 2da ejecución):
#      ./deploy-mvp.sh --with-composer
#      ./deploy-mvp.sh --with-colab
#      ./deploy-mvp.sh --all
#      ./deploy-mvp.sh "otro-correo@dominio.com" "otro-project-id" --all
####################################################################################
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF_DIR="${REPO_DIR}/terraform"

# Función de ayuda
show_help() {
  cat << 'EOF'
Uso de deploy-mvp.sh:
  ./deploy-mvp.sh [OPCIONES] [CORREO_O_PROJECT_ID] [PROJECT_ID_O_CORREO] [PROJECT_NUMBER]

Opciones:
  --with-composer    Habilita Cloud Composer 3 (por defecto deshabilitado en MVP)
  --with-colab       Habilita Colab Enterprise Runtime VM persistente
  --all              Habilita tanto Composer como Colab Runtime
  -h, --help         Muestra este mensaje de ayuda

Ejemplos:
  ./deploy-mvp.sh
  ./deploy-mvp.sh "seccion1-513621"
  ./deploy-mvp.sh "usuario@dominio.com" "seccion1-513621"
  ./deploy-mvp.sh "seccion1-513621" --all
EOF
  exit 0
}

# 0. Verificación de binarios requeridos en el sistema
for bin in gcloud terraform jq curl python3; do
  if ! command -v "${bin}" >/dev/null 2>&1; then
    echo "❌ Error: La herramienta '${bin}' no está instalada o no está en el PATH."
    echo "   Por favor instálala antes de continuar."
    exit 1
  fi
done

ENABLE_COMPOSER="${ENABLE_COMPOSER:-false}"
ENABLE_COLAB_RUNTIME="${ENABLE_COLAB_RUNTIME:-false}"
POS_ARGS=()

for arg in "$@"; do
  case "${arg}" in
    -h|--help)
      show_help
      ;;
    --with-composer)
      ENABLE_COMPOSER="true"
      ;;
    --with-colab)
      ENABLE_COLAB_RUNTIME="true"
      ;;
    --all)
      ENABLE_COMPOSER="true"
      ENABLE_COLAB_RUNTIME="true"
      ;;
    *)
      POS_ARGS+=("${arg}")
      ;;
  esac
done

# Detección inteligente de argumentos posicionales
RAW_ARG0="${POS_ARGS[0]:-}"
RAW_ARG1="${POS_ARGS[1]:-}"
RAW_ARG2="${POS_ARGS[2]:-}"

GCP_ACCOUNT_NAME=""
PROJECT_ID=""
PROJECT_NUMBER=""

if [[ -n "${RAW_ARG0}" && -z "${RAW_ARG1}" ]]; then
  # Si solo se pasa 1 argumento:
  if [[ "${RAW_ARG0}" == *"@"* ]]; then
    GCP_ACCOUNT_NAME="${RAW_ARG0}"
    PROJECT_ID="$(gcloud config get-value project 2>/dev/null || true)"
  else
    PROJECT_ID="${RAW_ARG0}"
    GCP_ACCOUNT_NAME="$(gcloud config get-value account 2>/dev/null || true)"
  fi
elif [[ -n "${RAW_ARG0}" && -n "${RAW_ARG1}" ]]; then
  # Si se pasan 2 argumentos:
  if [[ "${RAW_ARG0}" != *"@"* && "${RAW_ARG1}" == *"@"* ]]; then
    # Invertido: proyecto primero, luego correo
    PROJECT_ID="${RAW_ARG0}"
    GCP_ACCOUNT_NAME="${RAW_ARG1}"
  else
    GCP_ACCOUNT_NAME="${RAW_ARG0}"
    PROJECT_ID="${RAW_ARG1}"
  fi
  PROJECT_NUMBER="${RAW_ARG2}"
else
  # Sin argumentos: tomar los activos en gcloud
  GCP_ACCOUNT_NAME="$(gcloud config get-value account 2>/dev/null || true)"
  PROJECT_ID="$(gcloud config get-value project 2>/dev/null || true)"
fi

# Validación contra textos de ejemplo
PLACEHOLDERS=("otro-correo@dominio.com" "tu-correo@dominio.com" "otro-proyecto-id" "otro-project-id" "tu-proyecto-id" "tu-project-id" "my-project")
for p in "${PLACEHOLDERS[@]}"; do
  if [[ "${GCP_ACCOUNT_NAME}" == "${p}" || "${PROJECT_ID}" == "${p}" ]]; then
    echo "⚠️  Detectado texto de ejemplo ('${p}')."
    echo "👉 Reemplázalo por los valores reales de tu entorno de GCP, por ejemplo:"
    echo "   ./deploy-mvp.sh \"usuario@dominio.com\" \"mi-proyecto-id\""
    exit 1
  fi
done

if [[ -z "${GCP_ACCOUNT_NAME}" || -z "${PROJECT_ID}" ]]; then
  echo "❌ Error: Debes autenticarte en gcloud o pasar los parámetros:"
  echo "   ./deploy-mvp.sh <tu-correo-real@dominio.com> <tu-project-id-real> [--with-composer] [--with-colab] [--all]"
  exit 1
fi

export CLOUDSDK_CORE_ACCOUNT="${GCP_ACCOUNT_NAME}"
export CLOUDSDK_CORE_PROJECT="${PROJECT_ID}"
export CLOUDSDK_BILLING_QUOTA_PROJECT=""
export CLOUDSDK_AUTH_IMPERSONATE_SERVICE_ACCOUNT=""

# 1. Verifica y valida el token OAuth para ese correo (evitando tokens vencidos durante el apply)
ACCESS_TOKEN="$(gcloud auth print-access-token --account="${GCP_ACCOUNT_NAME}" 2>/dev/null || true)"
TOKEN_INFO="$(curl -s --max-time 10 "https://www.googleapis.com/oauth2/v1/tokeninfo?access_token=${ACCESS_TOKEN}" 2>/dev/null || true)"
EXPIRES_IN="$(echo "${TOKEN_INFO}" | python3 -c "import sys, json; print(json.load(sys.stdin).get('expires_in', 0))" 2>/dev/null || echo "0")"

if [[ -z "${ACCESS_TOKEN}" || "${EXPIRES_IN}" -lt 300 ]]; then
  echo "🔑 Token expirado o por expirar. Renovando sesión en gcloud para '${GCP_ACCOUNT_NAME}'..."
  gcloud auth login "${GCP_ACCOUNT_NAME}"
  ACCESS_TOKEN="$(gcloud auth print-access-token --account="${GCP_ACCOUNT_NAME}" 2>/dev/null || true)"
fi

if [[ -z "${ACCESS_TOKEN}" ]]; then
  echo "❌ Error: No se pudo obtener el token de acceso para '${GCP_ACCOUNT_NAME}'."
  exit 1
fi
export GOOGLE_OAUTH_ACCESS_TOKEN="${ACCESS_TOKEN}"

# 1.1 Asegura Application Default Credentials (ADC) para que Terraform renueve tokens automáticamente
if [[ ! -f "${HOME}/.config/gcloud/application_default_credentials.json" ]]; then
  echo "🔑 Configurando Application Default Credentials (ADC) para Terraform..."
  gcloud auth application-default login || true
fi

# 2. Obtiene el Project Number
if [[ -z "${PROJECT_NUMBER}" ]]; then
  PROJECT_NUMBER="$(gcloud projects describe "${PROJECT_ID}" --account="${GCP_ACCOUNT_NAME}" --format="value(projectNumber)" 2>/dev/null || true)"
fi

if [[ -z "${PROJECT_NUMBER}" ]]; then
  CRM_RESP="$(curl -s --max-time 10 -H "Authorization: Bearer ${ACCESS_TOKEN}" "https://cloudresourcemanager.googleapis.com/v1/projects/${PROJECT_ID}" 2>/dev/null || true)"
  PROJECT_NUMBER="$(echo "${CRM_RESP}" | python3 -c "import sys, json; d=json.load(sys.stdin); print(d.get('projectNumber',''))" 2>/dev/null || true)"
fi

if [[ -z "${PROJECT_NUMBER}" ]]; then
  echo "❌ Error: No se pudo encontrar el Project ID '${PROJECT_ID}' con la cuenta '${GCP_ACCOUNT_NAME}'."
  echo "🔎 Detalle devuelto por Google Cloud:"
  gcloud projects describe "${PROJECT_ID}" --account="${GCP_ACCOUNT_NAME}" 2>&1 || true
  echo ""
  echo "📋 Proyectos disponibles actualmente para '${GCP_ACCOUNT_NAME}':"
  gcloud projects list --account="${GCP_ACCOUNT_NAME}" --format="table(projectId,name,projectNumber)" || true
  echo ""
  echo "💡 Tip: También puedes pasar el Project Number directamente como 3er parámetro:"
  echo "   ./deploy-mvp.sh \"${GCP_ACCOUNT_NAME}\" \"${PROJECT_ID}\" \"158808485666\""
  exit 1
fi

# 2.1 Verificación y vinculación automática de Cuenta de Facturación (Billing Account)
echo "💳 Verificando facturación (Billing) en el proyecto '${PROJECT_ID}'..."
BILLING_ENABLED="$(gcloud billing projects describe "${PROJECT_ID}" --account="${GCP_ACCOUNT_NAME}" --format="value(billingEnabled)" 2>/dev/null || true)"

if [[ "${BILLING_ENABLED}" != "True" && "${BILLING_ENABLED}" != "true" ]]; then
  echo "⚠️  El proyecto '${PROJECT_ID}' no tiene una cuenta de facturación vinculada."
  
  # Buscar cuentas de facturación activas para el usuario
  AVAILABLE_BILLING_ACCOUNTS="$(gcloud billing accounts list --account="${GCP_ACCOUNT_NAME}" --filter="open=true" --format="value(ACCOUNT_ID)" 2>/dev/null || true)"
  if [[ -z "${AVAILABLE_BILLING_ACCOUNTS}" ]]; then
    AVAILABLE_BILLING_ACCOUNTS="$(gcloud billing accounts list --account="${GCP_ACCOUNT_NAME}" --filter="open=true" --format="value(name)" 2>/dev/null || true)"
  fi
  
  LINKED_SUCCESS=false
  if [[ -n "${AVAILABLE_BILLING_ACCOUNTS}" ]]; then
    FIRST_BILLING_ACCOUNT="$(echo "${AVAILABLE_BILLING_ACCOUNTS}" | head -n 1)"
    echo "🔗 Vinculando automáticamente la cuenta de facturación '${FIRST_BILLING_ACCOUNT}' a '${PROJECT_ID}'..."
    if gcloud billing projects link "${PROJECT_ID}" --billing-account="${FIRST_BILLING_ACCOUNT}" --account="${GCP_ACCOUNT_NAME}"; then
      echo "✅ Facturación vinculada exitosamente con '${FIRST_BILLING_ACCOUNT}'."
      LINKED_SUCCESS=true
    fi
  fi

  if [[ "${LINKED_SUCCESS}" != "true" ]]; then
    echo "❌ Error: El proyecto '${PROJECT_ID}' requiere tener facturación (Billing) habilitada."
    echo "   En Google Cloud, servicios como Compute, Cloud Run, Cloud Build y Dataflow requieren facturación para activarse."
    echo ""
    echo "💡 Pasos para solucionarlo:"
    echo "   1. Abre este enlace en tu navegador:"
    echo "      👉 https://console.cloud.google.com/billing/linkedaccount?project=${PROJECT_ID}"
    echo "   2. Selecciona o vincula tu cuenta de facturación."
    echo "   3. Vuelve a ejecutar este script."
    exit 1
  fi
fi

# 3. Pre-habilitación de APIs fundacionales críticas (garantiza que IAM y credenciales funcionen de inmediato)
echo "🔧 Verificando APIs esenciales de Google Cloud..."
gcloud services enable \
  serviceusage.googleapis.com \
  cloudresourcemanager.googleapis.com \
  iam.googleapis.com \
  iamcredentials.googleapis.com \
  --project="${PROJECT_ID}" --account="${GCP_ACCOUNT_NAME}" 2>/dev/null || true

# 4. Aislamiento modular de estado (tfstate) por proyecto
STATE_FILE="terraform.${PROJECT_ID}.tfstate"
if [[ ! -f "${TF_DIR}/${STATE_FILE}" && -f "${TF_DIR}/terraform.tfstate" ]]; then
  EXISTING_STATE_PROJECT="$(python3 -c "import json; d=json.load(open('${TF_DIR}/terraform.tfstate')); print(d.get('outputs',{}).get('project_id',{}).get('value',''))" 2>/dev/null || true)"
  if [[ "${EXISTING_STATE_PROJECT}" == "${PROJECT_ID}" ]]; then
    mv "${TF_DIR}/terraform.tfstate" "${TF_DIR}/${STATE_FILE}"
    [[ -f "${TF_DIR}/terraform.tfstate.backup" ]] && mv "${TF_DIR}/terraform.tfstate.backup" "${TF_DIR}/${STATE_FILE}.backup" 2>/dev/null || true
  fi
fi
STATE_ARG=("-state=${STATE_FILE}")
STATE_LABEL="${STATE_FILE} (aislado para ${PROJECT_ID})"

echo "=================================================================="
echo "🚀 Desplegando Data Analytics Golden Demo en GCP (Modo Modular MVP)"
echo "=================================================================="
echo "📂 Ruta del código      : ${TF_DIR}"
echo "👤 Cuenta GCP           : ${GCP_ACCOUNT_NAME}"
echo "🆔 Project ID           : ${PROJECT_ID}"
echo "🔢 Project Number       : ${PROJECT_NUMBER}"
echo "🎼 Cloud Composer       : ${ENABLE_COMPOSER}"
echo "📓 Colab Runtime VM     : ${ENABLE_COLAB_RUNTIME}"
echo "💾 Estado Terraform     : ${STATE_LABEL}"
echo "=================================================================="

terraform -chdir="${TF_DIR}" init

# 4.1 Garantizar que la Service Account exista en GCP con permisos de impersonación activos
SA_EMAIL="${PROJECT_ID}@${PROJECT_ID}.iam.gserviceaccount.com"
SA_RESOURCE_ID="projects/${PROJECT_ID}/serviceAccounts/${SA_EMAIL}"

echo "👤 Verificando Service Account de despliegue en Google Cloud (${SA_EMAIL})..."
if ! gcloud iam service-accounts describe "${SA_EMAIL}" --project="${PROJECT_ID}" --account="${GCP_ACCOUNT_NAME}" &>/dev/null; then
  echo "⚠️  La Service Account no existe en GCP (fue eliminada o aún no se ha creado)."
  echo "🛠️  Creándola ahora mismo en Google Cloud para habilitar la impersonación de Terraform..."
  gcloud iam service-accounts create "${PROJECT_ID}" \
    --display-name="Terraform Service Account" \
    --project="${PROJECT_ID}" \
    --account="${GCP_ACCOUNT_NAME}" 2>/dev/null || true

  echo "🛡️  Asignando rol de Owner en el proyecto a la Service Account..."
  gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
    --member="serviceAccount:${SA_EMAIL}" \
    --role="roles/owner" \
    --account="${GCP_ACCOUNT_NAME}" 2>/dev/null || true

  echo "🔑 Concediendo permiso Token Creator a '${GCP_ACCOUNT_NAME}' sobre la Service Account..."
  gcloud iam service-accounts add-iam-policy-binding "${SA_EMAIL}" \
    --member="user:${GCP_ACCOUNT_NAME}" \
    --role="roles/iam.serviceAccountTokenCreator" \
    --project="${PROJECT_ID}" \
    --account="${GCP_ACCOUNT_NAME}" 2>/dev/null || true

  # Esperar 10 segundos para que IAM propague el nuevo token y permisos
  sleep 10
fi

# Si no está en el estado de Terraform, la importamos para evitar conflicto 409
if ! terraform -chdir="${TF_DIR}" state list "${STATE_ARG[@]}" 2>/dev/null | grep -q "module.service-account.google_service_account.service_account"; then
  echo "📥 Sincronizando Service Account al estado de Terraform..."
  terraform -chdir="${TF_DIR}" import \
    "${STATE_ARG[@]}" \
    -var="gcp_account_name=${GCP_ACCOUNT_NAME}" \
    -var="project_id=${PROJECT_ID}" \
    -var="project_number=${PROJECT_NUMBER}" \
    -var="enable_composer=${ENABLE_COMPOSER}" \
    -var="enable_colab_runtime=${ENABLE_COLAB_RUNTIME}" \
    module.service-account.google_service_account.service_account \
    "${SA_RESOURCE_ID}" 2>/dev/null || true
fi

# 4.2 Ejecución de Terraform Apply con recuperación automática ante 404/409
set +e
terraform -chdir="${TF_DIR}" apply -auto-approve \
  "${STATE_ARG[@]}" \
  -var="gcp_account_name=${GCP_ACCOUNT_NAME}" \
  -var="project_id=${PROJECT_ID}" \
  -var="project_number=${PROJECT_NUMBER}" \
  -var="enable_composer=${ENABLE_COMPOSER}" \
  -var="enable_colab_runtime=${ENABLE_COLAB_RUNTIME}" 2>&1 | tee "${TF_DIR}/terraform_apply.log"
TF_EXIT_CODE="${PIPESTATUS[0]}"
set -e

if [[ "${TF_EXIT_CODE}" -ne 0 ]]; then
  if grep -qi "Account deleted" "${TF_DIR}/terraform_apply.log"; then
    echo ""
    echo "🔄 Detectado 'Account deleted': Recreando cuenta de servicio en GCP y refrescando permisos..."
    gcloud iam service-accounts create "${PROJECT_ID}" \
      --display-name="Terraform Service Account" \
      --project="${PROJECT_ID}" \
      --account="${GCP_ACCOUNT_NAME}" 2>/dev/null || true

    gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
      --member="serviceAccount:${SA_EMAIL}" \
      --role="roles/owner" \
      --account="${GCP_ACCOUNT_NAME}" 2>/dev/null || true

    gcloud iam service-accounts add-iam-policy-binding "${SA_EMAIL}" \
      --member="user:${GCP_ACCOUNT_NAME}" \
      --role="roles/iam.serviceAccountTokenCreator" \
      --project="${PROJECT_ID}" \
      --account="${GCP_ACCOUNT_NAME}" 2>/dev/null || true

    sleep 10

    echo "🚀 Reanudando despliegue de recursos..."
    terraform -chdir="${TF_DIR}" apply -auto-approve \
      "${STATE_ARG[@]}" \
      -var="gcp_account_name=${GCP_ACCOUNT_NAME}" \
      -var="project_id=${PROJECT_ID}" \
      -var="project_number=${PROJECT_NUMBER}" \
      -var="enable_composer=${ENABLE_COMPOSER}" \
      -var="enable_colab_runtime=${ENABLE_COLAB_RUNTIME}"
  elif grep -qi "already exists" "${TF_DIR}/terraform_apply.log" && grep -qi "service account" "${TF_DIR}/terraform_apply.log"; then
    echo ""
    echo "🔄 Detectado conflicto 409: La Service Account ya existía en GCP."
    echo "📥 Importándola al estado de Terraform..."
    terraform -chdir="${TF_DIR}" import \
      "${STATE_ARG[@]}" \
      -var="gcp_account_name=${GCP_ACCOUNT_NAME}" \
      -var="project_id=${PROJECT_ID}" \
      -var="project_number=${PROJECT_NUMBER}" \
      -var="enable_composer=${ENABLE_COMPOSER}" \
      -var="enable_colab_runtime=${ENABLE_COLAB_RUNTIME}" \
      module.service-account.google_service_account.service_account \
      "${SA_RESOURCE_ID}" 2>/dev/null || true

    echo "🚀 Reanudando despliegue de recursos..."
    terraform -chdir="${TF_DIR}" apply -auto-approve \
      "${STATE_ARG[@]}" \
      -var="gcp_account_name=${GCP_ACCOUNT_NAME}" \
      -var="project_id=${PROJECT_ID}" \
      -var="project_number=${PROJECT_NUMBER}" \
      -var="enable_composer=${ENABLE_COMPOSER}" \
      -var="enable_colab_runtime=${ENABLE_COLAB_RUNTIME}"
  elif grep -qi "demo-rest-api-service" "${TF_DIR}/terraform_apply.log" && grep -qi "already exists" "${TF_DIR}/terraform_apply.log"; then
    echo ""
    echo "🔄 Detectado conflicto 409 en Cloud Run / Cloud Functions ('demo-rest-api-service')."
    echo "🧹 Eliminando Cloud Function y Cloud Run huérfanos en us-central1..."
    gcloud functions delete demo-rest-api-service --region=us-central1 --project="${PROJECT_ID}" --account="${GCP_ACCOUNT_NAME}" --quiet 2>/dev/null || true
    gcloud run services delete demo-rest-api-service --region=us-central1 --project="${PROJECT_ID}" --account="${GCP_ACCOUNT_NAME}" --quiet 2>/dev/null || true
    sleep 5

    echo "🚀 Reanudando despliegue de recursos..."
    terraform -chdir="${TF_DIR}" apply -auto-approve \
      "${STATE_ARG[@]}" \
      -var="gcp_account_name=${GCP_ACCOUNT_NAME}" \
      -var="project_id=${PROJECT_ID}" \
      -var="project_number=${PROJECT_NUMBER}" \
      -var="enable_composer=${ENABLE_COMPOSER}" \
      -var="enable_colab_runtime=${ENABLE_COLAB_RUNTIME}"
  else
    echo "❌ Error en el despliegue de Terraform. Revisa el log en ${TF_DIR}/terraform_apply.log"
    exit "${TF_EXIT_CODE}"
  fi
fi

# 5. Generar archivo de outputs y resumen post-despliegue
echo ""
echo "💾 Exportando salidas de Terraform a tf-output.json..."
terraform -chdir="${TF_DIR}" output "${STATE_ARG[@]}" -json > "${TF_DIR}/tf-output.json" 2>/dev/null || true

echo "=================================================================="
echo "✅ ¡DESPLIEGUE MVP COMPLETADO CON ÉXITO!"
echo "=================================================================="
echo "🔗 Enlaces directos a tu consola de Google Cloud:"
echo "   📊 BigQuery Studio : https://console.cloud.google.com/bigquery?project=${PROJECT_ID}"
echo "   📓 Colab Enterprise: https://console.cloud.google.com/colab?project=${PROJECT_ID}"
echo "   🔄 Dataform ELT    : https://console.cloud.google.com/bigquery/dataform?project=${PROJECT_ID}"
echo "   🗄️  Cloud Storage   : https://console.cloud.google.com/storage/browser?project=${PROJECT_ID}"
echo "------------------------------------------------------------------"
echo "💡 Siguientes pasos recomendados:"
echo "   - Para habilitar Cloud Composer más adelante:"
echo "     ./deploy-mvp.sh --with-composer"
echo "   - Para eliminar todos los recursos cuando termines:"
echo "     ./undeploy-mvp.sh"
echo "=================================================================="
