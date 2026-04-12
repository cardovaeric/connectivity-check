#!/bin/bash

# Configuration
INPUT_FILE=$1
TIMEOUT=2

# Get Source IP (Local IP)
SOURCE_IP=$(hostname -I | awk '{print $1}')

# 1. Validation
if [[ -z "$INPUT_FILE" ]]; then
    echo "Usage: $0 <filename>"
    exit 1
fi

if [[ ! -f "$INPUT_FILE" ]]; then
    echo "Error: File '$INPUT_FILE' not found."
    exit 1
fi

# Table Header
printf "%-15s | %-60s | %-8s | %-6s | %-19s | %-25s\n" "SOURCE IP" "DESTINATION (RESOLVED IP)" "PORT" "STATUS" "DATE" "REMARK/ISSUE"
printf "%0.s-" {1..150}
echo

# 2. Read the file line by line
while IFS= read -r line || [ -n "$line" ]; do
    [[ -z "$line" || "$line" =~ ^# ]] && continue
    
    host_part=$(echo "$line" | cut -d':' -f1 | xargs)
    port_part=$(echo "$line" | cut -d':' -f2)

    # Attempt to resolve IP
    resolved_ip=$(getent hosts "$host_part" | awk '{print $1}' | head -n 1)
    
    # Format the display string: hostname (resolved_ip) or just IP if it was already an IP
    if [[ -n "$resolved_ip" && "$resolved_ip" != "$host_part" ]]; then
        display_dest="$host_part ($resolved_ip)"
    else
        display_dest="$host_part"
    fi

    IFS=',' read -ra ADDR <<< "$port_part"
    
    for port in "${ADDR[@]}"; do
        port=$(echo "$port" | xargs)
        current_date=$(date "+%Y-%m-%d %H:%M:%S")
        issue="None"
        
        # Check if we failed to resolve (and it's not a raw IP)
        if [[ -z "$resolved_ip" ]] && ! [[ "$host_part" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            status="NOK"
            issue="DNS Resolution Failed"
        else
            # Perform connectivity test
            output=$(nc -zv -w $TIMEOUT "$host_part" "$port" 2>&1)
            
            if [ $? -eq 0 ]; then
                status="OK"
                issue="Success"
            else
                status="NOK"
                if [[ "$output" == *"timed out"* ]]; then
                    issue="Connection Timeout (Firewall?)"
                elif [[ "$output" == *"refused"* ]]; then
                    issue="Connection Refused (Service Down?)"
                else
                    issue="Network Unreachable"
                fi
            fi
        fi

        # Print formatted row
        printf "%-15s | %-60s | %-8s | %-6s | %-19s | %-25s\n" "$SOURCE_IP" "$display_dest" "$port" "$status" "$current_date" "$issue"
    done
done < "$INPUT_FILE"