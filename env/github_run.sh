#!/bin/bash

# Set the environment for the github command:
this_dir=`dirname "$0"`
. $this_dir/activate

# Run the command passed to the script:
echo "Showing env"
env
echo "$ $@"
eval "$@"
