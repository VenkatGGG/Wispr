#!/usr/bin/env bash
set -euo pipefail

IDENTITY_NAME="${WISPR_CODESIGN_IDENTITY:-Wispr Local Development}"
KEYCHAIN_NAME="${WISPR_CODESIGN_KEYCHAIN_NAME:-WisprLocalDevelopment.keychain-db}"
KEYCHAIN_PATH="${WISPR_CODESIGN_KEYCHAIN_PATH:-${HOME}/Library/Keychains/${KEYCHAIN_NAME}}"
KEYCHAIN_PASSWORD="${WISPR_CODESIGN_KEYCHAIN_PASSWORD:-wisprlocal}"

ensure_keychain() {
  if [[ ! -f "${KEYCHAIN_PATH}" ]]; then
    security create-keychain -p "${KEYCHAIN_PASSWORD}" "${KEYCHAIN_PATH}" >/dev/null
  fi

  security unlock-keychain -p "${KEYCHAIN_PASSWORD}" "${KEYCHAIN_PATH}" >/dev/null
}

import_identity() {
  local tmpdir
  tmpdir="$(mktemp -d)"
  trap 'rm -rf "${tmpdir}"' RETURN

  cat > "${tmpdir}/openssl.cnf" <<EOF
[ req ]
distinguished_name = dn
x509_extensions = ext
prompt = no
[ dn ]
CN = ${IDENTITY_NAME}
O = Local Development
[ ext ]
basicConstraints = critical,CA:FALSE
keyUsage = critical,digitalSignature
extendedKeyUsage = codeSigning
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid,issuer
EOF

  openssl req \
    -newkey rsa:2048 \
    -nodes \
    -keyout "${tmpdir}/key.pem" \
    -x509 \
    -days 3650 \
    -out "${tmpdir}/cert.pem" \
    -config "${tmpdir}/openssl.cnf" \
    >/dev/null 2>&1

  openssl pkcs12 \
    -export \
    -legacy \
    -out "${tmpdir}/identity.p12" \
    -inkey "${tmpdir}/key.pem" \
    -in "${tmpdir}/cert.pem" \
    -passout "pass:${KEYCHAIN_PASSWORD}" \
    >/dev/null 2>&1

  security import "${tmpdir}/identity.p12" \
    -k "${KEYCHAIN_PATH}" \
    -P "${KEYCHAIN_PASSWORD}" \
    -A \
    -T /usr/bin/codesign \
    -T /usr/bin/security \
    >/dev/null
}

ensure_partition_list() {
  security set-key-partition-list \
    -S apple-tool:,apple: \
    -s \
    -k "${KEYCHAIN_PASSWORD}" \
    "${KEYCHAIN_PATH}" \
    >/dev/null
}

resolve_identity_hash() {
  security find-identity -v -p codesigning "${KEYCHAIN_PATH}" \
    | awk -v name="${IDENTITY_NAME}" '$0 ~ "\"" name "\"" { print $2; exit }'
}

ensure_keychain

IDENTITY_HASH="$(resolve_identity_hash || true)"
if [[ -z "${IDENTITY_HASH}" ]]; then
  import_identity
  ensure_partition_list
  IDENTITY_HASH="$(resolve_identity_hash || true)"
else
  ensure_partition_list
fi

if [[ -z "${IDENTITY_HASH}" ]]; then
  echo "Failed to create or locate code signing identity: ${IDENTITY_NAME}" >&2
  exit 1
fi

echo "Using code signing identity ${IDENTITY_NAME} (${IDENTITY_HASH}) in ${KEYCHAIN_PATH}"
