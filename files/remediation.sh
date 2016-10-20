#!/bin/bash

# Takes a check command, and an action command
# If the action doesn't return a 0, the action is run and the output is returned
RETRIES=1
while getopts "n:c:a:r:" arg; do
  case $arg in
  n)
    # The name of the check we're running
    NAME=$OPTARG
    ;;
  c)
    # The check that we're running
    CHECK=$OPTARG
    ;;
  a)
    # The action to take in the case of a non 0 exit
    ACTION=$OPTARG
    ;;
  r)
    # Number of times to retry the action
    RETRIES=$OPTARG
    ;;
  esac
done

CHECK_OUTPUT=$($CHECK)
CHECK_EXITCODE=$?
echo -e "$CHECK_OUTPUT"

# For logic, it is easier to compare attempts to max_attempts.
# When a users says "0" retries, they really mean max_attempts=1
let MAX_ATTEMPTS=$RETRIES+1

if [ $CHECK_EXITCODE -eq 2 ]; then

  # The check failed. Lets try remediation
  if [[ -f "/tmp/$NAME" ]]; then
    ATTEMPTS=$(cat "/tmp/$NAME")
  else
    ATTEMPTS=0
    echo $ATTEMPTS > "/tmp/$NAME"
  fi

  echo ""
  if [ $ATTEMPTS -ge $MAX_ATTEMPTS ]; then
    echo "Not doing remediation. Already did $ATTEMPTS out of $MAX_ATTEMPTS attempts" >&2
  else
    ATTEMPTS=$((ATTEMPTS + 1))
    echo "Trying remediation attempt $ATTEMPTS out of $MAX_ATTEMPTS..." >&2
    $ACTION
    echo $ATTEMPTS >"/tmp/$NAME"
  fi

else
  # The check has succeeded. Let's clean up
  rm -f "/tmp/$NAME"
fi

exit $CHECK_EXITCODE
