#!/usr/bin/env bash
# Deploys the BUILT (comment-free) rules — never the commented source — so the
# release stays well under the service's size limit (docs/production-audit SEC-1).
#
#   tool/deploy_rules.sh <firebase-project-id> [--dry-run]
#
# Always run with --dry-run first. Deploy to staging/dev before production.
set -euo pipefail
cd "$(dirname "$0")/.."
project="${1:?usage: tool/deploy_rules.sh <project-id> [--dry-run]}"
shift || true
node tool/build_rules.js --check
exec firebase deploy --only firestore:rules,storage --config firebase.rules.json --project "$project" "$@"
