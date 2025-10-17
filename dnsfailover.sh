#!/bin/ash

# Openwrt DNSmasq DNS upstream resolver checker
# Created to solve priority issue since openwrt does not support priority DNS forward resolvers
# Primary DNS server not expected to run all the time, need fallback to good and trusted provider

# WARN
# Do not add more than 1 upstream resolvers ie more than 1 "list server 'x.x.x.x' lines", or this script will create unintended behaviors and would defeat the scripts purpose of piping every query to a Pihole+Unbound or local dns Server

# SETUP
# Change CONF to point to dhcp and uncomment DNSMASQ RELOAD on reload_dnsmasq func for deployment
# cron at every 5 minutes

# TODO
# add cli arg for testing so that users dont have to manually edit the script
# cli arg timeout and retry
# add setup script or cli arg function to add states to openwrt and a test dhcp file
# add error checking
# add internet down detector
#       - if all alt dns down, infer that the internet is down


PRIMARY='192.168.0.153'
ALT='1.1.1.1'

STATE="script_persist.dns_state"

CONF="dhcp.@dnsmasq[0]"
# CONF="test.@dnsmasq[0]" # use the CONF above for deployment

HOSTS="google.com cloudflare.com microsoft.com akamai.com fastly.com"

TIMEOUT=1
RETRY=3

QUERY_THRESHOLD=3

QUERY_ARGS="+timeout=$TIMEOUT +retry=$RETRY"

FAIL_THRESHOLD=3
SUCCESS_THRESHOLD=3

COOLDOWN=300 # Seconds after change 

DNS_CHECK_RETRIES=5
LOOP_INTERVAL_SECS=10 # Loop interval

log() 
{
    logger -t DNSCHECK "$1"
}

set_primary()
{
    # Old implemetation uses 'uci set' and would keep the network down
    uci -q delete "$CONF.server"
    uci add_list "$CONF.server=$PRIMARY"
    uci commit "$CONF"
    log "Loaded Primary DNS Server: $PRIMARY"
}

set_alt()
{
    uci -q delete "$CONF.server"
    uci add_list "$CONF.server=$ALT"
    uci commit "$CONF"
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

reset_counters()
{
    reset_fail
    reset_success
}

query()
{
    local host=$1
    local dns=$2
    local output
    local status
    output=$(dig $host "@$dns" A $QUERY_ARGS +short)
    status=$?
    output=$(echo $output | wc -l)
    if [[ "$output" -gt 0 ]] && [[ "$status" -eq 0 ]]; then
        return 0
    fi
    return 1
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
            # log "Reached $host with $dns"
            success_count=$(($success_count + 1))
        else
            log "Cannot reach $host with $dns"
        fi
    done

    if [ "$success_count" -ge "$QUERY_THRESHOLD" ]; then 
        log "Probe OK"
        return 0
    fi
    log "Probe BAD"
    return 1
}

restart_dnsmasq()
{
    service dnsmasq reload
    # echo "Test Reload"
}

log "Currently using $(get_active_dns)"

last_change=$(get_cooldown)
now=$(date +%s)

diff=$(($now-$last_change))

# Exit if cooldown still in effect
if [ "$diff" -le "$COOLDOWN" ]; then
    log "It has been $diff seconds since last change"
    exit 0
fi

for i in $(seq 1 $DNS_CHECK_RETRIES)
do
    log "Starting Probe $i of set $DNS_CHECK_RETRIES..."
    # Probe known hosts
    probe

    status=$?

    if [ "$status" -eq 0 ]; then
        inc_success
        reset_fail
    else
        inc_fail
        reset_success
    fi

    # [ $(get_success_count) -gt 1 ] && log "DNS SERVER OK" || log "DNS SERVER BAD"

    # If Upstream set to Primary 
    if [ $(get_active_dns) = "$PRIMARY" ]; then
        if [ $(get_fail_count) -ge "$FAIL_THRESHOLD" ]; then
            set_alt
            # log "Upstream set to $ALT"
            reset_counters
            set_cooldown
            restart_dnsmasq
        fi
    else
        if [ $(get_success_count) -ge "$SUCCESS_THRESHOLD" ]; then
            set_primary
            # log "Upstream set to $PRIMARY"
            reset_counters
            set_cooldown
            restart_dnsmasq
        fi
    fi

    [ "$i" -eq $DNS_CHECK_RETRIES ] || sleep $LOOP_INTERVAL_SECS
done


uci commit $STATE # Save State persistance

[ $(get_success_count) -gt 1 ] && log "DNS Server Up"

elapsed_time=$(($(date +%s) - $now))

log "Probe took $elapsed_time seconds"

exit 0




