#!/bin/bash

# Check if the JSON file path is provided
if [ -z "$1" ]; then
    echo "Error: No JSON file path provided."
    exit 1
fi

# The path to the JSON file
json_file="$1"

# Check if the file exists
if [ ! -f "$json_file" ]; then
    echo "Error: JSON file not found at path '$json_file'."
    exit 1
fi

# Use jq to parse the JSON file and convert it to 'key=value' format
# Assuming the JSON structure is a flat key-value object
jq -r "to_entries|map(\"\(.key) ?= \(.value|tostring)\")|.[]" "$json_file"
