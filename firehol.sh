#!/bin/sh
#
# Startup script to implement /etc/firehol.conf pre-defined rules.
#
# chkconfig: 2345 99 92
#
# description: Automates a packet filtering firewall with iptables.
#
# by costa@tsaousis.gr
#
# config: /etc/firehol.conf
#
# $Id: firehol.sh,v 1.24 2002/12/03 22:03:00 ktsaou Exp $
#
# $Log: firehol.sh,v $
# Revision 1.24  2002/12/03 22:03:00  ktsaou
# Another work around to fix the problem of LINENO not working in debian
# systems.
#
# Added command line argument "services" which shows all the service
# definitions firehol knows about.
#
# Revision 1.23  2002/12/02 17:48:41  ktsaou
# Fixed a bug where some versions of BASH do not handle correctly cat >>"EOF".
# They treat it as cat >>EOF and thus they do variable substitution on the
# text.
# Now, FireHOL uses cat >>EOF but the text has been escaped in order to avoid
# variable substitution.
#
# The problem has been reported by Florian Thiel <thiel@ksan.de>.
#
# Revision 1.22  2002/12/02 00:01:24  ktsaou
# Fixed parameter 'custom' processing. It is not an array now, but it is
# treated specially to support BASH special characters such as !
# Quoting things in parameters 'custom' needs tweaking still.
#
# Revision 1.21  2002/12/01 04:34:00  ktsaou
# More quoting issues fixed. Changed the core to work with BASH arrays in
# order to handle quoted arguments accurately.
#
# Fixed a bug in postprocessing error handler that did not present the
# command line that produced the error.
#
# Revision 1.20  2002/11/30 22:53:55  ktsaou
# Fixed various problems related to quoted arguments.
# Fixed iptables generation to support quoted arguments.
# Made chain names shorter.
#
# Every single element in the firehol config now gets its own chain.
# Previously, the same services (e.g. smtp servers) were implemented using
# only one pair of chains.
#
# Enhanced the error handler of logical and syntactical error. Now it says
# were and why an error has occured.
#
# Revision 1.19  2002/11/30 14:33:33  ktsaou
# As suggested by Florian Thiel <thiel@ksan.de>:
# a. Fixed service IRC to work on TCP instead of UDP.
# b. Added services: UUCP, VNC, WEBCACHE, IMAPS, IKE.
#
# Also fixed the home-router.conf example (it was outdated).
#
# Revision 1.18  2002/11/03 13:17:39  ktsaou
# Minor aesthetic changes.
#
# Revision 1.17  2002/11/01 19:37:20  ktsaou
# Added service: any
# Any allows the administrator to define any stateful rule to match services
# that cannot have source and destination ports, such as unusual protocols,
# etc.
#
# Syntax: type any name action [optional rule parameters]
#
# type: server/client/route
# name: the name for the service (used for the chain)
# action: accept, reject, etc.
#
#
# Added service: multicast
# Multicast allows the administrator to match packets with destination
# 224.0.0.0/8 in both directions (input/output).
#
# Revision 1.16  2002/10/31 15:31:52  ktsaou
# Added command line parameter 'try' (in addition to 'start', 'stop', etc)
# that when used it activates the firewall and waits 30 seconds for the
# administrator to type 'commit' in order to keep the firewall active.
# If the administrator does not write 'commit' or the timeout passes, FireHOL
# restores the previous firewall.
#
# Also, if you break (Ctrl-C) FireHOL while activating the new firewall,
# FireHOL will restore the old firewall.
#
# Revision 1.15  2002/10/30 23:25:07  ktsaou
# Rearranged default RELATED rules to match after normal processing and
# protections.
# Made the core of FireHOL operate on multiple tables (not assuming the
# rules refer to the 'filter' table). This will allow FireHOL to support
# all kinds of NAT chains in the future.
#
# Revision 1.14  2002/10/29 22:20:41  ktsaou
# Client and server keywords now work on routers too.
# (The old 'route' subcommand is an alias for the 'server' subcommand -
# within a router).
# Protection can be reversed on routers to match outface instead of inface.
# Masquerade can be used in interfaces, routers (matches outface - but can
# be reverse(ed) to match inface) or as a primary command with all the
# interfaces to be masqueraded in an argument.
#
# Revision 1.13  2002/10/28 19:47:02  ktsaou
# Protection has been extented to work on routers too.
# Made a few minor aesthetic changes on the generated code. Now in/out chains
# on routers match the inface/outface correctly.
#
# Revision 1.12  2002/10/28 18:45:54  ktsaou
# Added support for ICMP floods protection and from BAD TCP flags protection.
# This was suggested by: Fco.Felix Belmonte (ffelix@gescosoft.com).
#
# Revision 1.11  2002/10/27 12:47:48  ktsaou
# Added CVS versioning to all files.
#
#

# ------------------------------------------------------------------------------
# Copied from /etc/init.d/iptables

# On non RedHat machines we need success() and failure()
success() {
	echo " OK"
}
failure() {
	echo " FAILED"
}

# On RedHat systems this will define success() and failure()
test -f /etc/init.d/functions && . /etc/init.d/functions

if [ ! -x /sbin/iptables ]; then
	exit 0
fi

KERNELMAJ=`uname -r | sed                   -e 's,\..*,,'`
KERNELMIN=`uname -r | sed -e 's,[^\.]*\.,,' -e 's,\..*,,'`

if [ "$KERNELMAJ" -lt 2 ] ; then
	exit 0
fi
if [ "$KERNELMAJ" -eq 2 -a "$KERNELMIN" -lt 3 ] ; then
	exit 0
fi


if  /sbin/lsmod 2>/dev/null | grep -q ipchains ; then
	# Don't do both
	exit 0
fi

# --- PARAMETERS Processing ----------------------------------------------------

# The default configuration file
FIREHOL_CONFIG="/etc/firehol.conf"

# If set to 1, we are just going to present the resulting firewall instead of
# installing it.
FIREHOL_DEBUG=0

# If set to 1, the firewall will be saved for normal iptables processing.
FIREHOL_SAVE=0

# If set to 1, the firewall will be restored if you don't commit it.
FIREHOL_TRY=1

me="${0}"
arg="${1}"
shift

if [ ! -z "${arg}" -a -f "${arg}" ]
then
	FIREHOL_CONFIG="${arg}"
	arg="try"
fi

if [ ! -f "${FIREHOL_CONFIG}" ]
then
	echo -n $"FireHOL config ${FIREHOL_CONFIG} not found:"
	failure $"FireHOL config ${FIREHOL_CONFIG} not found:"
	echo
	exit 1
fi

case "${arg}" in
	try)
		FIREHOL_TRY=1
		;;
	
	start)
		FIREHOL_TRY=0
		;;
	
	restart)
		FIREHOL_TRY=0
		;;
	
	condrestart)
		FIREHOL_TRY=0
		if [ ! -e /var/lock/subsys/iptables ]
		then
			exit 0
		fi
		;;
	
	save)
		FIREHOL_TRY=0
		FIREHOL_SAVE=1
		;;
		
	debug)
		FIREHOL_TRY=0
		FIREHOL_DEBUG=1
		;;
	
	services)
		cat <<"EOF"
$Id: firehol.sh,v 1.24 2002/12/03 22:03:00 ktsaou Exp $
(C) Copyright 2002, Costa Tsaousis

FireHOL supports the following services (sorted by name):
EOF

		(
			# The simple services
			cat "${me}"				|\
				grep -e "^server_.*_ports="	|\
				cut -d '=' -f 1			|\
				sed "s/^server_//"		|\
				sed "s/_ports\$//"
			
			# The complex services
			cat "${me}"				|\
				grep -e "^rules_.*()"		|\
				cut -d '(' -f 1			|\
				sed "s/^rules_//"
		) | sort | uniq |\
		(
			x=0
			while read
			do
				x=$[x + 1]
				if [ $x -gt 4 ]
				then
					printf "\n"
					x=1
				fi
				printf "% 17s" "$REPLY"
			done
			printf "\n\n"
		)
		cat <<EOF
Please note that the service:
	
	all	matches all packets, all protocols, all of everything,
		while ensuring that required kernel modules are loaded.
	
	any	allows the matching of packets with unusual rules, like
		only protocol but no ports. If service any is used
		without other parameters, it does what service all does
		but it does not handle kernel modules.
		For example, to match GRE traffic use:
		
		server any mygre accept proto 47
		
		Service any does not handle kernel modules.
		
	custom	allows the definition of a custom service.
		The template is:
		
		server custom name protocol/sport cport accept
		
		where name is just a name, protocol is the protocol the
		service uses (tcp, udp, etc), sport is server port,
		cport is the client port. For example, IMAP4 is:
		
		server custom imap tcp/143 default accept
	
EOF
		exit 0
		;;
	
	*)
		echo >&2 "FireHOL: Calling the iptables service..."
		/etc/init.d/iptables "${arg}"
		ret=$?
		if [ $ret -gt 0 ]
		then
			echo >&2 "FireHOL: use also the 'debug' to see and 'try' to test the configuration."
		fi
		exit $ret
		;;
esac


# ------------------------------------------------------------------------------
# XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
# ------------------------------------------------------------------------------
#
# GLOBAL DEFAULTS
#
# ------------------------------------------------------------------------------
# XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
# ------------------------------------------------------------------------------

# IANA Reserved IPv4 address space
# Suggested by Fco.Felix Belmonte <ffelix@gescosoft.com>
# This has been generated by get-iana.sh
RESERVED_IPS="0.0.0.0/8 1.0.0.0/8 2.0.0.0/8 5.0.0.0/8 7.0.0.0/8 23.0.0.0/8 27.0.0.0/8 31.0.0.0/8 36.0.0.0/8 37.0.0.0/8 39.0.0.0/8 41.0.0.0/8 42.0.0.0/8 58.0.0.0/8 59.0.0.0/8 60.0.0.0/8 70.0.0.0/8 71.0.0.0/8 72.0.0.0/8 73.0.0.0/8 74.0.0.0/8 75.0.0.0/8 76.0.0.0/8 77.0.0.0/8 78.0.0.0/8 79.0.0.0/8 82.0.0.0/8 83.0.0.0/8 84.0.0.0/8 85.0.0.0/8 86.0.0.0/8 87.0.0.0/8 88.0.0.0/8 89.0.0.0/8 90.0.0.0/8 91.0.0.0/8 92.0.0.0/8 93.0.0.0/8 94.0.0.0/8 95.0.0.0/8 96.0.0.0/8 97.0.0.0/8 98.0.0.0/8 99.0.0.0/8 100.0.0.0/8 101.0.0.0/8 102.0.0.0/8 103.0.0.0/8 104.0.0.0/8 105.0.0.0/8 106.0.0.0/8 107.0.0.0/8 108.0.0.0/8 109.0.0.0/8 110.0.0.0/8 111.0.0.0/8 112.0.0.0/8 113.0.0.0/8 114.0.0.0/8 115.0.0.0/8 116.0.0.0/8 117.0.0.0/8 118.0.0.0/8 119.0.0.0/8 120.0.0.0/8 121.0.0.0/8 122.0.0.0/8 123.0.0.0/8 124.0.0.0/8 125.0.0.0/8 126.0.0.0/8 127.0.0.0/8 197.0.0.0/8 222.0.0.0/8 223.0.0.0/8 240.0.0.0/8 241.0.0.0/8 242.0.0.0/8 243.0.0.0/8 244.0.0.0/8 245.0.0.0/8 246.0.0.0/8 247.0.0.0/8 248.0.0.0/8 249.0.0.0/8 250.0.0.0/8 251.0.0.0/8 252.0.0.0/8 253.0.0.0/8 254.0.0.0/8 255.0.0.0/8 "

# Private IPv4 address space
# Suggested by Fco.Felix Belmonte <ffelix@gescosoft.com>
# Revised by me according to RFC 3330. Explanation:
# 10.0.0.0/8       => RFC 1918: IANA Private Use
# 169.254.0.0/16   => Link Local
# 192.0.2.0/24     => Test Net
# 192.88.99.0/24   => RFC 3068: 6to4 anycast
# 192.168.0.0/16   => RFC 1918: Private use
# 192.88.99.0/24   => RFC 2544: Benchmarking addresses
PRIVATE_IPS="10.0.0.0/8 169.254.0.0/16 172.16.0.0/12 169.254.0.0/16 192.88.99.0/24 192.168.0.0/16 192.88.99.0/24"

# The multicast address space
MULTICAST_IPS="224.0.0.0/8"

# A shortcut to have all the Internet unroutable addresses in one
# variable
UNROUTABLE_IPS="${RESERVED_IPS} ${PRIVATE_IPS}"

# ----------------------------------------------------------------------

# The default policy for the interface commands of the firewall.
# This can be controlled on a per interface basis using the
# policy interface subscommand. 
DEFAULT_INTERFACE_POLICY="DROP"

# What to do with unmatched packets?
# To change these, simply define them the configuration file.
UNMATCHED_INPUT_POLICY="DROP"
UNMATCHED_OUTPUT_POLICY="DROP"
UNMATCHED_ROUTER_POLICY="DROP"

# Options for iptables LOG action.
# These options will be added to all LOG actions FireHOL will generate.
# To change them, type such a line in the configuration file.
# FIREHOL_LOG_OPTIONS="--log-level warning --log-tcp-sequence --log-tcp-options --log-ip-options"
FIREHOL_LOG_OPTIONS="--log-level warning"

# Complex services' rules may add themeselves to this variable so that
# the service "all" will also call them.
# By default it is empty - only rules programmers should change this.
ALL_SHOULD_ALSO_RUN=

# The client ports to be used for "default" client ports when the
# client specified is a foreign host.
# We give all ports above 1000 because a few systems (like Solaris)
# use this range.
# Note that FireHOL will ask the kernel for default client ports of
# the local host. This only applies to client ports of remote hosts.
DEFAULT_CLIENT_PORTS="1000:65535"

# Get the default client ports from the kernel configuration.
# This is formed to a range of ports to be used for all "default"
# client ports when the client specified is the localhost.
LOCAL_CLIENT_PORTS_LOW=`sysctl net.ipv4.ip_local_port_range | cut -d '=' -f 2 | cut -f 1`
LOCAL_CLIENT_PORTS_HIGH=`sysctl net.ipv4.ip_local_port_range | cut -d '=' -f 2 | cut -f 2`
LOCAL_CLIENT_PORTS=`echo ${LOCAL_CLIENT_PORTS_LOW}:${LOCAL_CLIENT_PORTS_HIGH}`

# These files will be created and deleted during our run.
FIREHOL_OUTPUT="/tmp/firehol-out-$$.sh"
FIREHOL_SAVED="/tmp/firehol-save-$$.sh"
FIREHOL_TMP="/tmp/firehol-tmp-$$.sh"

# This is our version number. It is increased when the configuration
# file commands and arguments change their meaning and usage, so that
# the user will have to review it more precisely.
FIREHOL_VERSION=5
FIREHOL_VERSION_CHECKED=0

# The initial line number of the configuration file.
FIREHOL_LINEID="INIT"

# Variable kernel module requirements.
# Suggested by Fco.Felix Belmonte <ffelix@gescosoft.com>
# Bellow are the minimum ones. Note that each of the complex services
# may add to this variable the kernel modules it requires.
# See rules_ftp() bellow for an example.
FIREHOL_KERNEL_MODULES="ip_tables ip_conntrack"
#
# In the configuration file you can write:
#
#                     require_kernel_module <module_name>
# 
# to have FireHOL require a specific module for the configurarion.

# Set this to 1 in the configuration file to have FireHOL complex
# services' rules load NAT kernel modules too.
FIREHOL_NAT=0


# ------------------------------------------------------------------------------
# Keep information about the current primary command
# Primary commands are: interface, router

work_counter=0
work_cmd=
work_name=
work_inface=
work_outface=
work_policy=${DEFAULT_INTERFACE_POLICY}
work_error=0
work_function="Initializing"

# ------------------------------------------------------------------------------
# Keep status information

# Keeps a list of all interfaces we have setup rules
work_interfaces=

# 0 = no errors, 1 = there were errors in the script
work_final_status=0

# keeps a list of all created iptables chains
work_created_chains=


# ------------------------------------------------------------------------------
# XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
# ------------------------------------------------------------------------------
#
# SIMPLE SERVICES DEFINITIONS
#
# ------------------------------------------------------------------------------
# XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
# ------------------------------------------------------------------------------
# The following are definitions for simple services.
# We define as "simple" the services that are implemented using a single socket,
# initiated by the client and used by the server.
# The following list is sorted by service name.

server_daytime_ports="tcp/daytime"
client_daytime_ports="default"

server_dhcp_ports="udp/bootps"
client_dhcp_ports="bootpc"

server_echo_ports="tcp/echo"
client_echo_ports="default"

server_finger_ports="tcp/finger"
client_finger_ports="default"

# We assume heartbeat uses ports in the range 690 to 699
server_heartbeat_ports="udp/690:699"
client_heartbeat_ports="default"

server_http_ports="tcp/http"
client_http_ports="default"

server_https_ports="tcp/https"
client_https_ports="default"

server_ident_ports="tcp/auth"
client_ident_ports="default"

server_ike_ports="udp/500"
client_ike_ports="default"

server_imap_ports="tcp/imap"
client_imap_ports="default"

server_imaps_ports="tcp/imaps"
client_imaps_ports="default"

server_irc_ports="tcp/ircd"
client_irc_ports="default"
require_irc_modules="ip_conntrack_irc"
require_irc_nat_modules="ip_nat_irc"
ALL_SHOULD_ALSO_RUN="${ALL_SHOULD_ALSO_RUN} irc"

server_ldap_ports="tcp/ldap"
client_ldap_ports="default"

server_lpd_ports="tcp/printer"
client_lpd_ports="default"

server_mysql_ports="tcp/mysql"
client_mysql_ports="default"

server_netbios_ns_ports="udp/netbios-ns"
client_netbios_ns_ports="default udp/netbios-ns"

server_netbios_dgm_ports="udp/netbios-dgm"
client_netbios_dgm_ports="default netbios-dgm"

server_netbios_ssn_ports="tcp/netbios-ssn"
client_netbios_ssn_ports="default"

server_nntp_ports="tcp/nntp"
client_nntp_ports="default"

server_ntp_ports="udp/ntp tcp/ntp"
client_ntp_ports="ntp default"

server_pop3_ports="tcp/pop3"
client_pop3_ports="default"

# Portmap clients appear to use ports bellow 1024
server_portmap_ports="udp/sunrpc tcp/sunrpc"
client_portmap_ports="500:65535"

server_radius_ports="udp/radius udp/radius-acct"
client_radius_ports="default"

server_radiusold_ports="udp/1645 udp/1646"
client_radiusold_ports="default"

server_rndc_ports="tcp/rndc"
client_rndc_ports="default"

server_rsync_ports="tcp/rsync udp/rsync"
client_rsync_ports="default"

server_smtp_ports="tcp/smtp"
client_smtp_ports="default"

server_snmp_ports="udp/snmp"
client_snmp_ports="default"

server_ssh_ports="tcp/ssh"
client_ssh_ports="default"

# Sun RCP is an alias for service portmap
server_sunrpc_ports="${server_portmap_ports}"
client_sunrpc_ports="${client_portmap_ports}"

server_syslog_ports="udp/syslog"
client_syslog_ports="syslog"

server_telnet_ports="tcp/telnet"
client_telnet_ports="default"

# TFTP is more complicated than this.
# TFTP communicates through high ports. The problem is that there is
# no relevant iptables module in most distributions.
server_tftp_ports="udp/tftp"
client_tftp_ports="default"

server_uucp_ports="tcp/uucp"
client_uucp_ports="default"

server_vmware_ports="tcp/902"
client_vmware_ports="default"

server_vmwareauth_ports="tcp/903"
client_vmwareauth_ports="default"

server_vmwareweb_ports="tcp/8222"
client_vmwareweb_ports="default"

server_vnc_ports="tcp/5900:5903"
client_vnc_ports="default"

server_webcache_ports="tcp/webcache"
client_webcache_ports="default"


# ------------------------------------------------------------------------------
# XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
# ------------------------------------------------------------------------------
#
# COMPLEX SERVICES DEFINITIONS
#
# ------------------------------------------------------------------------------
# XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
# ------------------------------------------------------------------------------
# The following are definitions for complex services.
# We define as "complex" the services that are implemented using multiple sockets.

# Each function bellow is organized in three parts:
# 1) A Header, common to each and every function
# 2) The rules required for the INPUT of the server
# 3) The rules required for the OUTPUT of the server
#
# The Header part, together with the "reverse" keyword can reverse the rules so
# that if we are implementing a client the INPUT will become OUTPUT and vice versa.
#
# In most the cases the input and output rules are the same with the following
# differences:
#
# a) The output rules begin with the "reverse" keyword, which reverses:
#    inface/outface, src/dst, sport/dport
# b) The output rules use ${out}_${mychain} instead of ${in}_${mychain}
# c) The state rules match the client operation, not the server.


# --- SAMBA --------------------------------------------------------------------

rules_samba() {
        local mychain="${1}"; shift
	local type="${1}"; shift
	
	local in=in
	local out=out
	if [ "${type}" = "client" ]
	then
		in=out
		out=in
	fi
	
	local client_ports="${DEFAULT_CLIENT_PORTS}"
	if [ "${type}" = "client" ]
	then
		client_ports="${LOCAL_CLIENT_PORTS}"
	fi
	
	# ----------------------------------------------------------------------
	
	# allow new and established incoming packets
	rule action "$@" chain "${in}_${mychain}" proto "udp" sport "netbios-ns ${client_ports}"  dport "netbios-ns" state NEW,ESTABLISHED || return 1
	rule action "$@" chain "${in}_${mychain}" proto "udp" sport "netbios-dgm ${client_ports}" dport "netbios-dgm" state NEW,ESTABLISHED || return 1
	rule action "$@" chain "${in}_${mychain}" proto "tcp" sport "${client_ports}" dport "netbios-ssn" state NEW,ESTABLISHED || return 1
	
	# allow outgoing established packets
	rule reverse action "$@" chain "${out}_${mychain}" proto "udp" sport "netbios-ns ${client_ports}"  dport "netbios-ns" state ESTABLISHED || return 1
	rule reverse action "$@" chain "${out}_${mychain}" proto "udp" sport "netbios-dgm ${client_ports}" dport "netbios-dgm" state ESTABLISHED || return 1
	rule reverse action "$@" chain "${out}_${mychain}" proto "tcp" sport "${client_ports}" dport "netbios-ssn" state ESTABLISHED || return 1
	
	return 0
}


# --- PPTP --------------------------------------------------------------------

rules_pptp() {
        local mychain="${1}"; shift
	local type="${1}"; shift
	
	local in=in
	local out=out
	if [ "${type}" = "client" ]
	then
		in=out
		out=in
	fi
	
	local client_ports="${DEFAULT_CLIENT_PORTS}"
	if [ "${type}" = "client" ]
	then
		client_ports="${LOCAL_CLIENT_PORTS}"
	fi
	
	# ----------------------------------------------------------------------
	
	# allow new and established incoming packets
	rule action "$@" chain "${in}_${mychain}" proto "tcp" sport "${client_ports}" dport "1723" state NEW,ESTABLISHED || return 1
	rule action "$@" chain "${in}_${mychain}" proto "47" state NEW,ESTABLISHED || return 1
	
	# allow outgoing established packets
	rule reverse action "$@" chain "${out}_${mychain}" proto "tcp" sport "${client_ports}" dport "1723" state ESTABLISHED || return 1
	rule reverse action "$@" chain "${out}_${mychain}" proto "47" state ESTABLISHED|| return 1
	
	return 0
}


# --- NFS ----------------------------------------------------------------------

rules_nfs() {
        local mychain="${1}"; shift
	local type="${1}"; shift
	
	local in=in
	local out=out
	if [ "${type}" = "client" ]
	then
		in=out
		out=in
	fi
	
	local client_ports="${DEFAULT_CLIENT_PORTS}"
	if [ "${type}" = "client" ]
	then
		client_ports="${LOCAL_CLIENT_PORTS}"
	fi
	
	# ----------------------------------------------------------------------
	
	# This command requires in the client or route subcommands,
	# the first argument after the policy/action is a dst.
	
	local action="${1}"; shift
	local servers="localhost"
	
	if [ "${type}" = "client" ]
	then
		case "${1}" in
			dst|DST|destination|DESTINATION)
				shift
				servers="${1}"
				shift
				;;
				
			*)
				error "Please re-phrase to: ${type} nfs ${action} dst <NFS_SERVER> [other rules]"
				return 1
				;;
		esac
	fi
	
	local x=
	for x in ${servers}
	do
		local tmp="/tmp/firehol.rpcinfo.$$"
		
		rpcinfo -p ${x} >"${tmp}"
		if [ $? -gt 0 -o ! -s "${tmp}" ]
		then
			error "Cannot get rpcinfo from host '${x}' (using the previous firewall rules)"
			rm -f "${tmp}"
			return 1
		fi
		
		local server_mountd_ports="`cat "${tmp}" | grep " mountd$" | ( while read a b proto port s; do echo "$proto/$port"; done ) | sort | uniq`"
		local server_nfsd_ports="`cat "${tmp}" | grep " nfs$" | ( while read a b proto port s; do echo "$proto/$port"; done ) | sort | uniq`"
		
		local dst=
		if [ ! "${x}" = "localhost" ]
		then
			dst="dst ${x}"
		fi
		
		"${type}" custom nfs "${server_mountd_ports}" "500:65535" "${action}" $dst "$@"
		"${type}" custom nfs "${server_nfsd_ports}"   "500:65535" "${action}" $dst "$@"
		
		rm -f "${tmp}"
		
		echo >&2 ""
		echo >&2 "WARNING:"
		echo >&2 "This firewall must be restarted if NFS server ${x} is restarted !!!"
		echo >&2 ""
	done
	
	return 0
}


# --- DNS ----------------------------------------------------------------------

rules_dns() {
        local mychain="${1}"; shift
	local type="${1}"; shift
	
	local in=in
	local out=out
	if [ "${type}" = "client" ]
	then
		in=out
		out=in
	fi
	
	local client_ports="${DEFAULT_CLIENT_PORTS}"
	if [ "${type}" = "client" ]
	then
		client_ports="${LOCAL_CLIENT_PORTS}"
	fi
	
	# ----------------------------------------------------------------------
	
	# UDP: allow all incoming DNS packets
	rule action "$@" chain "${in}_${mychain}" proto udp dport domain || return 1
	
	# UDP: allow all outgoing DNS packets
	rule reverse action "$@" chain "${out}_${mychain}" proto udp dport domain || return 1
	
	# TCP: allow new and established incoming packets
	rule action "$@" chain "${in}_${mychain}" proto tcp dport domain state NEW,ESTABLISHED || return 1
	
	# TCP: allow outgoing established packets
	rule reverse action "$@" chain "${out}_${mychain}" proto tcp dport domain state ESTABLISHED || return 1
	
	return 0
}

# --- FTP ----------------------------------------------------------------------

ALL_SHOULD_ALSO_RUN="${ALL_SHOULD_ALSO_RUN} ftp"

rules_ftp() {
        local mychain="${1}"; shift
	local type="${1}"; shift
	
	local in=in
	local out=out
	if [ "${type}" = "client" ]
	then
		in=out
		out=in
	fi
	
	local client_ports="${DEFAULT_CLIENT_PORTS}"
	if [ "${type}" = "client" ]
	then
		client_ports="${LOCAL_CLIENT_PORTS}"
	fi
	
	# ----------------------------------------------------------------------
	
	# allow new and established incoming, and established outgoing
	# accept port ftp new connections
	rule action "$@" chain "${in}_${mychain}" proto tcp sport "${client_ports}" dport ftp state NEW,ESTABLISHED || return 1
	rule reverse action "$@" chain "${out}_${mychain}" proto tcp sport "${client_ports}" dport ftp state ESTABLISHED || return 1
	
	# Active FTP
	# send port ftp-data related connections
	rule action "$@" chain "${out}_${mychain}" proto tcp sport ftp-data dport "${client_ports}" state ESTABLISHED,RELATED || return 1
	rule reverse action "$@" chain "${in}_${mychain}" proto tcp sport ftp-data dport "${client_ports}" state ESTABLISHED || return 1
	
	# ----------------------------------------------------------------------
	
	# A hack for Passive FTP only
	local s_client_ports="${DEFAULT_CLIENT_PORTS}"
	local c_client_ports="${DEFAULT_CLIENT_PORTS}"
	
	if [ "${type}" = "client" ]
	then
		c_client_ports="${LOCAL_CLIENT_PORTS}"
	elif [ "${type}" = "server" ]
	then
		s_client_ports="${LOCAL_CLIENT_PORTS}"
	fi
	
	# Passive FTP
	# accept high-ports related connections
	rule action "$@" chain "${in}_${mychain}" proto tcp sport "${c_client_ports}" dport "${s_client_ports}" state ESTABLISHED,RELATED || return 1
	rule reverse action "$@" chain "${out}_${mychain}" proto tcp sport "${c_client_ports}" dport "${s_client_ports}" state ESTABLISHED || return 1
	
	require_kernel_module ip_conntrack_ftp
	test ${FIREHOL_NAT} -eq 1 && require_kernel_module ip_nat_ftp
	
	return 0
}


# --- ICMP ---------------------------------------------------------------------

ALL_SHOULD_ALSO_RUN="${ALL_SHOULD_ALSO_RUN} icmp"

rules_icmp() {
        local mychain="${1}"; shift
	local type="${1}"; shift
	
	local in=in
	local out=out
	if [ "${type}" = "client" ]
	then
		in=out
		out=in
	fi
	
	local client_ports="${DEFAULT_CLIENT_PORTS}"
	if [ "${type}" = "client" ]
	then
		client_ports="${LOCAL_CLIENT_PORTS}"
	fi
	
	# ----------------------------------------------------------------------
	
	# check out http://www.cs.princeton.edu/~jns/security/iptables/iptables_conntrack.html#ICMP
	
	# allow new and established incoming packets
	rule action "$@" chain "${in}_${mychain}" proto icmp state NEW,ESTABLISHED,RELATED || return 1
	
	# allow outgoing established packets
	rule reverse action "$@" chain "${out}_${mychain}" proto icmp state ESTABLISHED,RELATED || return 1
	
	return 0
}


# --- ALL ----------------------------------------------------------------------

rules_all() {
        local mychain="${1}"; shift
	local type="${1}"; shift
	
	local in=in
	local out=out
	if [ "${type}" = "client" ]
	then
		in=out
		out=in
	fi
	
	local client_ports="${DEFAULT_CLIENT_PORTS}"
	if [ "${type}" = "client" ]
	then
		client_ports="${LOCAL_CLIENT_PORTS}"
	fi
	
	# ----------------------------------------------------------------------
	
	# allow new and established incoming packets
	rule action "$@" chain "${in}_${mychain}" state NEW,ESTABLISHED || return 1
	
	# allow outgoing established packets
	rule reverse action "$@" chain "${out}_${mychain}" state ESTABLISHED || return 1
	
	local ser=
	for ser in ${ALL_SHOULD_ALSO_RUN}
	do
		"${type}" ${ser} "$@" || return 1
	done
	
	return 0
}


# --- ANY ----------------------------------------------------------------------

rules_any() {
        local mychain="${1}"; shift
	local type="${1}"; shift
	local name="${1}"; shift # a special case: service any gets a name
	
	local in=in
	local out=out
	if [ "${type}" = "client" ]
	then
		in=out
		out=in
	fi
	
	local client_ports="${DEFAULT_CLIENT_PORTS}"
	if [ "${type}" = "client" ]
	then
		client_ports="${LOCAL_CLIENT_PORTS}"
	fi
	
	# ----------------------------------------------------------------------
	
	# allow new and established incoming packets
	rule action "$@" chain "${in}_${mychain}" state NEW,ESTABLISHED || return 1
	
	# allow outgoing established packets
	rule reverse action "$@" chain "${out}_${mychain}" state ESTABLISHED || return 1
	
	return 0
}


# --- MULTICAST ----------------------------------------------------------------

rules_multicast() {
        local mychain="${1}"; shift
	local type="${1}"; shift
	
	local in=in
	local out=out
	if [ "${type}" = "client" ]
	then
		in=out
		out=in
	fi
	
	local client_ports="${DEFAULT_CLIENT_PORTS}"
	if [ "${type}" = "client" ]
	then
		client_ports="${LOCAL_CLIENT_PORTS}"
	fi
	
	# ----------------------------------------------------------------------
	
	# match multicast packets in both directions
	rule action "$@" chain "${out}_${mychain}" dst "224.0.0.0/8" || return 1
	rule reverse action "$@" chain "${in}_${mychain}" src "224.0.0.0/8" || return 1
	
	return 0
}


# ------------------------------------------------------------------------------
# XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
# ------------------------------------------------------------------------------
#
# INTERNAL FUNCTIONS BELLOW THIS POINT
#
# ------------------------------------------------------------------------------
# XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
# ------------------------------------------------------------------------------


# ------------------------------------------------------------------------------
# Manage kernel modules

require_kernel_module() {
	local new="${1}"
	
	local m=
	for m in ${FIREHOL_KERNEL_MODULES}
	do
		test "${m}" = "${new}" && return 0
	done
	
	FIREHOL_KERNEL_MODULES="${FIREHOL_KERNEL_MODULES} ${new}"
	
	return 0
}


# ------------------------------------------------------------------------------
# Check our version

version() {
	FIREHOL_VERSION_CHECKED=1
	
	if [ ${1} -gt ${FIREHOL_VERSION} ]
	then
		error "Wrong version. FireHOL is v${FIREHOL_VERSION}, your script requires v${1}."
	fi
}


# ------------------------------------------------------------------------------
# Make sure we cleanup when we exit.
# We trap this, so even a CTRL-C will call this and we will not leave tmp files.

firehol_exit() {
	
	if [ -f "${FIREHOL_SAVED}" ]
	then
		echo
		echo -n "FireHOL: Restoring old firewall:"
		iptables-restore <"${FIREHOL_SAVED}"
		if [ $? -eq 0 ]
		then
			success "FireHOL: Restoring old firewall:"
		else
			failure "FireHOL: Restoring old firewall:"
		fi
		echo
	fi
	
	test -f "${FIREHOL_OUTPUT}"	&& rm -f "${FIREHOL_OUTPUT}"
	test -f "${FIREHOL_OUTPUT}.log"	&& rm -f "${FIREHOL_OUTPUT}.log"
	test -f "${FIREHOL_SAVED}"	&& rm -f "${FIREHOL_SAVED}"
	test -f "${FIREHOL_TMP}"	&& rm -f "${FIREHOL_TMP}"
	test -f "${FIREHOL_TMP}.awk"	&& rm -f "${FIREHOL_TMP}.awk"
	
	return 0
}

# Make sure there is no saved firewall.
test -f "${FIREHOL_SAVED}" && rm -f "${FIREHOL_SAVED}"

# Run our exit even if we don't call exit.
trap firehol_exit EXIT



# ------------------------------------------------------------------------------
# Keep track of all interfaces used

register_iface() {
	local iface="${1}"
	
	local found=0
	local x=
	for x in ${work_interfaces}
	do
		if [ "${x}" = "${iface}" ]
		then
			found=1
			break
		fi
	done
	
	test $found -eq 0 && work_interfaces="${work_interfaces} ${iface}"
}


# ------------------------------------------------------------------------------
# Check the status of the current primary command.
# WHY:
# Some sanity check for the order of commands in the configuration file.
# Each function has a "require_work type command" in order to check that it is
# placed in a valid point. This means that if you place a "route" command in an
# interface section (and many other compinations) it will fail.

require_work() {
	local type="${1}"
	local cmd="${2}"
	
	case "${type}" in
		clear)
			test ! -z "${work_cmd}" && error "Previous work was not applied." && return 1
			;;
		
		set)
			test -z "${work_cmd}" && error "The command used requires that a primary command is set." && return 1
			test ! "${work_cmd}" = "${cmd}" -a ! "${cmd}" = "any"  && error "Primary command is '${work_cmd}' but '${cmd}' is required." && return 1
			;;
			
		*)
			error "Unknown work status '${type}'."
			return 1
			;;
	esac
	
	return 0
}


# ------------------------------------------------------------------------------
# Finalizes the rules of the last primary command.
# Finalization occures automatically when a new primary command is executed and
# when the script finishes.

close_cmd() {
	work_function="Closing last open primary command (${work_cmd}/${work_name})"
	
	case "${work_cmd}" in
		interface)
			close_interface
			;;
		
		router)
			close_router
			;;
		
		'')
			;;
		
		*)
			error "Unknown work '${work_cmd}'."
			return 1
			;;
	esac
	
	# Reset the current status variables to empty/default
	work_counter=0
	work_cmd=
	work_name=
	work_inface=
	work_outface=
	work_policy="${DEFAULT_INTERFACE_POLICY}"
	
	return 0
}

policy() {
	require_work set interface || return 1
	
	work_policy="${1}"
	
	return 0
}

masquerade() {
	local f="${1}"
	test -z "${f}" && f="${work_outface}"
	test "${f}" = "reverse" && f="${work_inface}"
	
	work_function="Initializing masquerade"
	
	test -z "${f}" && error "masquerade requires an interface set or as argument" && return 1
	
	local x=
	for x in ${f}
	do
#		iptables -t nat -A POSTROUTING -o "${x}" -j MASQUERADE || return 1
		rule table nat chain POSTROUTING outface "${x}" action MASQUERADE "$@" || return 1
	done
	
	FIREHOL_NAT=1
	
	return 0
}

# ------------------------------------------------------------------------------
# PRIMARY COMMAND: interface
# Setup rules specific to an interface (physical or logical)

interface() {
	# --- close any open command ---
	
	close_cmd
	
	
	# --- test prerequisites ---
	
	require_work clear || return 1
	work_function="Initializing interface"
	
	
	# --- get paramaters and validate them ---
	
	# Get the interface
	local inface="${1}"; shift
	test -z "${inface}" && error "interface is not set" && return 1
	
	# Get the name for this interface
	local name="${1}"; shift
	test -z "${name}" && error "Name is not set" && return 1
	
	
	# --- do the job ---
	
	work_cmd="${FUNCNAME}"
	work_name="${name}"
	
	work_function="Initializing interface '${work_name}'"
	
	create_chain filter "in_${work_name}" INPUT set_work_inface inface "${inface}" "$@"
	create_chain filter "out_${work_name}" OUTPUT set_work_outface reverse inface "${inface}" "$@"
	
	return 0
}

# ------------------------------------------------------------------------------
# close_interface()
# Finalizes the rules for the last interface primary command.

close_interface() {
	require_work set interface || return 1
	
	work_function="Finilizing interface '${work_name}'"
	
	case "${work_policy}" in
		return|RETURN)
			return 0
			;;
			
		accept|ACCEPT)
			;;
		
		*)
			local -a inlog=(loglimit "IN-${work_name}")
			local -a outlog=(loglimit "OUT-${work_name}")
			;;
	esac
	
	# Accept all related traffic to the established connections
	rule chain "in_${work_name}" state RELATED action ACCEPT
	rule chain "out_${work_name}" state RELATED action ACCEPT
	
	rule chain "in_${work_name}" "${inlog[@]}" action "${work_policy}"
	rule reverse chain "out_${work_name}" "${outlog[@]}" action "${work_policy}"
	
	return 0
}


router() {
	# --- close any open command ---
	
	close_cmd
	
	
	# --- test prerequisites ---
	
	require_work clear || return 1
	work_function="Initializing router"
	
	
	# --- get paramaters and validate them ---
	
	# Get the name for this router
	local name="${1}"; shift
	test -z "${name}" && error "router name is not set" && return 1
	
	
	# --- do the job ---
	
	work_cmd="${FUNCNAME}"
	work_name="${name}"
	
	work_function="Initializing router '${work_name}'"
	
	create_chain filter "in_${work_name}" FORWARD set_work_inface set_work_outface "$@"
	create_chain filter "out_${work_name}" FORWARD reverse "$@"
	
	return 0
}

close_router() {	
	require_work set router || return 1
	
	work_function="Finilizing router '${work_name}'"
	
	# Accept all related traffic to the established connections
	rule chain "in_${work_name}" state RELATED action ACCEPT
	rule chain "out_${work_name}" state RELATED action ACCEPT
	
# routers always have RETURN as policy	
#	local inlog=
#	local outlog=
#	case ${work_policy} in
#		return|RETURN)
#			return 0
#			;;
#		
#		accept|ACCEPT)
#			inlog=
#			outlog=
#			;;
#		
#		*)
#			inlog="loglimit PASSIN-${work_name}"
#			outlog="loglimit PASSOUT-${work_name}"
#			;;
#	esac
#	
#	rule chain in_${work_name} ${inlog} action ${work_policy}
#	rule reverse chain out_${work_name} ${outlog} action ${work_policy}
	
	return 0
}

close_master() {
	work_function="Finilizing firewall policies"
	
	# Accept all related traffic to the established connections
	rule chain INPUT state RELATED action ACCEPT
	rule chain OUTPUT state RELATED action ACCEPT
	rule chain FORWARD state RELATED action ACCEPT
	
	rule chain INPUT loglimit "IN-unknown" action ${UNMATCHED_INPUT_POLICY}
	rule chain OUTPUT loglimit "OUT-unknown" action ${UNMATCHED_OUTPUT_POLICY}
	rule chain FORWARD loglimit "PASS-unknown" action ${UNMATCHED_ROUTER_POLICY}
	return 0
}

# This variable is used for generating dynamic chains when needed for
# combined negative statements (AND) implied by the "not" parameter
# to many FireHOL directives.
# What FireHOL is doing to accomplish this, is to produce dynamically
# a linked list of iptables chains with just one condition each, making
# the packets to traverse from chain to chain when matched, to reach
# their final destination.
FIREHOL_DYNAMIC_CHAIN_COUNTER=1

rule() {
	local table="-t filter"
	local chain=
	
	local inface=any
	local infacenot=
	
	local outface=any
	local outfacenot=
	
	local src=any
	local srcnot=
	
	local dst=any
	local dstnot=
	
	local sport=any
	local sportnot=
	
	local dport=any
	local dportnot=
	
	local proto=any
	local protonot=
	
	local log=
	local logtxt=
	
	local limit=
	local burst=
	
	local iplimit=
	local iplimit_mask=
	
	local action=
	
	local state=
	local statenot=
	
	local failed=0
	local reverse=0
	
	local swi=0
	local swo=0
	
	local custom=
	
	while [ ! -z "${1}" ]
	do
		case "${1}" in
			set_work_inface|SET_WORK_INFACE)
				swi=1
				shift
				;;
				
			set_work_outface|SET_WORK_OUTFACE)
				swo=1
				shift
				;;
				
			reverse|REVERSE)
				reverse=1
				shift
				;;
				
			table|TABLE)
				table="-t ${2}"
				shift 2
				;;
				
			chain|CHAIN)
				chain="${2}"
				shift 2
				;;
				
			inface|INFACE)
				shift
				if [ ${reverse} -eq 0 ]
				then
					infacenot=
					if [ "${1}" = "not" -o "${1}" = "NOT" ]
					then
						shift
						infacenot="!"
					else
						if [ $swi -eq 1 ]
						then
							work_inface="${1}"
						fi
					fi
					inface="${1}"
				else
					outfacenot=
					if [ "${1}" = "not" -o "${1}" = "NOT" ]
					then
						shift
						outfacenot="!"
					else
						if [ ${swo} -eq 1 ]
						then
							work_outface="$1"
						fi
					fi
					outface="${1}"
				fi
				shift
				;;
				
			outface|OUTFACE)
				shift
				if [ ${reverse} -eq 0 ]
				then
					outfacenot=
					if [ "${1}" = "not" -o "${1}" = "NOT" ]
					then
						shift
						outfacenot="!"
					else
						if [ ${swo} -eq 1 ]
						then
							work_outface="${1}"
						fi
					fi
					outface="${1}"
				else
					infacenot=
					if [ "${1}" = "not" -o "${1}" = "NOT" ]
					then
						shift
						infacenot="!"
					else
						if [ ${swi} -eq 1 ]
						then
							work_inface="${1}"
						fi
					fi
					inface="${1}"
				fi
				shift
				;;
				
			src|SRC|source|SOURCE)
				shift
				if [ ${reverse} -eq 0 ]
				then
					srcnot=
					if [ "${1}" = "not" -o "${1}" = "NOT" ]
					then
						shift
						srcnot="!"
					fi
					src="${1}"
				else
					dstnot=
					if [ "${1}" = "not" -o "${1}" = "NOT" ]
					then
						shift
						dstnot="!"
					fi
					dst="${1}"
				fi
				shift
				;;
				
			dst|DST|destination|DESTINATION)
				shift
				if [ ${reverse} -eq 0 ]
				then
					dstnot=
					if [ "${1}" = "not" -o "${1}" = "NOT" ]
					then
						shift
						dstnot="!"
					fi
					dst="${1}"
				else
					srcnot=
					if [ "${1}" = "not" -o "${1}" = "NOT" ]
					then
						shift
						srcnot="!"
					fi
					src="${1}"
				fi
				shift
				;;
				
			sport|SPORT|sourceport|SOURCEPORT)
				shift
				if [ ${reverse} -eq 0 ]
				then
					sportnot=
					if [ "${1}" = "not" -o "${1}" = "NOT" ]
					then
						shift
						sportnot="!"
					fi
					sport="${1}"
				else
					dportnot=
					if [ "${1}" = "not" -o "${1}" = "NOT" ]
					then
						shift
						dportnot="!"
					fi
					dport="${1}"
				fi
				shift
				;;
				
			dport|DPORT|destinationport|DESTINATIONPORT)
				shift
				if [ ${reverse} -eq 0 ]
				then
					dportnot=
					if [ "${1}" = "not" -o "${1}" = "NOT" ]
					then
						shift
						dportnot="!"
					fi
					dport="${1}"
				else
					sportnot=
					if [ "${1}" = "not" -o "${1}" = "NOT" ]
					then
						shift
						sportnot="!"
					fi
					sport="${1}"
				fi
				shift
				;;
				
			proto|PROTO|protocol|PROTOCOL)
				shift
				protonot=
				if [ "${1}" = "not" -o "${1}" = "NOT" ]
				then
					shift
					protonot="!"
				fi
				proto="${1}"
				shift
				;;
				
			custom|CUSTOM)
				custom="${2}"
				shift 2
				;;
				
			log|LOG)
				log=normal
				logtxt="${2}"
				shift 2
				;;
				
			loglimit|LOGLIMIT)
				log=limit
				logtxt="${2}"
				shift 2
				;;
				
			limit|LIMIT)
				limit="${2}"
				burst="${3}"
				shift 3
				;;
				
			iplimit|IPLIMIT)
				iplimit="${2}"
				iplimit_mask="${3}"
				shift 3
				;;
				
			action|ACTION)
				action="${2}"
				shift 2
				;;
				
			state|STATE)
				shift
				statenot=
				if [ "${1}" = "not" -o "${1}" = "NOT" ]
				then
					shift
					statenot="!"
				fi
				state="${1}"
				shift
				;;
				
			*)
				error "Cannot understand directive '${1}'."
				return 1
				;;
		esac
	done
	
	
	case "${action}" in
		accept|ACCEPT)
			action=ACCEPT
			;;
			
		deny|DENY)
			action=DENY
			;;
			
		reject|REJECT)
			action=REJECT
			;;
			
		drop|DROP)
			action=DROP
			;;
			
		return|RETURN)
			action=RETURN
			;;
			
		none|NONE)
			action=NONE
			;;
	esac
	
	
	# ----------------------------------------------------------------------------------
	# Do we have negative contitions?
	# If yes, we have to make a linked list of chains to the final one.
	local chain_orig="${chain}"
	
	if [ ! "${infacenot}" = "" ]
	then
		local inf=
		for inf in ${inface}
		do
			chain2="${chain_orig}.${FIREHOL_DYNAMIC_CHAIN_COUNTER}"
			FIREHOL_DYNAMIC_CHAIN_COUNTER="$[FIREHOL_DYNAMIC_CHAIN_COUNTER + 1]"
			
			iptables ${table} -N "${chain2}"
			iptables ${table} -A "${chain}" -i ! "${inf}" -j "${chain2}"
			chain="${chain2}"
		done
		infacenot=
		inface=any
	fi
	
	if [ ! "${outfacenot}" = "" ]
	then
		local outf=
		for outf in ${outface}
		do
			chain2="${chain_orig}.${FIREHOL_DYNAMIC_CHAIN_COUNTER}"
			FIREHOL_DYNAMIC_CHAIN_COUNTER="$[FIREHOL_DYNAMIC_CHAIN_COUNTER + 1]"
			
			iptables ${table} -N "${chain2}"
			iptables ${table} -A "${chain}" -o ! "${outf}" -j "${chain2}"
			chain="${chain2}"
		done
		outfacenot=
		outface=any
	fi
	
	if [ ! "${srcnot}" = "" ]
	then
		local s=
		for s in ${src}
		do
			chain2="${chain_orig}.${FIREHOL_DYNAMIC_CHAIN_COUNTER}"
			FIREHOL_DYNAMIC_CHAIN_COUNTER="$[FIREHOL_DYNAMIC_CHAIN_COUNTER + 1]"
			
			iptables ${table} -N "${chain2}"
			iptables ${table} -A "${chain}" -s ! "${s}" -j "${chain2}"
			chain="${chain2}"
		done
		srcnot=
		src=any
	fi
	
	if [ ! "${dstnot}" = "" ]
	then
		local d=
		for d in ${dst}
		do
			chain2="${chain_orig}.${FIREHOL_DYNAMIC_CHAIN_COUNTER}"
			FIREHOL_DYNAMIC_CHAIN_COUNTER="$[FIREHOL_DYNAMIC_CHAIN_COUNTER + 1]"
			
			iptables ${table} -N "${chain2}"
			iptables ${table} -A "${chain}" -d ! "${d}" -j "${chain2}"
			chain="${chain2}"
		done
		dstnot=
		dst=any
	fi
	
	if [ ! "${sportnot}" = "" ]
	then
		local sp=
		for sp in ${sport}
		do
			chain2="${chain_orig}.${FIREHOL_DYNAMIC_CHAIN_COUNTER}"
			FIREHOL_DYNAMIC_CHAIN_COUNTER="$[FIREHOL_DYNAMIC_CHAIN_COUNTER + 1]"
			
			iptables ${table} -N "${chain2}"
			iptables ${table} -A "${chain}" --sport ! "${sp}" -j "${chain2}"
			chain="${chain2}"
		done
		sportnot=
		sport=any
	fi
	
	if [ ! "${dportnot}" = "" ]
	then
		local dp=
		for dp in ${dport}
		do
			chain2="${chain_orig}.${FIREHOL_DYNAMIC_CHAIN_COUNTER}"
			FIREHOL_DYNAMIC_CHAIN_COUNTER="$[FIREHOL_DYNAMIC_CHAIN_COUNTER + 1]"
			
			iptables ${table} -N "${chain2}"
			iptables ${table} -A "${chain}" --dport ! "${dp}" -j "${chain2}"
			chain="${chain2}"
		done
		dportnot=
		dport=any
	fi
	
	if [ ! "${protonot}" = "" ]
	then
		local pr=
		for pr in ${proto}
		do
			chain2="${chain_orig}.${FIREHOL_DYNAMIC_CHAIN_COUNTER}"
			FIREHOL_DYNAMIC_CHAIN_COUNTER="$[FIREHOL_DYNAMIC_CHAIN_COUNTER + 1]"
			
			iptables ${table} -N "${chain2}"
			iptables ${table} -A "${chain}" --p ! "${pr}" -j "${chain2}"
			chain="${chain2}"
		done
		protonot=
		proto=any
	fi
	
	
	# ----------------------------------------------------------------------------------
	# Process the positive rules
	
	local inf=
	for inf in ${inface}
	do
		unset inf_arg
		case ${inf} in
			any|ANY)
				;;
			
			*)
				local -a inf_arg=("-i" "${inf}")
				register_iface ${inf}
				;;
		esac
		
		local outf=
		for outf in ${outface}
		do
			unset outf_arg
			case ${outf} in
				any|ANY)
					;;
				
				*)
					local -a outf_arg=("-o" "${outf}")
					register_iface ${outf}
					;;
			esac
			
			local s=
			for s in ${src}
			do
				unset s_arg
				case ${s} in
					any|ANY)
						;;
					
					*)
						local -a s_arg=("-s" "${s}")
						;;
				esac
				
				local d=
				for d in ${dst}
				do
					unset d_arg
					case ${d} in
						any|ANY)
							;;
						
						*)
							local -a d_arg=("-d" "${d}")
							;;
					esac
					
					local sp=
					for sp in ${sport}
					do
						unset sp_arg
						case ${sp} in
							any|ANY)
								;;
							
							*)
								local -a sp_arg=("--sport" "${sp}")
								;;
						esac
						
						local dp=
						for dp in ${dport}
						do
							unset dp_arg
							case ${dp} in
								any|ANY)
									;;
								
								*)
									local -a dp_arg=("--dport" "${dp}")
									;;
							esac
							
							local pr=
							for pr in ${proto}
							do
								unset proto_arg
								
								case ${pr} in
									any|ANY)
										;;
									
									*)
										local -a proto_arg=("-p" "${proto}")
										;;
								esac
								
								unset state_arg
								if [ ! -z "${state}" ]
								then
									local -a state_arg=("-m" "state" "${statenot}" "--state" "${state}")
								fi
								
								unset limit_arg
								if [ ! -z "${limit}" ]
								then
									local -a limit_arg=("-m" "limit" "--limit" "${limit}" "--limit-burst" "${burst}")
								fi
								
								unset iplimit_arg
								if [ ! -z "${iplimit}" ]
								then
									local -a iplimit_arg=("-m" "iplimit" "--iplimit-above" "${iplimit}" "--iplimit-mask" "${iplimit_mask}")
								fi
								
								declare -a basecmd=("${table}" "-A" "${chain}" "${inf_arg[@]}" "${outf_arg[@]}" "${limit_arg[@]}" "${iplimit_arg[@]}" "${proto_arg[@]}" "${s_arg[@]}" "${sp_arg[@]}" "${d_arg[@]}" "${dp_arg[@]}" "${state_arg[@]}")
								
								case "${log}" in
									'')
										;;
									
									limit)
										iptables "${basecmd[@]}" ${custom} -m limit --limit 1/second -j LOG ${FIREHOL_LOG_OPTIONS} --log-prefix="${logtxt}:"
										;;
										
									normal)
										iptables "${basecmd[@]}" ${custom} -j LOG ${FIREHOL_LOG_OPTIONS} --log-prefix="${logtxt}:"
										;;
										
									*)
										error "Unknown log value '${log}'."
										;;
								esac
								
								if [ ! "${action}" = NONE ]
								then
									iptables "${basecmd[@]}" ${custom} -j "${action}"
									test $? -gt 0 && failed=$[failed + 1]
								fi
							done
						done
					done
				done
			done
		done
	done
	
	test ${failed} -gt 0 && error "There are ${failed} failed commands." && return 1
	return 0
}

postprocess() {
	local tmp=" >${FIREHOL_OUTPUT}.log 2>&1"
	test ${FIREHOL_DEBUG} -eq 1 && local tmp=
	
#	echo "$@" " $tmp # L:${FIREHOL_LINEID}" >>${FIREHOL_OUTPUT}
	
	local cmd=
	while [ ! -z "${1}" ]; do cmd="${cmd} '${1}'"; shift; done
	printf "%s" "${cmd}" >>${FIREHOL_OUTPUT}
	echo " $tmp # L:${FIREHOL_LINEID}" >>${FIREHOL_OUTPUT}
		
	test ${FIREHOL_DEBUG} -eq 0 && echo "check_final_status \$? '" "${cmd}" "' ${FIREHOL_LINEID}" >>${FIREHOL_OUTPUT}
	
	return 0
}

iptables() {
	postprocess "/sbin/iptables" "$@"
	
	return 0
}

check_final_status() {
	if [ ${1} -gt 0 ]
	then
		work_final_status=$[work_final_status + 1]
		echo >&2
		echo >&2 "--------------------------------------------------------------------------------"
		echo >&2 "ERROR #: ${work_final_status}."
		echo >&2 "WHAT   : A runtime command failed to execute."
		echo >&2 "SOURCE : line ${3} of ${FIREHOL_CONFIG}"
		echo >&2 "COMMAND: ${2}"
		echo >&2 "OUTPUT : (of the failed command)"
		cat ${FIREHOL_OUTPUT}.log
		echo >&2
	fi
	
	return 0
}

create_chain() {
	local table="${1}"
	local newchain="${2}"
	local oldchain="${3}"
	shift 3
	
	work_function="Creating chain '${newchain}' under '${oldchain}' in table '${table}'"
	
#	echo >&2 "CREATED CHAINS : ${work_created_chains}"
#	echo >&2 "REQUESTED CHAIN: ${newchain}"
	
	local x=
	for x in ${work_created_chains}
	do
		test "${x}" = "${newchain}" && return 1
	done
	
	iptables -t ${table} -N "${newchain}" || return 1
	rule table ${table} chain "${oldchain}" action "${newchain}" "$@" || return 1
	
	work_created_chains="${work_created_chains} ${newchain}"
	
	return 0
}

error() {
	work_error=$[work_error + 1]
	echo >&2
	echo >&2 "--------------------------------------------------------------------------------"
	echo >&2 "ERROR #: ${work_error}"
	echo >&2 "WHAT   : ${work_function}"
	echo >&2 "WHY    :" "$@"
	echo >&2 "SOURCE : line ${FIREHOL_LINEID} of ${FIREHOL_CONFIG}"
	echo >&2
	
	return 0
}

# smart_function() creates a chain for the subcommand and
# detects, for each service given, if it is a simple service
# or a custom rules based service.

smart_function() {
	local type="${1}"	# The current subcommand: server/client/route
	local services="${2}"	# The services to implement
	shift 2
	
	local service=
	for service in $services
	do
		work_function="Looking up service '${service}' (${type})"
		
		# Increase the command counter, to make all chains within a primary
		# command, unique.
		work_counter=$[work_counter + 1]
		
		local suffix="u${work_counter}"
		case "${type}" in
			client)
				suffix="c${work_counter}"
				;;
			
			server)
				suffix="s${work_counter}"
				;;
			
			route)
				suffix="r${work_counter}"
				;;
			
			*)	error "Cannot understand type '${type}'."
				return 1
				;;
		esac
		
		local mychain="${work_name}_${service}_${suffix}"
		
		create_chain filter "in_${mychain}" "in_${work_name}"
		create_chain filter "out_${mychain}" "out_${work_name}"
		
		# Try the simple services first
		simple_service "${mychain}" "${type}" "${service}" "$@"
		local ret=$?
		
		# simple service completed succesfully.
		test $ret -eq 0 && continue
		
		# simple service exists but failed.
		if [ $ret -ne 127 ]
		then
			error "Simple service '${service}' returned an error ($ret)."
			return 1
		fi
		
		
		# Try the custom services
		local fn="rules_${service}"
		"${fn}" "${mychain}" "${type}" "$@"
		local ret=$?
		test $ret -eq 0 && continue
		
		if [ $ret -eq 127 ]
		then
			error "There is no service '${service}' defined."
		else
			error "Complex service '${service}' returned an error ($ret)."
		fi
		return 1
	done
	
	return 0
}

server() {
	require_work set any || return 1
	smart_function server "$@"
	return $?
}

client() {
	require_work set any || return 1
	smart_function client "$@"
	return $?
}

route() {
	require_work set router || return 1
	smart_function server "$@"
	return $?
}

simple_service() {
	local mychain="${1}"; shift
	local type="${1}"; shift
	local server="${1}"; shift
	
	local server_varname="server_${server}_ports"
	local server_ports="`eval echo \\\$${server_varname}`"
	
	local client_varname="client_${server}_ports"
	local client_ports="`eval echo \\\$${client_varname}`"
	
	test -z "${server_ports}" -o -z "${client_ports}" && return 127
	
	local x=
	local varname="require_${server}_modules"
	local value="`eval echo \\\$${varname}`"
	for x in ${value}
	do
		require_kernel_module $x || return 1
	done
	
	if [ ${FIREHOL_NAT} -eq 1 ]
	then
		local varname="require_${server}_nat_modules"
		local value="`eval echo \\\$${varname}`"
		for x in ${value}
		do
			require_kernel_module $x || return 1
		done
	fi
	
	rules_custom "${mychain}" "${type}" "${server}" "${server_ports}" "${client_ports}" "$@"
	return $?
}


rules_custom() {
	local mychain="${1}"; shift
	local type="${1}"; shift
	
	local server="${1}"; shift
	local my_server_ports="${1}"; shift
	local my_client_ports="${1}"; shift
	
	local in=in
	local out=out
	if [ "${type}" = "client" ]
	then
		in=out
		out=in
	fi
	
	local client_ports="${DEFAULT_CLIENT_PORTS}"
	if [ "${type}" = "client" ]
	then
		client_ports="${LOCAL_CLIENT_PORTS}"
	fi
	
	# ----------------------------------------------------------------------
	
	local sp=
	for sp in ${my_server_ports}
	do
		local proto="`echo $sp | cut -d '/' -f 1`"
		local sport="`echo $sp | cut -d '/' -f 2`"
		
		local cp=
		for cp in ${my_client_ports}
		do
			local cport=
			case ${cp} in
				default)
					cport="${client_ports}"
					;;
					
				*)	cport="${cp}"
					;;
			esac
			
			# allow new and established incoming packets
			rule action "$@" chain "${in}_${mychain}" proto "${proto}" sport "${cport}" dport "${sport}" state NEW,ESTABLISHED || return 1
			
			# allow outgoing established packets
			rule reverse action "$@" chain "${out}_${mychain}" proto "${proto}" sport "${cport}" dport "${sport}" state ESTABLISHED || return 1
		done
	done
	
	return 0
}


# --- protection ---------------------------------------------------------------

protection() {
	require_work set any || return 1
	
	local in="in"
	local prface="${work_inface}"
	
	if [ "${1}" = "reverse" ]
	then
		in="out"
		prface="${work_outface}"
		shift
	fi
	
	local type="${1}"
	local rate="${2}"
	local burst="${3}"
	
	test -z "${rate}"  && rate="100/s"
	test -z "${burst}" && burst="4"
	
	local x=
	for x in ${type}
	do
		case "${x}" in
			none|NONE)
				return 0
				;;
			
			strong|STRONG|full|FULL|all|ALL)
				protection "fragments new-tcp-w/o-syn icmp-floods syn-floods malformed-xmas malformed-null malformed-bad" "${rate}" "${burst}"
				return $?
				;;
				
			fragments|FRAGMENTS)
				local mychain="pr_${work_name}_fragments"
				create_chain filter "${mychain}" "${in}_${work_name}" custom "-f"				|| return 1
				
				rule chain "${mychain}" loglimit "PACKET FRAGMENTS" action drop 				|| return 1
				;;
				
			new-tcp-w/o-syn|NEW-TCP-W/O-SYN)
				local mychain="pr_${work_name}_nosyn"
				create_chain filter "${mychain}" "${in}_${work_name}" proto tcp state NEW custom "! --syn"	|| return 1
				
				rule chain "${mychain}" loglimit "NEW TCP w/o SYN" action drop					|| return 1
				;;
				
			icmp-floods|ICMP-FLOODS)
				local mychain="pr_${work_name}_icmpflood"
				create_chain filter "${mychain}" "${in}_${work_name}" proto icmp custom "--icmp-type echo-request"	|| return 1
				
				rule chain "${mychain}" limit "${rate}" "${burst}" action return				|| return 1
				rule chain "${mychain}" loglimit "ICMP FLOOD" action drop					|| return 1
				;;
				
			syn-floods|SYN-FLOODS)
				local mychain="pr_${work_name}_synflood"
				create_chain filter "${mychain}" "${in}_${work_name}" proto tcp custom "--syn"			|| return 1
				
				rule chain "${mychain}" limit "${rate}" "${burst}" action return				|| return 1
				rule chain "${mychain}" loglimit "SYN FLOOD" action drop					|| return 1
				;;
				
			malformed-xmas|MALFORMED-XMAS)
				local mychain="pr_${work_name}_malxmas"
				create_chain filter "${mychain}" "${in}_${work_name}" proto tcp custom "--tcp-flags ALL ALL"	|| return 1
				
				rule chain "${mychain}" loglimit "MALFORMED XMAS" action drop					|| return 1
				;;
				
			malformed-null|MALFORMED-NULL)
				local mychain="pr_${work_name}_malnull"
				create_chain filter "${mychain}" "${in}_${work_name}" proto tcp custom "--tcp-flags ALL NONE"	|| return 1
				
				rule chain "${mychain}" loglimit "MALFORMED NULL" action drop					|| return 1
				;;
				
			malformed-bad|MALFORMED-BAD)
				local mychain="pr_${work_name}_malbad"
				create_chain filter "${mychain}" "${in}_${work_name}" proto tcp custom "--tcp-flags SYN,FIN SYN,FIN"		|| return 1
				rule chain "${in}_${work_name}" action "${mychain}"   proto tcp custom "--tcp-flags SYN,RST SYN,RST"			|| return 1
				rule chain "${in}_${work_name}" action "${mychain}"   proto tcp custom "--tcp-flags ALL     SYN,RST,ACK,FIN,URG"	|| return 1
				rule chain "${in}_${work_name}" action "${mychain}"   proto tcp custom "--tcp-flags ALL     FIN,URG,PSH"		|| return 1
				
				rule chain "${mychain}" loglimit "MALFORMED BAD" action drop							|| return 1
				;;
		esac
	done
	
	return 0
}

# --- set_proc_value -----------------------------------------------------------

set_proc_value() {
	local file="${1}"
	local value="${2}"
	local why="${3}"
	
	if [ ! -f "${file}" ]
	then
		echo >&2 "WARNING: File '${file}' does not exist."
		return 1
	fi
	
	local t="`cat ${1}`"
	if [ ! "$t" = "${value}" ]
	then
		local name=`echo ${file} | tr '/' '.' | cut -d '.' -f 4-`
		echo >&2 "WARNING: To ${why}, you should run:"
		echo >&2 "         \"sysctl -w ${name}=${value}\""
		echo >&2
#		postprocess "echo 1 >'${file}'"
	fi
}


# ------------------------------------------------------------------------------
# XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
# ------------------------------------------------------------------------------
#
# MAIN PROCESSING
#
# ------------------------------------------------------------------------------
# XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
# ------------------------------------------------------------------------------

echo -n $"FireHOL: Setting firewall defaults:"
ret=0

# --- Initialization -----------------------------------------------------------

# Ignore all pings
###set_proc_value /proc/sys/net/ipv4/icmp_echo_ignore_all 1 "ignore all pings"

# Ignore all icmp broadcasts - protects from smurfing
###set_proc_value /proc/sys/net/ipv4/icmp_echo_ignore_broadcasts 1 "be protected from smurfing"

# Ignore source routing
###set_proc_value /proc/sys/net/ipv4/conf/all/accept_source_route 0 "ignore source routing"

# Ignore routing redirects
###set_proc_value /proc/sys/net/ipv4/conf/all/accept_redirects 0 "ignore redirects"

# Enable bad error message protection.
###set_proc_value /proc/sys/net/ipv4/icmp_ignore_bogus_error_responses 1 "be protected from bad error messages"

# Turn on reverse path filtering. This helps make sure that packets use
# legitimate source addresses, by automatically rejecting incoming packets
# if the routing table entry for their source address doesn't match the network
# interface they're arriving on. This has security advantages because it prevents
# so-called IP spoofing, however it can pose problems if you use asymmetric routing
# (packets from you to a host take a different path than packets from that host to you)
# or if you operate a non-routing host which has several IP addresses on different
# interfaces. (Note - If you turn on IP forwarding, you will also get this).
###set_proc_value /proc/sys/net/ipv4/conf/all/rp_filter 1 "match routing table with source interfaces"

# Log spoofed packets, source routed packets, redirect packets.
###set_proc_value /proc/sys/net/ipv4/conf/all/log_martians 1 "log spoofing, source routing, redirects"

# ------------------------------------------------------------------------------

iptables -F				|| ret=$[ret + 1]
iptables -X				|| ret=$[ret + 1]
iptables -Z				|| ret=$[ret + 1]
iptables -t nat -F			|| ret=$[ret + 1]
iptables -t nat -X			|| ret=$[ret + 1]
iptables -t nat -Z			|| ret=$[ret + 1]
iptables -t mangle -F			|| ret=$[ret + 1]
iptables -t mangle -X			|| ret=$[ret + 1]
iptables -t mangle -Z			|| ret=$[ret + 1]


# ------------------------------------------------------------------------------
# Set everything to accept in order not to loose the connection the user might
# be working now.

iptables -P INPUT ACCEPT		|| ret=$[ret + 1]
iptables -P OUTPUT ACCEPT		|| ret=$[ret + 1]
iptables -P FORWARD ACCEPT		|| ret=$[ret + 1]


# ------------------------------------------------------------------------------
# Accept everything in/out the loopback device.

iptables -A INPUT -i lo -j ACCEPT	|| ret=$[ret + 1]
iptables -A OUTPUT -o lo -j ACCEPT	|| ret=$[ret + 1]


# ------------------------------------------------------------------------------
# Drop all invalid packets.
# Netfilter HOWTO suggests to DROP all INVALID packets.

iptables -A INPUT -m state --state INVALID -j DROP	|| ret=$[ret + 1]
iptables -A OUTPUT -m state --state INVALID -j DROP	|| ret=$[ret + 1]
iptables -A FORWARD -m state --state INVALID -j DROP	|| ret=$[ret + 1]


if [ $ret -eq 0 ]
then
	success $"FireHOL: Setting firewall defaults:"
	echo
else
	failure$ $"FireHOL: Setting firewall defaults:"
	echo
	exit 1
fi


# XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX

echo -n $"FireHOL: Processing file ${FIREHOL_CONFIG}:"
ret=0

# ------------------------------------------------------------------------------
# Create a small awk script that inserts line numbers in the configuration file
# just before each known directive.
# These line numbers will be used for debugging the configuration script.

cat >"${FIREHOL_TMP}.awk" <<EOF
/^[[:space:]]*interface[[:space:]]/ { printf "FIREHOL_LINEID=\\\${LINENO} " }
/^[[:space:]]*router[[:space:]]/ { printf "FIREHOL_LINEID=\\\${LINENO} " }
/^[[:space:]]*route[[:space:]]/ { printf "FIREHOL_LINEID=\\\${LINENO} " }
/^[[:space:]]*client[[:space:]]/ { printf "FIREHOL_LINEID=\\\${LINENO} " }
/^[[:space:]]*server[[:space:]]/ { printf "FIREHOL_LINEID=\\\${LINENO} " }
/^[[:space:]]*iptables[[:space:]]/ { printf "FIREHOL_LINEID=\\\${LINENO} " }
/^[[:space:]]*protection[[:space:]]/ { printf "FIREHOL_LINEID=\\\${LINENO} " }
/^[[:space:]]*policy[[:space:]]/ { printf "FIREHOL_LINEID=\\\${LINENO} " }
/^[[:space:]]*masquerade[[:space:]]/ { printf "FIREHOL_LINEID=\\\${LINENO} " }
{ print }
EOF

cat ${FIREHOL_CONFIG} | awk -f "${FIREHOL_TMP}.awk" >${FIREHOL_TMP}
rm -f "${FIREHOL_TMP}.awk"

# ------------------------------------------------------------------------------
# Run the configuration file.

enable -n trap			# Disable the trap buildin shell command.
enable -n exit			# Disable the exit buildin shell command.
source ${FIREHOL_TMP} "$@"	# Run the configuration as a normal script.
FIREHOL_LINEID="FIN"
enable trap			# Enable the trap buildin shell command.
enable exit			# Enable the exit buildin shell command.


# ------------------------------------------------------------------------------
# Make sure the script stated a version number.

if [ ${FIREHOL_VERSION_CHECKED} -eq 0 ]
then
	error "The configuration file does not state a version number."
	failure $"FireHOL: Processing file ${FIREHOL_CONFIG}:"
	echo
	exit 1
fi

close_cmd					|| ret=$[ret + 1]
close_master					|| ret=$[ret + 1]

iptables -P INPUT DROP				|| ret=$[ret + 1]
iptables -P OUTPUT DROP				|| ret=$[ret + 1]
iptables -P FORWARD DROP			|| ret=$[ret + 1]

iptables -t nat -P PREROUTING ACCEPT		|| ret=$[ret + 1]
iptables -t nat -P POSTROUTING ACCEPT		|| ret=$[ret + 1]
iptables -t nat -P OUTPUT ACCEPT		|| ret=$[ret + 1]

iptables -t mangle -P PREROUTING ACCEPT		|| ret=$[ret + 1]
#iptables -t mangle -P POSTROUTING ACCEPT	|| ret=$[ret + 1]
iptables -t mangle -P OUTPUT ACCEPT		|| ret=$[ret + 1]

if [ ${work_error} -gt 0 -o $ret -gt 0 ]
then
	echo >&2
	echo >&2 "NOTICE: No changes made to your firewall."
	failure $"FireHOL: Processing file ${FIREHOL_CONFIG}:"
	echo
	exit 1
fi

success $"FireHOL: Processing file ${FIREHOL_CONFIG}:"
echo


# XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX

if [ ${FIREHOL_DEBUG} -eq 1 ]
then
	cat ${FIREHOL_OUTPUT}
	exit 1
fi


# XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX

echo -n $"FireHOL: Loading required kernel modules:"
ret=0
for m in ${FIREHOL_KERNEL_MODULES}
do
	modprobe $m || ret=$[ret + 1]
done

if [ $ret -gt 0 ]
then
	failure $"FireHOL: Loading required kernel modules:"
	echo
	exit 1
fi
success $"FireHOL: Loading required kernel modules:"
echo


# XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX

echo -n $"FireHOL: Saving your old firewall to a temporary file:"
iptables-save >${FIREHOL_SAVED}
if [ $? -eq 0 ]
then
	success $"FireHOL: Saving your old firewall to a temporary file:"
	echo
else
	test -f "${FIREHOL_SAVED}" && rm -f "${FIREHOL_SAVED}"
	failure $"FireHOL: Saving your old firewall to a temporary file:"
	echo
	exit 1
fi


# XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX

echo -n $"FireHOL: Activating new firewall:"

source ${FIREHOL_OUTPUT} "$@"

if [ ${work_final_status} -gt 0 ]
then
	failure $"FireHOL: Activating new firewall:"
	echo
	
	# The trap will restore the firewall.
	
	exit 1
fi
success $"FireHOL: Activating new firewall:"
echo

if [ ${FIREHOL_TRY} -eq 1 ]
then
	read -p "Keep the firewall? (type 'commit' to accept - 30 seconds timeout) : " -t 30 -e
	ret=$?
	echo
	if [ ! $ret -eq 0 -o ! "${REPLY}" = "commit" ]
	then
		# The trap will restore the firewall.
		
		exit 1
	else
		echo "Successfull activation of FireHOL firewall."
	fi
fi

# Remove the saved firewall, so that the trap will not restore it.
rm -f "${FIREHOL_SAVED}"

touch /var/lock/subsys/iptables

# XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX

if [ ${FIREHOL_SAVE} -eq 1 ]
then
	/etc/init.d/iptables save
	exit $?
fi
