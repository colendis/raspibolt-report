#!/bin/bash

# Checks whether the script is being running as sudo
# This script needs read access to the logs that can only be read as sudo
if [ $(whoami) != 'root' ]; then
  echo "This script requires sudo or root privileges in order to access the logs."
  echo "Please, run the script with sudo."
  exit 0
fi

# Paths
pathBitcoin=

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
  echo "The argument hoursAgo must be an integer"
  exit 0
fi

# Calculate date and timestamp depending on 'hoursAgo'
dateFrom=$(date -d "now-$hoursAgo hours" +"%b %d %H:%M:%S")
dateFromTimeStamp=$(($(date -d "now-$hoursAgo hours" +%s%N)/1000000))

# Date's formats
# Format: MMM DD hh:mm:ss (ie: Jan 03 18:15:00) -> Attention: the date does not include the year!
dateFormat_loginattemps="s/\([[:alpha:]]\{3\} [[:digit:]]\{2\} [[:digit:]]\{2\}:[[:digit:]]\{2\}:[[:digit:]]\{2\}\) \(.*\)$/\1/"
# Format: yyyy-MM-dd hh:mm:ss (ie: 2009-01-03 18:15:00)
dateFormat_fail2ban="s/\([[:digit:]]\{4\}-[[:digit:]]\{2\}-[[:digit:]]\{2\} [[:digit:]]\{2\}:[[:digit:]]\{2\}:[[:digit:]]\{2\}\)\(.*\)$/\1/"
# Format: MMM DD hh:mm:ss (ie: Jan 03 18:15:00) -> Attention: the date does not include the year!
dateFormat_ufw="s/\([[:alpha:]]\{3\} [[:digit:]]\{2\} [[:digit:]]\{2\}:[[:digit:]]\{2\}:[[:digit:]]\{2\}\) \(.*\)$/\1/"
# Format of bitcoin logs: yyyy-MM-ddThh:mm:ssZ (ie: 2009-01-03T18:15:00Z)
dateFormat_bitcoin="s/\([[:digit:]]\{4\}-[[:digit:]]\{2\}-[[:digit:]]\{2\}T[[:digit:]]\{2\}:[[:digit:]]\{2\}:[[:digit:]]\{2\}Z\) \(.*\)$/\1/"

# Whether any log entry was displayed (0: false, 1: true)
logsPrinted=0

# Returns the string "..." if the input's length is greater than 'printMaxLength'
# Argument 1: represents the input
print() {
  line=$(expr substr "$1" 1 $printMaxLength)
  suffix=""

  if [ ${#1} -gt $printMaxLength ]; then
    suffix="..."
  fi

  echo "$line$suffix"
}

# Returns the string "No log entries found!" if 'logsPrinted' is 0
printNoLogsFound() {
  if [ $logsPrinted -eq 0 ]; then
    printf "${color_grey}No log entries found!${color_none}\n\n"
  fi
}

# Returns the given date in milliseconds
# Argument 1: date
getMilliseconds() {
  echo $(($(date -d "$1" +%s%N)/1000000))
}


# Start
# ------------------------------------------------------------------------------
printf "\nDisplaying logs from $dateFrom ($hoursAgo hours ago)"


# Logins
# ------------------------------------------------------------------------------
printf "\n\n${color_blue}━━━ ${color_yellow}Logins ${color_blue}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${color_none}"
printf "\n\n${color_grey}Logins between 22:00 and 07:59 are considered suspicious. For detailed information on the logs: $ last${color_none}\n\n"

logsPrinted=0

while read line
do
  # Trim line
  line=$(echo $line | sed 's/ *$//g')

  if [ ${#line} == 0 ]; then
    break
  fi

  # Filter all hours between 22:00-07:59
  match=$(echo $line | grep --color=always '\( 2[2-3]:[0-5][0-9] \)\|\( 0[0-7]:[0-5][0-9] \)')

  if [ ${#match} = 0 ]; then
    print "$line"
  else
    print "$match"
  fi

  logsPrinted=1
# Remove unnecessary last line ("wtmp begins")
done <<< $(last -R -s "-${hoursAgo}hours" | grep -v "wtmp begins")

printNoLogsFound


# Login attempts
# ------------------------------------------------------------------------------
printf "\n\n${color_blue}━━━ ${color_yellow}Login attempts ${color_blue}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${color_none}"
printf "\n\n${color_grey}For detailed information on the logs: $ sudo cat /var/log/auth.log${color_none}\n\n"

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
done <<< $(cat /var/log/auth.log | egrep --color=always 'Failed|Failure|preauth|Connection closed')

printNoLogsFound


# Fail2ban
# ------------------------------------------------------------------------------
printf "\n${color_blue}━━━ ${color_yellow}Fail2ban ${color_blue}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${color_none}\n\n"
printf "${color_grey}Fail2Ban actions aren't necessary bad. For detailed information on the logs: $ sudo cat /var/log/fail2ban.log${color_none}\n\n"

if test -f "/etc/fail2ban/fail2ban.conf"; then
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
  done <<< $(cat /var/log/fail2ban.log | grep  -i --color=always 'fail2ban\.actions')

  printNoLogsFound
else
  printf "${color_red}Fail2ban was not found in your system.\n\n"
  printf "Fail2ban is a log-parsing application that monitors system logs for symptoms of an automated attack.${color_none}\n\n"
fi


# Firewall connection attempts
# ------------------------------------------------------------------------------
printf "\n${color_blue}━━━ ${color_yellow}Firewall connections attempts ${color_blue}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${color_none}\n\n"
printf "${color_grey}For detailed information on the logs: $ sudo cat /var/log/ufw.log${color_none}\n\n"

if test -f "/etc/ufw/ufw.conf"; then
  logsPrinted=0

  while read line
  do
    # Trim line
    line=$(echo $line | sed 's/ *$//g')

    if [ ${#line} == 0 ]; then
      break
    fi

    # Date's format: MMM DD hh:mm:ss (ie: Jan 03 18:15:00) -> Attention: the date does not include the year!
    entryDateMatch=$(echo $line | sed "s/\([[:alpha:]]\{3\} [[:digit:]]\{2\} [[:digit:]]\{2\}:[[:digit:]]\{2\}:[[:digit:]]\{2\}\) \(.*\)$/\1/")

    if [ ${#entryDateMatch} != 0 ]; then
      entryDateTimeStamp=$(getMilliseconds $entryDateMatch)

      if [ $entryDateTimeStamp -gt $dateFromTimeStamp ]; then
        print "$line"
        logsPrinted=1
     fi
    fi
  # INFO: filter all broadcast connections (224.0.0.)
  done <<< $(cat /var/log/ufw.log | grep -av '224.0.0.')

  printNoLogsFound
else
  printf "${color_red}UFW was not found in your system.\n\n"
  printf "UFW manages a netfilter firewall.${color_none}\n\n"
fi


# Bitcoin Core logs
# ------------------------------------------------------------------------------
printf "\n${color_blue}━━━ ${color_yellow}Bitcoin Core ${color_blue}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${color_none}\n\n"

if [ ${#pathBitcoin} -eq 0 ]; then
  echo "The variable 'pathBitcoin' is empty. Please fill it in."
else
  printf "${color_grey}For detailed information on the logs: $ sudo cat ${pathBitcoin}debug.log${color_none}\n\n"

  while read line
  do
    # Trim line
    line=$(echo $line | sed 's/ *$//g')

    if [ ${#line} == 0 ]; then
      break
    fi

    # Date's format: yyyy-MM-ddThh:mm:ssZ (ie: 2009-01-03T18:15:00Z)
    entryDateMatch=$(echo $line | sed "s/\([[:digit:]]\{4\}-[[:digit:]]\{2\}-[[:digit:]]\{2\}T[[:digit:]]\{2\}:[[:digit:]]\{2\}:[[:digit:]]\{2\}Z\) \(.*\)$/\1/")

    if [ ${#entryDateMatch} != 0 ]; then
      entryDateTimeStamp=$(getMilliseconds $entryDateMatch)

      if [ $entryDateTimeStamp -gt $dateFromTimeStamp ]; then
        print "$line"
        logsPrinted=1
      fi
    fi
  done <<< $(cat "${pathBitcoin}debug.log" | egrep -i --color=always 'error|warn(ing)?')

  printNoLogsFound
fi


# Electrum Server logs
# ------------------------------------------------------------------------------
printf "\n${color_blue}━━━ ${color_yellow}Electrum Server ${color_blue}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${color_none}\n\n"
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
done <<< $(journalctl -u electrs --since="${hoursAgo} hours ago" | egrep -i --color=always 'error|warn(ing)?')

printNoLogsFound
