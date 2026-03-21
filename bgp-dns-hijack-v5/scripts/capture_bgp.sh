#!/bin/bash
echo "Capturing BGP packets on R2 (Transit)..."
echo "Press Ctrl+C to stop capture"
docker exec clab-bgp-dns-hijack-r2 tcpdump -i any -w /tmp/bgp_capture.pcap port 179 &
TCPDUMP_PID=$!
echo "Capture PID: $TCPDUMP_PID"
echo "Run attack in another terminal, then stop with: kill $TCPDUMP_PID"
echo "Copy pcap: docker cp clab-bgp-dns-hijack-r2:/tmp/bgp_capture.pcap ."
wait $TCPDUMP_PID
