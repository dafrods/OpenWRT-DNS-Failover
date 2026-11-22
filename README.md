## DESCRIPTION
Script for a DNS Failover in case your main DNS server dies or is unresponsive.

OpenWRT does not natively support a failover on the event where your main server dies. 

If you setup a system with two DNS, it will use the other too, in which case would bypass your server at times.

Typical Setup for this script is to have a One single DNS server allocated over your network and if that fails, will switch to any server you wish to use as an alternative.

Assumes all of your devices in your network uses the router as its DNS and the router upstreams it to your Main DNS or an alternative incase it fails.

## Requirements

Written for `OpenWrt 23.05.5`
