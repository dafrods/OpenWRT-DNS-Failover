#!/bin/ash

# Openwrt DNSmasq DNS upstream resolver checker
# Created to solve priority issue since openwrt does not support priority DNS forward resolvers
# Primary DNS server not expected to run all the time, need fallback to good and trusted provider

# WARN
# Do not add more than 1 upstream resolvers ie more than 1 "list server 'x.x.x.x' lines", or this script will create strange behaviors and would defeat the scripts purpose of piping every query to Pihole+Unbound Server

# SETUP
# Change CONF to point to dhcp and uncomment DNSMASQ RELOAD on deployment
# cron at every minute

# TODO
# check if flock is needed, might not since dnsmasq needs to reload
#   - no, flock not needed, luci does not use flock

PRIMARY='192.168.0.153'
ALT='1.1.1.1'

STATE="script_persist.dns_state"

# CONF="dhcp.@dnsmasq[0]"
CONF="test.@dnsmasq[0]"

HOSTS="google.com cloudflare.com microsoft.com akamai.com fastly.com"

TIMEOUT=1
RETRY=3

QUERY_THRESHOLD=3

QUERY_ARGS="+timeout=$TIMEOUT +retry=$RETRY"

FAIL_THRESHOLD=3
SUCCESS_THRESHOLD=3

COOLDOWN=300 # Seconds after change 

log()
{
    logger -t DNSCHECK "$1"
}

set_primary()
{
    uci set "$CONF.server=$PRIMARY"
    log "Loaded Primary DNS Server: $PRIMARY"
}

set_alt()
{
    uci set "$CONF.server=$ALT"
    log "Loaded Alternative DNS Server: $ALT"
}

get_active_dns()
{
    echo $(uci get "$CONF.server")
}

get_success_count()
{
    echo $(uci get "$STATE.success")
}

inc_success()
{   
    local count=$(get_success_count)
    count=$(($count+1))
    uci set "$STATE.success=$count"
}

reset_success()
{
    uci set "$STATE.success=0"
}

get_fail_count()
{
    echo $(uci get "$STATE.fail")
}

inc_fail()
{   
    local count=$(get_fail_count)
    count=$(($count+1))
    uci set "$STATE.fail=$count"
}

reset_fail()
{
    uci set "$STATE.fail=0"
}

query()
{
    local host=$1
    local dns=$2
    local output
    output=$(dig $host "@$dns" A $QUERY_ARGS +short | wc -l)
    [ "$output" -gt 0 ]
}

set_cooldown()
{   
    local now=$(date +%s)
    uci set "$STATE.last_change=$now"
}

get_cooldown()
{
    echo $(uci get "$STATE.last_change")
}

probe()
{
    local dns="$PRIMARY"
    local success_count=0

    for host in $HOSTS
    do 
        query $host $dns
        if [ "$?" -eq 0 ]; then
            log "Reached $host with $dns"
            success_count=$(($success_count + 1))
        else
            log "Cannot reach $host with $dns"
        fi
    done

    if [ "$success_count" -ge "$QUERY_THRESHOLD" ]; then 
        return 0
    else
        return 1
    fi
    return 1
}

reload_dnsmasq()
{
    # service dnsmasq reload
    echo "Test Reload"
}

last_change=$(get_cooldown)
now=$(date +%s)



diff=$(($now-$last_change))

if [ "$diff" -le "$COOLDOWN" ]; then
    log "It has been $diff since last change"
    exit 0
fi

# Probe known host
probe

if [ "$?" -eq 0 ]; then
    inc_success
else
    inc_fail
fi

# If Upstream set to Primary 
if [ $(get_active_dns) = "$PRIMARY" ]; then
    if [ $(get_fail_count) -ge "$FAIL_THRESHOLD" ]; then
        set_alt
        log "Upstream set to $ALT"
        reset_success
        reset_fail
	set_cooldown
        reload_dnsmasq
    fi
else
    if [ $(get_success_count) -ge "$SUCCESS_THRESHOLD" ]; then
        set_primary
        log "Upstream set to $PRIMARY"
        reset_success
        reset_fail
        set_cooldown
        reload_dnsmasq
    fi
fi

exit 0




