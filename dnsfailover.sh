#!/bin/sh

# Openwrt DNSmasq DNS upstream resolver checker
# Created to solve priority issue since openwrt does not support priority DNS forward resolvers
# Primary DNS server not expected to run all the time, need fallback to good and trusted provider

# WARN
# Do not add more than 1 upstream resolvers ie more than 1 "list server 'x.x.x.x' lines", or this script will create strange behaviors and would defeat the scripts purpose of piping every query to Pihole+Unbound Server


# SETUP
# Change CONF and uncomment DNSMASQ RELOAD on deployment
# cron at every minute, out of box openwrt does not support second granuality, sad

# TODO
# ADD Logger, log to /tmp
# Loop through multiple hosts and test for atleast 3 successful connections, assume bad otherwise
# check if flock is needed, might not since dnsmasq needs to reload 
# add persistent state like last good config (backup of dhcp), cooldown, [add more]

PRIMARY='192.168.0.153'
ALT='1.1.1.1'

# STATEFILE=/root/dnsstate
STATEFILE=dnsstate


# CONF=/etc/config/dhcp
CONF=dhcp

QUERYTEST=5 # use odd number
TIMEOUT=1
RETRY=3

QUERYHOST="google.com"
QUERYHOSTS="google.com microsoft.com cloudflare.com"

DNSSERVER="192.168.0.153"

LOOKUPARGS="-timeout=$TIMEOUT -retry=$RETRY"

lookup_state()
{
    if [[ "$2"=="d" ]];then
    fi
    echo $(sed -E "s/($1=)//g")
}

validate_statefile()
{   
    # return 1 if any errors detected or alt replace the statefile with default
    # Check if file exists
    # Check Number of Lines
    # Check for errors in lines
    # -- Check value for error -- dropped

    line_count=3

    # File exist
    [ ! -f $STATEFILE ] && return 1

    # Line check
    [ $(cat $STATEFILE | wc -l) -eq $line_count ] || return 1

    # Syntax check
    [ $(grep $STATEFILE -E -e "^FAIL_COUNT=[0-9]{1}"|wc -l) -eq 1 ] || return 1
    [ $(grep $STATEFILE -E -e "^SUCCESS_COUNT=[0-9]{1}"|wc -l) -eq 1 ] || return 1
    [ $(grep $STATEFILE -E -e "^LAST_RUN=[0-9]+"|wc -l) -eq 1 ] || return 1

    return 0

}

set_default_statefile()
{

}

load_statefile()
{
    source $STATEFILE
}

set_conf()
{
    mode="$1"
    sed -Ei "s/(list server ')[0-9]{1,3}.[0-9]{1,3}.[0-9]{1,3}.[0-9]{1,3}(')/\1$mode\2/g" $CONF
}

get_active_dns()
{
    echo $(grep $CONF -e "list server" | sed -E "s/list server '([0-9]{1,3}.[0-9]{1,3}.[0-9]{1,3}.[0-9]{1,3})'/\1/g")
}

test_query()
{
    local DNS=$1
    echo $DNS
    if nslookup $LOOKUPARGS $QUERYHOST $DNS > /dev/null 2>&1; then
        return 0
    fi
    return 1

    for hosts in $QUERYHOSTS; do

}

get_success_count()
{
    local DNS=$(grep $CONF -e "list server" | sed -E "s/list server '([0-9]{1,3}.[0-9]{1,3}.[0-9]{1,3}.[0-9]{1,3})'/\1/g")

}

inc_success()
{   
sed -Ei "s/(list server ')[0-9]{1,3}.[0-9]{1,3}.[0-9]{1,3}.[0-9]{1,3}(')/\1$mode\2/g" $CONF
}

reset_success()
{

}


if test_query "$DNSSERVER"; then
    DNSUP=1
else
    DNSUP=0
fi

# Look and Verify
DNS=$(get_active_dns) # Trust that the output is always a valid IP

if [ $DNSUP -eq 1 ] && [ $DNS = $PRIMARY ]; then
    status=0
elif [ $DNSUP -eq 1 ] && [ $DNS = $ALT ]; then
    set_conf "$PRIMARY"
    status=0
elif [ $DNSUP -eq 0 ] && [ $DNS = $PRIMARY ]; then
    set_conf "$ALT"
    status=0
elif [ $DNSUP -eq 0 ] && [ $DNS = $ALT ]; then
    status=0
elif [ $DNSUP -eq 1 ] && [ -n "$DNS" ]; then
    set_conf "$PRIMARY"
    status=0
elif [ $DNSUP -eq 0 ] && [ -n "$DNS" ]; then
    # Check if valid DNS, came from the browser agent
    if test_query "$DNS";then
        set_conf "$DNS" # Try provided DNS by browser agent
        status=0
    else    
        set_conf "$ALT" # If bad dns server provided, use alt
        status=0
    fi
    # exit out of branch to a bad exit
    status=1 # bad exit
fi

if [ $status -eq 0 ];then
    # service dnsmasq reload
    exit 0
fi

exit 1


