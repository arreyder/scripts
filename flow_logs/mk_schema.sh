#!/bin/bash

# Usage: ./parquet_to_go.sh [path to your parquet file]

PARQUET_FILE="$1"

if [[ -z "$PARQUET_FILE" ]]; then
    echo "Please provide a Parquet file path."
    exit 1
fi

echo "type YourStructName struct {"

parquet-tools schema "$PARQUET_FILE" | grep -Eo 'name=[^,]+, type=[^,]+' | while read -r line; do
    # Extract field name and type
    name=$(echo "$line" | grep -Eo 'name=[^,]+' | cut -d= -f2)
    type=$(echo "$line" | grep -Eo 'type=[^,]+' | cut -d= -f2)

    # Map Parquet type to Go type
    case $type in
        BOOLEAN)
            go_type="bool"
            ;;
        INT32)
            go_type="int32"
            ;;
        INT64)
            go_type="int64"
            ;;
        FLOAT)
            go_type="float32"
            ;;
        DOUBLE)
            go_type="float64"
            ;;
        BYTE_ARRAY)
            go_type="[]byte"
            ;;
        *)
            go_type="interface{}" # Default case for unhandled types
            ;;
    esac

    # Output the Go struct field
    echo "    $name $go_type \`parquet:\"name=$name, type=$type\"\`"
done

echo "}"

