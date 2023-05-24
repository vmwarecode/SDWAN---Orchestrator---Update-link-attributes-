#!/usr/bin/env bash
#
# update-links.sh
#
# Update select link metadata properties based on current Maxmind data, including:
#  - lat
#  - lon
#  - isp
#  - displayName
#
# NOTE: This script expects that the following environment variables are set:
#  - MAXMIND_LICENSE_KEY: Maxmind license key
#  - VCO_API_TOKEN: API token downloaded by a user with the necessary privileges to update links
#
set -Euo pipefail
trap cleanup SIGINT SIGTERM ERR EXIT
MAXMIND_GEOIP_API_URL='https://geoip.maxmind.com/f'
usage() {
  cat <<EOF
Usage: $(basename "${BASH_SOURCE[0]}") [-h] [-v] vco_hostname [link_id...]
Update select link metadata properties based on current Maxmind data, including:
 - lat
 - lon
 - isp
 - displayName
Available options:
-h, --help      Print this help and exit
-v, --verbose   Print script debug info
NOTE: This script expects that the following environment variables are set:
 - MAXMIND_LICENSE_KEY: Maxmind license key
 - VCO_API_TOKEN: API token downloaded by a user with the necessary privileges to update links
EOF
  exit
}
cleanup() {
  trap - SIGINT SIGTERM ERR EXIT
}
setup_colors() {
  if [[ -t 2 ]] && [[ -z "${NO_COLOR-}" ]] && [[ "${TERM-}" != "dumb" ]]; then
    NOFORMAT='\033[0m' RED='\033[0;31m' GREEN='\033[0;32m' ORANGE='\033[0;33m' BLUE='\033[0;34m' PURPLE='\033[0;35m' CYAN='\033[0;36m' YELLOW='\033[1;33m'
  else
    NOFORMAT='' RED='' GREEN='' ORANGE='' BLUE='' PURPLE='' CYAN='' YELLOW=''
  fi
}
msg() {
  echo >&2 -e "${1-}"
}
die() {
  local msg=$1
  local code=${2-1} # default exit status 1
  msg "$msg"
  exit "$code"
}
parse_params() {
  while :; do
    case "${1-}" in
    -h | --help) usage ;;
    -v | --verbose) set -x ;;
    --no-color) NO_COLOR=1 ;;
    -?*) die "Unknown option: $1" ;;
    *) break ;;
    esac
    shift
  done
  args=("$@")
  # check required params and arguments
  [[ ${#args[@]} -lt 2 ]] && usage
  return 0
}
join_by() {
  local d=$1
  shift
  local f=$1
  shift
  printf %s "$f" "${@/#/$d}";
}
parse_params "$@"
setup_colors
# Call
grep_filter=$(join_by '\|' "${args[@]:1}")
links=$(curl -ks -H "Authorization: Token ${VCO_API_TOKEN}" -X POST "https://${args[0]}/portal/rest/monitoring/getEnterpriseEdgeLinkStatus" | jq '.[] | (.linkId|tostring) + " " + (.enterpriseId|tostring) + " " + .linkIpAddress' | sed -e 's/^"\(.*\)"$/\1/' | grep -e "^\(${grep_filter}\)")
while IFS=' ' read -r link_id enterprise_id link_ip; do
  echo "Getting current link information for link [${link_id}/${link_ip}]"
  IFS=, read country state city zip lat lon a b isp org < <(curl -ks -X GET "${MAXMIND_GEOIP_API_URL}?l=${MAXMIND_LICENSE_KEY}&i=${link_ip}")
  echo "- lat=${lat} lon=${lon} isp=${isp} org=${org}"
  echo "Updating..."
  curl -ks -H "Authorization: Token ${VCO_API_TOKEN}" "https://${args[0]}/portal/rest/link/updateLinkAttributes" -d "{\"enterpriseId\":${enterprise_id},\"linkId\":${link_id},\"_update\":{\"lat\":${lat},\"lon\":${lon},\"isp\":\"$(echo "${isp}" | sed -e 's/^"\(.*\)"$/\1/')\",\"displayName\":\"$(echo "${isp}" | sed -e 's/^"\(.*\)"$/\1/')\"}}" 1>/dev/null 2>&1 && echo "- Success!"
done <<< "$links"
