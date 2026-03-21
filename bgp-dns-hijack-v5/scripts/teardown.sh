#!/bin/bash
echo "Destroying lab..."
cd "$(dirname "$0")/.."
sudo containerlab destroy -t topology.yaml --cleanup
echo "Done."
