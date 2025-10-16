#!/bin/sh

# check dns state
#     if up
#         check activeconfig
#         if not primary
#             change
#         else
#             exit
#         exit
#     else 
#         check activeconfig
#         if not primary
#             change
#         else
#             exit

set_conf()
{
    mode="$1"
    sed -E -i "s/(list server ')([0-9]{1,3}.[0-9]{1,3}.[0-9]{1,3}.[0-9]{1,3})(')/\1$mode\3/g" $CONF
}

get_active_dns()
{
    local DNS=$(grep $CONF -e "list server" | sed -E "s/(list server ')([0-9]{1,3}.[0-9]{1,3}.[0-9]{1,3}.[0-9]{1,3})(')/\2/g")
    echo $DNS
}

PRIMARY='192.168.0.153'
ALT='1.1.1.1'

CONF=dhcp

QUERYHOST="google.com"
DNSSERVER="192.168.0.153"

TIMEOUT=1
RETRY=1
LOOKUPARGS="-timeout=$TIMEOUT -retry=$RETRY"

if nslookup $LOOKUPARGS $QUERYHOST $DNSSERVER > /dev/null 2>&1; then
    DNSUP=1
else
    DNSUP=0
fi

# Look and Verify
DNS=$(get_active_dns) # Trust that the output is always a valid IP

if [ $DNSUP -eq 1 ] && [ $DNS = $PRIMARY ]; then
    echo "Good"
    exit

elif [ $DNSUP -eq 1 ] && [ $DNS = $ALT ]; then
    set_conf "$PRIMARY"

elif [ $DNSUP -eq 0 ] && [ $DNS = $PRIMARY ]; then
    set_conf "$ALT"

elif [ $DNSUP -eq 0 ] && [ $DNS = $ALT ]; then
    exit

elif [ $DNSUP -eq 1 ] && [ -n $DNS ]; then
    set_conf "$PRIMARY"

elif [ $DNSUP -eq 0 ] && [ -n $DNS ]; then
    set_conf "$DNS"

fi

exit


