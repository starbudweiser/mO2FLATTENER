#!/bin/bash
# Compile la version Swift (macos/build_app.sh) : mO2FLATTENER.app à la racine du projet.
exec "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/macos/build_app.sh" "$@"
