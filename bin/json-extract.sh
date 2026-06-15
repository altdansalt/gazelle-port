#!/usr/bin/env bash
# json-extract.sh — pull the first complete JSON object out of possibly-fenced LLM output.
# Reads stdin, writes the JSON object to stdout. Tolerates ```json fences and prose.
set -euo pipefail
in="$(cat)"
# strip code fences if present
in="${in//\`\`\`json/}"; in="${in//\`\`\`/}"
# from first { to last } (LLM is instructed to emit a single object)
printf '%s' "$in" | awk '
  BEGIN{d=0; started=0}
  { for(i=1;i<=length($0);i++){c=substr($0,i,1);
      if(c=="{"){d++; started=1}
      if(started) buf=buf c
      if(c=="}"){d--; if(d==0 && started){print buf; exit}}
    }
    if(started) buf=buf "\n"
  }'
