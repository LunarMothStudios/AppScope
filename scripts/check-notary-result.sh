#!/bin/bash
# Fail closed: notarytool can finish a submission whose status is Invalid.
set -euo pipefail
if [[ $# -ne 1 ]]; then printf 'Usage: %s NOTARY_RESULT_JSON\n' "$0" >&2; exit 1; fi
if ! notary_status="$(/usr/bin/plutil -extract status raw -o - "$1" 2>/dev/null)"; then
  printf 'Cannot verify notarization status. No release archive was produced.\n' >&2; exit 1
fi
if [[ "$notary_status" != "Accepted" ]]; then
  printf 'Notarization was not Accepted. Inspect the submission with notarytool before publishing.\n' >&2; exit 1
fi
printf 'Notarization Accepted.\n'
