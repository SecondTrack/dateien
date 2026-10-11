#!/bin/sh
# Erzeugt src/FMWeb.h aus web/ (eingebettete Browser-Oberfläche). Läuft automatisch vor jedem make.
set -e
cd "$(dirname "$0")/.."
out=src/FMWeb.h
{
  echo "// FMWeb.h — AUTOMATISCH aus web/index.html + web/app.js erzeugt (tools/mkweb.sh). Nicht von Hand bearbeiten."
  echo "#pragma once"
  for f in index.html app.js; do
    (cd web && xxd -i "$f") | sed -e 's/^unsigned char/static const unsigned char/' -e 's/^unsigned int/static const unsigned int/'
  done
} > "$out.tmp"
mv "$out.tmp" "$out"
