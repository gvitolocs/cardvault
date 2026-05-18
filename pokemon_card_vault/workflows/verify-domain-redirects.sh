#!/usr/bin/env bash
set -euo pipefail

protected_routes=(wallet auth profile checkout orders)
hosts=(
  explorer.pokoin.com
  wallet.pokoin.com
  forum.pokoin.com
  cards.pokoin.com
  cardcaveau.pokoin.com
  www.pokoin.com
)

for host in "${hosts[@]}"; do
  for route in "${protected_routes[@]}"; do
    url="https://${host}/${route}"
    line="$(/usr/bin/curl -I -s "$url" | /usr/bin/awk 'BEGIN{status="";loc=""} /^HTTP\//{status=$2} tolower($1)=="location:"{loc=$2} END{gsub("\r","",loc); print status, loc}')"
    echo "${url} -> ${line}"
  done
done

echo "roots"
for url in \
  https://explorer.pokoin.com/ \
  https://forum.pokoin.com/ \
  https://cards.pokoin.com/ \
  https://cardcaveau.pokoin.com/ \
  https://www.pokoin.com/; do
  line="$(/usr/bin/curl -I -s "$url" | /usr/bin/awk 'BEGIN{status="";loc=""} /^HTTP\//{status=$2} tolower($1)=="location:"{loc=$2} END{gsub("\r","",loc); print status, loc}')"
  echo "${url} -> ${line}"
done
