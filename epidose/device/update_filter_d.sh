#!/bin/sh
#
# Periodically update the Cuckoo filter of affected users
#
# Copyright 2020 Diomidis Spinellis
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

set -e

# Location of the Cuckoo filter
FILTER=/var/lib/epidose/client-filter.bin

export APP_NAME=update_filter_d

# Pick up utility functions relative to the script's source code
UTIL="$(dirname "$0")/util.sh"


# Source common functionality (logging, WiFi)
# shellcheck source=epidose/device/util.sh
. "$UTIL"

# Wait until a filter file is required
wait_till_filter_needed()
{
  # Checks whether the Cuckoo filter is stale or fresh
  # and returns the time until its valid (in seconds)
  validity_time=$(get_filter_validity_age)
  if [ "$validity_time" -ne 0 ]; then
    log "Sleeping for $validity_time s"
    # Sleep until filter becomes invalid and store sleep process id
    sleep "$validity_time" &
    sleep_pid=$!
    echo "$sleep_pid" > "$SLEEP_UPDATE_FILTER_PID"
    if wait $sleep_pid ; then
      log "Waking up from sleep; new filter is now required"
    else
      log "Killed during sleep; obtaining a new filter"
    fi
  fi
}

while : ; do
  wait_till_filter_needed
  log "Obtaining new filter from $SERVER_URL"
  while : ; do
    wifi_acquire
    check_for_updates
    # Provide a chance for a remote user to log in
    sleep 60
    # Tries to get a new cuckoo filter from the ha-server
    if get_new_filter; then
      wifi_release
      break
    else
      wifi_release
      log "Will retry in $WIFI_RETRY_TIME s"
      sleep "$WIFI_RETRY_TIME"
    fi
  done
  run_python check_infection_risk "$FILTER" || :
done
