#!/bin/sh
#
#
#
# If you would prefer not to use a hash of your username & machine os+version for the client ID, please 
# uncomment below and type in anything you like, but it MUST BE UNIQUE
#CLIENT_ID="replace with anything you like"
#
# Uncomment below and change to your interface if you don't want the script to try to work it out
#INTERFACE="tab0"
#
# if you have a different url to check port status then place it here, the port will be appended to the end of the URI
#PORTCHECKURI="http://example.xyz/pc.php?p="

PROGRAM=`basename $0`
VERSION=1.1
CURL_TIMEOUT=4
USE_IP=0
USE_SUM=0
SILENT=1
TESTPORT=1


# Check commands we need exist if not found, set alternatives if we have them.
for cmd in awk sed curl ip shasum; do
  if ! command -v $cmd > /dev/null; then
    case "$cmd" in 
    'ip')
      if ! command -v ifconfig > /dev/null; then
        echo "command 'ip' and 'ifconfig' not found, please check path or install one of them"
        exit 1
      fi
      USE_IP=1
    ;;
    'shasum')
      if ! command -v md5sum > /dev/null; then
        if ! command -v md5 > /dev/null; then
          echo "commands 'shasum', 'md5sum' and 'md5' are not found, please check path or install one of them"
          exit 1
        fi
        USE_SUM=2
      else
        USE_SUM=1
      fi
    ;;
    *)
      echo "command '$cmd' not found, please check path or install"
      exit 1
    ;;
    esac
  fi
done


error( )
{
  echo "$@" 1>&2
  exit 1
}

error_and_usage( )
{
  echo "$@" 1>&2
  usage_and_exit 1
}

usage( )
{
  echo "Usage: `dirname $0`/$PROGRAM (optional parameters) <user> <password>"
  echo ""
  echo "  <credentials filename> - path to plane text file containing PIA credentials"
  echo "                           1st line of file is username, 2nd line is passwd"
  echo "                           can use same file you use for openvpn credentials"
  echo "  optional parameter(s)"
  echo "     -v | --version sho version"
  echo "     -f | --file <credentials filename>"
  echo "     -t | --testport <run an external test on port>"
  echo "     -s | --silent <silent, print port and nothing else>"
  echo "     -i | --interface tun0"
  echo ""
}

usage_and_exit( )
{
  usage
  exit $1
}

version( )
{
  echo "$PROGRAM version $VERSION"
}

port_forward_assignment( )
{
  if [ $USE_IP -eq 0 ]; then
    if [ -z "${INTERFACE}" ];then
      INTERFACE=`ip addr show | awk 'BEGIN{FS=":"} /POINTOPOINT/ {gsub(/^[ \t]+/, "", $2); gsub(/[ \t]+$/, "", $2); print $2}'`
      if [ -z "${INTERFACE}" ];then
        echo "ERROR: Can't find VPN interface, please edit script and hardcode it"
        exit 1
      fi
    fi
    IPADDRESS=`ip addr show $INTERFACE | awk '/inet / {print $2}'`
  else
    if [ -z "${INTERFACE}" ];then
      INTERFACE=`ifconfig | awk 'BEGIN {RS="\n\n"} /POINTTOPOINT/ {print $1}'`
      if [ -z "${INTERFACE}" ];then
        echo "ERROR: Can't find VPN interface, please edit script and hardcode it"
        exit 1
      fi
    fi
    IPADDRESS=`ifconfig $INTERFACE | awk '/inet / {print $2}' | awk 'BEGIN { FS = ":" } {print $(NF)}'`
  fi

  if [ -z "${CLIENT_ID}" ];then
    CLIENT_ID="$USER `uname -v`"
  fi

  # Encode the string with md5 or sha, then delete every 'f' in the string, this will make a UUID that's constantly
  # generated, doesn't have to be stored anywhere, and can't be decrypted.

  if [ $USE_SUM -eq 0 ]; then
    CLIENT_ID=`echo $CLIENT_ID | shasum | awk '{gsub("f","",$1); print $1}'`
  else
    if [ $USE_SUM -eq 1 ]; then
      CLIENT_ID=`echo $CLIENT_ID | md5sum | awk '{gsub("f","",$1); print $1}'`
    else
      CLIENT_ID=`echo $CLIENT_ID | md5 | awk '{gsub("f","",$1); print $1}'`
    fi
  fi

  json=`curl -m $CURL_TIMEOUT --silent --interface $INTERFACE -d "user=$USER&pass=$PASSWORD&client_id=$CLIENT_ID&local_ip=$IPADDRESS" 'https://www.privateinternetaccess.com/vpninfo/port_forward_assignment' | head -1`
}


print_vpn_information()
{
  if [ $SILENT -ne 0 ];then echo "Using VPN connection on interface $INTERFACE..."; fi

  externalIP=`curl -m $CURL_TIMEOUT --interface $INTERFACE "http://ipinfo.io/ip" --silent --stderr -`
  if [ $SILENT -ne 0 ];then echo "VPN Internal IP = $IPADDRESS";fi

  if port=`echo $json | awk 'BEGIN{r=1;FS="{|:|}"} /port/{r=0; print $3} END{exit r}'`; then
    if [ ! -z "${port##*[!0-9]*}" ]; then
      if [ $SILENT -ne 0 ];then echo "VPN External IP:Port = $externalIP:$port";else echo $port;fi
    else
      if [ $SILENT -ne 0 ];then echo "VPN External IP = $externalIP (port forwarding is disabled on pia server, or port returned from pia is invalid)";fi
      if [ $SILENT -ne 0 ];then echo " *** pia returned invalid port '$port' ***";fi
    fi
  else
    if [ $SILENT -ne 0 ];then echo "Error assigning port forward in pia";fi
    echo $json
  fi

  if [ $TESTPORT -eq 0 -a $SILENT -ne 0 ]; then
    echo 'Checking incomming connections...'
    if [ -z "${PORTCHECKURI}" ];then 
      echo '*** WARNING Using 3rd pary to check, do not run this often as it will detect a bot and send a capatcha ***'
      status=`curl -m $CURL_TIMEOUT "http://ports.yougetsignal.com/check-port.php" -H "Origin: http://www.yougetsignal.com" --data "remoteAddress=$externalIP&portNumber=$port" --compressed --silent --stderr - | sed -e 's/<[^>]*>//g'`
    else
      status=`curl -s -m $CURL_TIMEOUT "$PORTCHECKURI$port"`
      status="Port $port is $status on $externalIP"
    fi
    echo $status
  fi
}


while [ "`echo $1 | cut -c1`" = "-" ]; do
  case "$1" in
    "--usage"|"--help"|"-h" ) usage_and_exit 0;;
    "--version"|"-v"        ) version; exit 0;;
    "--file"|"-f"           ) if [ ! -f $2 ] ; then
                                echo "File dosent exist"
                                usage_and_exit 0
                              else
                                USER=$(head -n 1 $2)
                                PASSWORD=$(tail -n 1 $2)
                              fi; shift 2;;
    "--testport"|"--t"      ) TESTPORT=0; shift;;
    "--silent"|"-s"         ) SILENT=0; shift;;
    "--interface"|"-i"      ) echo "Interface: $2 "; INTERFACE="$2"; shift 2;;
  esac
done
if [ "$1" != "" ] ; then
  USER=$1
fi
if [ "$2" != "" ] ; then
  PASSWORD=$2
fi

if [ -z "${USER}" ] || [ -z "${PASSWORD}" ]; then
  usage_and_exit 0
fi

port_forward_assignment
print_vpn_information

exit 0

