#!/bin/bash
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
#
# Copyright 2012-2014 Daniel Ehlers
#


# List of gateways to test
#                      VPN4         VPN0         VPN2
DEFAULT_GATEWAYS=${1:-"10.116.136.1 10.116.152.1 10.116.160.1 10.116.168.1"}
# Interface which should be used for pinging a remote host
#INTERFACE=br-freifunk
INTERFACE=wlan0
# routing table which should be used to setup rules
ROUTING_TABLE=100
# the number which should be used for marking packets
FWMARK=100
# the host we like to ping, ip addr
TARGET_HOST=8.8.8.8
# the dns record we like to receive
TARGET_DNS_RECORD=www.toppoint.de
TARGET_DNS_FFKI_RECORD=vpn0.ffki

# Check if rp_filter is activated
if test `cat /proc/sys/net/ipv4/conf/$INTERFACE/rp_filter` -ne 0; then
  echo ERROR: Please deactivate rp_filter on device $INTERFACE.
  echo sysctl -w net.ipv4.conf.$INTERFACE.rp_filter=0
  exit 2
fi

clean_up() {
  ip route flush table ${ROUTING_TABLE}
  ip rule del fwmark ${FWMARK} table ${ROUTING_TABLE}
  exit
}

# Be sure we clean up
trap clean_up SIGINT

ip rule add fwmark ${FWMARK} table ${ROUTING_TABLE}

GATEWAY_SOA=()

for gw in $DEFAULT_GATEWAYS; do
  # clean routing table
  ip route flush table ${ROUTING_TABLE}
  # setup routing table
  ip route add 0.0.0.0/1 via $gw table ${ROUTING_TABLE}
  ip route add 128.0.0.0/1 via $gw table ${ROUTING_TABLE}
  ip route replace unreachable default table ${ROUTING_TABLE}

  echo -n "Testing $gw ."

  #### Gateway reachability
  if  ping -c 2 -i 1 -W 2 -q $gw > /dev/null 2>&1; then
    echo -n "."
  else
    echo " Failed - Gateway unreachable"
    continue
  fi

  #### Gateway functionality ping
  if ping -m 100 -I ${INTERFACE} -c 2  -i 1 -W 2 -q $TARGET_HOST > /dev/null 2>&1; then
    echo -n "."
  else
    echo " ping throught the gateway FAILED"
    continue
  fi

  #### DHCP test
  if dhcping -q -i -s "$gw"; then
    echo -n "."
  else
    echo " dhcp request test FAILED"
    continue
  fi

  #### Nameserver test
  if nslookup ${TARGET_DNS_RECORD} ${gw} > /dev/null 2>&1 ; then
    echo -n "."
  else
    echo " cannot resolve domain via gateway FAILED"
    continue
  fi

  #### Nameserver test (own domain)
  if nslookup ${TARGET_DNS_FFKI_RECORD} ${gw} > /dev/null 2>&1 ; then
    echo -n "."
  else
    echo " cannot resolve ffki domain via gateway FAILED"
    continue
  fi

  #### Nameserver SOA Record
  GATEWAY_SOA+=($(dig "@${gw}" ffki SOA))
  echo -n "."

  echo " Success"
done

#### Compare SOA records
IFS=$'\n'
UNIQ_SOA=$(echo -n "${GATEWAY_SOA[*]}" | sort | uniq)
if [ ${#UNIQ_SOA[@]} -gt 1 ] ; then
  echo "WARN: none unique SOA record"
fi

clean_up
