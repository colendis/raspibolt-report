#!/bin/bash

# Checks whether the script is being running as sudo
# This script needs read access to the logs that can only be read as sudo
if [ $(whoami) != 'root' ]; then
  echo "This script requires sudo or root privileges in order to access the logs."
  echo "Please, run the script with sudo."
  exit 0
fi

# Paths
pathBitcoin=""

# Colors
color_blue='\033[0;34m'
color_green='\033[0;32m'
color_grey='\033[0;37m'
color_red='\033[0;31m'
color_yellow='\033[0;33m'
color_none='\033[0m'

# Max length of characters to display per line (some log entries can be very long)
printMaxLength=250

# Period to look for events in hours (default: 48 hours)
hoursAgo=48

# Argument 1: represents 'hoursAgo'
if [ "$1" != "" ]; then
  hoursAgo=$1
fi

# Check whether 'hoursAgo' is an integer
if ! [[ "$hoursAgo" =~ ^[0-9]+$ ]]; then
  echo "The argument hoursAgo must be an integer."
  exit 0
fi

# Check whether 'pathBitcoin' is filled in or not
if [ ${#pathBitcoin} -eq 0 ]; then
  echo "The variable 'pathBitcoin' is empty. Please fill it in."
  exit 0
fi

# Calculate date (format: MMM DD HH:mm:ss) and timestamp depending on 'hoursAgo'
dateFrom=$(date -d "now-$hoursAgo hours" +"%b %d %H:%M:%S")
dateFromTimeStamp=$(($(date -d "now-$hoursAgo hours" +%s%N)/1000000))

# Date's formats
# Format: MMM DD hh:mm:ss (ie: Jan [3|03] 18:15:00) -> Attention: the date does not include the year!
dateFormat_loginattemps="s/\([a-zA-Z]\{3\} [0-9]\{1,2\} [0-9]\{2\}:[0-9]\{2\}:[0-9]\{2\}\) \(.*\)$/\1/"
# Format: yyyy-MM-dd hh:mm:ss (ie: 2009-01-03 18:15:00)
dateFormat_fail2ban="s/\([0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\} [0-9]\{2\}:[0-9]\{2\}:[0-9]\{2\}\)\(.*\)$/\1/"
# Format: MMM DD hh:mm:ss (ie: Jan [3|03] 18:15:00) -> Attention: the date does not include the year!
dateFormat_ufw="s/\([a-zA-Z]\{3\} [0-9]\{1,2\} [0-9]\{2\}:[0-9]\{2\}:[0-9]\{2\}\) \(.*\)$/\1/"
# Format of bitcoin logs: yyyy-MM-ddThh:mm:ssZ (ie: 2009-01-03T18:15:00Z)
dateFormat_bitcoin="s/\([0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}T[0-9]\{2\}:[0-9]\{2\}:[0-9]\{2\}Z\) \(.*\)$/\1/"

# Whether any log entry was displayed (0: false, 1: true)
logsPrinted=0

# Returns the string "..." if the input's length is greater than 'printMaxLength'
# Argument 1: represents the input
print() {
  line=$(expr substr "$1" 1 $printMaxLength)
  lineSuffix=""

  if [ ${#1} -gt $printMaxLength ]; then
    lineSuffix="..."
  fi

  echo "$line$lineSuffix"
}

# Returns the string "No log entries found!" if 'logsPrinted' is 0
printNoLogsFound() {
  if [ $logsPrinted -eq 0 ]; then
    printf "${color_grey}No log entries found!${color_none}\n"
  fi
}

# Returns the given date in milliseconds
# Argument 1: date
getMilliseconds() {
  echo $(($(date -d "$1" +%s%N)/1000000))
}

# Returns a formatted title with a fixed lenght
printTitle() {
  titleLenght=$(expr length "$1")
  titleSuffixLength=$(expr 100 - ${titleLenght})

  printf "\n\n${color_blue}━━━ ${color_yellow}$1 ${color_blue}"
  for i in $(seq 1 $titleSuffixLength); do printf "━"; done
  printf "${color_none}\n\n"
}


# Start
# ------------------------------------------------------------------------------
printf "\nDisplaying logs from $dateFrom ($hoursAgo hours ago)"


# Login sessions
# ------------------------------------------------------------------------------
printTitle "Login sessions"
printf "${color_grey}Login sessions between 22:00 and 07:59 are considered suspicious. For detailed information on the logs: $ last${color_none}\n\n"

logsPrinted=0

while read line
do
  # Trim line
  line=$(echo $line | sed 's/ *$//g')

  if [ ${#line} == 0 ]; then
    break
  fi

  # Filter all hours between 22:00-07:59 and active sessions
  match=$(echo $line | grep --color=always '\( 2[2-3]:[0-5][0-9] \)\|\( 0[0-7]:[0-5][0-9] \)\|\(still logged in\)')

  if [ ${#match} = 0 ]; then
    print "$line"
  else
    print "$match"
  fi

  logsPrinted=1
# Remove unnecessary last line ("wtmp begins")
done <<< $(last -R -s "-${hoursAgo}hours" | grep -iv "wtmp begins")

printNoLogsFound


# Login attempts failed
# ------------------------------------------------------------------------------
printTitle "Login attempts failed"
printf "${color_grey}For detailed information on the logs: $ sudo cat /var/log/auth.log${color_none}\n\n"

logsPrinted=0

while read line
do
  # Trim line
  line=$(echo $line | sed 's/ *$//g')

  if [ ${#line} == 0 ]; then
    break
  fi

  # Date's format: MMM DD hh:mm:ss (ie: Jan 03 18:15:00) -> Attention: the date does not include the year!
  entryDateMatch=$(echo $line | sed "$dateFormat_loginattemps")

  if [ ${#entryDateMatch} != 0 ]; then
    entryDateTimeStamp=$(getMilliseconds "$entryDateMatch")

    if [ $entryDateTimeStamp -gt $dateFromTimeStamp ]; then
      print "$line"
      logsPrinted=1
    fi
  fi
done <<< $(cat /var/log/auth.log | egrep -ai --color=always 'failed|failure|preauth|connection closed')

printNoLogsFound


# Login attempts succeeded
# ------------------------------------------------------------------------------
printTitle "Login attempts succeeded"
printf "${color_grey}For detailed information on the logs: $ sudo cat /var/log/auth.log${color_none}\n\n"
printf "${color_grey}If any login has been made by an unknown IP, you should take preventive measures:${color_none}\n"
printf "${color_grey} - Block suspicious IPs or range of IPs in your firewall (UFW)${color_none}\n"
printf "${color_grey} - Allow only local connections in your firewall (UFW)${color_none}\n"
printf "${color_grey} - If you log in with a password, you should change it by a very strong one${color_none}\n"
printf "${color_grey} - If you log in with a public key, you might want to generate a new key${color_none}\n\n"

logsPrinted=0
usageOfPasswordDetected=0

while read line
do
  # Trim line
  line=$(echo $line | sed 's/ *$//g')

  if [ ${#line} == 0 ]; then
    break
  fi

  # Look for log in with password
  usageOfPasswordMatch=$(echo $line | egrep -ai "accepted password")
  if [ ${#usageOfPasswordMatch} != 0 ]; then
    usageOfPasswordDetected=1
  fi

  # Date's format: MMM DD hh:mm:ss (ie: Jan 03 18:15:00) -> Attention: the date does not include the year!
  entryDateMatch=$(echo $line | sed "$dateFormat_loginattemps")

  if [ ${#entryDateMatch} != 0 ]; then
    entryDateTimeStamp=$(getMilliseconds "$entryDateMatch")

    if [ $entryDateTimeStamp -gt $dateFromTimeStamp ]; then
      print "$line"
      logsPrinted=1
    fi
  fi
done <<< $(cat /var/log/auth.log | egrep -ai --color=always 'new session|accepted password|accepted publickey')

printNoLogsFound

if [ $usageOfPasswordDetected -eq 1 ]; then
  printf '%b' "\n${color_red}\033[1mDetected usage of password to log in. It's highly recommended to log in with a public key you only own. This increases the security a lot!\033[0m${color_none}\n"
fi


# Fail2ban
# ------------------------------------------------------------------------------
printTitle "Fail2ban"

if test -f "/etc/fail2ban/fail2ban.conf"; then
  printf "${color_grey}Fail2Ban actions aren't necessary bad. For detailed information on the logs: $ sudo cat /var/log/fail2ban.log${color_none}\n\n"
  logsPrinted=0

  while read line
  do
    # Trim line
    line=$(echo $line | sed 's/ *$//g')

    if [ ${#line} == 0 ]; then
      break
    fi

    # Date's format: yyyy-MM-dd hh:mm:ss (ie: 2009-01-03 18:15:00)
    entryDateMatch=$(echo $line | sed "$dateFormat_fail2ban")

    if [ ${#entryDateMatch} != 0 ]; then
      entryDateTimeStamp=$(getMilliseconds $entryDateMatch)

      if [ $entryDateTimeStamp -gt $dateFromTimeStamp ]; then
        print "$line"
        logsPrinted=1
      fi
    fi
  done <<< $(cat /var/log/fail2ban.log | grep -ai --color=always 'fail2ban\.actions')

  printNoLogsFound

  printf "\n\n${color_grey}Statistics about failed and banned actions. For detailed information: $ sudo fail2ban-client status sshd${color_none}\n\n"

  sudo fail2ban-client status sshd
else
  printf "${color_red}Fail2ban was not found in your system.\n\n"
  printf "${color_grey}Fail2ban is a log-parsing application that monitors system logs for symptoms of an automated attack.\n\n"
  printf "If you want to install Fail2ban: $ sudo apt install fail2ban\n\n"
  printf "If you want to know if Fail2ban is installed: $ sudo fail2ban-client status${color_none}\n\n"
fi


# Firewall connection attempts
# ------------------------------------------------------------------------------
printTitle "Firewall connections attempts"

if test -f "/etc/ufw/ufw.conf"; then
  printf "${color_grey}For detailed information on the logs: $ sudo cat /var/log/ufw.log${color_none}\n\n"
  logsPrinted=0

  while read line
  do
    # Trim line
    line=$(echo $line | sed 's/ *$//g')

    if [ ${#line} == 0 ]; then
      break
    fi

    # Date's format: MMM DD hh:mm:ss (ie: Jan 03 18:15:00) -> Attention: the date does not include the year!
    entryDateMatch=$(echo $line | sed "$dateFormat_ufw")

    if [ ${#entryDateMatch} != 0 ]; then
      entryDateTimeStamp=$(getMilliseconds "$entryDateMatch")

      if [ $entryDateTimeStamp -gt $dateFromTimeStamp ]; then
        print "$line"
        logsPrinted=1
     fi
    fi
  # INFO: filter all broadcast connections (224.0.0.)
  done <<< $(cat /var/log/ufw.log | egrep -aiv -e '224\.0\.0\.|UFW AUDIT')

  printNoLogsFound
else
  printf "${color_red}Either UFW is not in your system or the logs are not activated.\n\n"
  printf "${color_grey}UFW manages a netfilter firewall.\n\n"
  printf "If you want to know if UFW is installed: $ sudo ufw status\n\n"
  printf "If you alreaday have installed UFW and want to activate the logs: $ sudo ufw logging on\n\n"
  printf "If you want to install UFW: $ sudo apt install ufw${color_none}\n\n"
fi


# Bitcoin Core logs
# ------------------------------------------------------------------------------
printTitle "Bitcoin Core"
printf "${color_grey}For detailed information on the logs: $ sudo cat ${pathBitcoin}debug.log${color_none}\n\n"

logsPrinted=0

while read line
do
  # Trim line
  line=$(echo $line | sed 's/ *$//g')

  if [ ${#line} == 0 ]; then
    break
  fi

  # Date's format: yyyy-MM-ddThh:mm:ssZ (ie: 2009-01-03T18:15:00Z)
  entryDateMatch=$(echo $line | sed "$dateFormat_bitcoin")

  if [ ${#entryDateMatch} != 0 ]; then
    entryDateTimeStamp=$(getMilliseconds "$entryDateMatch")

    if [ $entryDateTimeStamp -gt $dateFromTimeStamp ]; then
      print "$line"
      logsPrinted=1
    fi
  fi
done <<< $(cat "${pathBitcoin}debug.log" | egrep -ai --color=always 'error|warn(ing)?')

printNoLogsFound


# Electrum Server logs
# ------------------------------------------------------------------------------
printTitle "Electrum Server"
printf "${color_grey}For detailed information on the logs: $ sudo journalctl -u electrs${color_none}\n\n"

logsPrinted=0

while read line
do
  # Trim line
  line=$(echo $line | sed 's/ *$//g')

  if [ ${#line} == 0 ]; then
    # The line won't be printed if the line is empty
    break
  fi

  print "$line"
  logsPrinted=1
done <<< $(journalctl -u electrs --since="${hoursAgo} hours ago" | egrep -ai --color=always 'error|warn(ing)?')

printNoLogsFound


# Tor Hidden Services
# ------------------------------------------------------------------------------
printTitle "Tor Hidden Services"
printf "${color_grey}Active tor hidden services. For detailed information: $ cat /etc/tor/torrc${color_none}\n\n"

cat /etc/tor/torrc | egrep -ai --color=always ^HiddenServiceDir

# Services
# ------------------------------------------------------------------------------
printTitle "Services"
printf "${color_grey}Services that failed to start. For detailed information: $ sudo systemctl list-units --failed${color_none}\n\n"

systemctl list-units --failed

print ""
