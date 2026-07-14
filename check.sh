#!/bin/bash

# ==============================================================================
# Connectivity Test Strategy Script (Parallel + Grouped by Remark)
# ==============================================================================

# 1. Dependency Check
for cmd in nc getent awk cut printf timeout sort wc grep sed xargs; do
    if ! command -v $cmd > /dev/null; then
        echo "Error: Required command '$cmd' is not installed."
        exit 1
    fi
done

# 2. Configuration & Arguments
INPUT_FILE=$1
TIMEOUT=3
OUTPUT_NOK_FILE="nok_list.txt"
SOURCE_IP=$(hostname -I | awk '{print $1}')

TEMP_RESULTS=$(mktemp)
NOK_TEMP=$(mktemp) 

if [[ -z "$INPUT_FILE" || ! -f "$INPUT_FILE" ]]; then
    echo "Usage: $0 <filename>"
    exit 1
fi

echo "Firing parallel connectivity tests... (Max wait time: ~${TIMEOUT}s)" >&2

# 3. Execution Loop (Multi-Threaded)
LAST_COMMENT="General"
REMARK_IDX=1

while IFS= read -r line || [ -n "$line" ]; do
    # Capture the remark/comment and increment index for ordering
    if [[ "$line" =~ ^# ]]; then
        LAST_COMMENT=$(echo "$line" | sed 's/^#//' | xargs)
        REMARK_IDX=$((REMARK_IDX + 1))
        continue
    fi

    # Skip empty lines
    [[ -z "$line" ]] && continue
    
    host_part=$(echo "$line" | cut -d':' -f1 | xargs)
    port_part=$(echo "$line" | cut -d':' -f2)
    IFS=',' read -ra ADDR <<< "$port_part"
    
    for port in "${ADDR[@]}"; do
        port=$(echo "$port" | xargs)
        
        (
            current_remark="$LAST_COMMENT"
            current_idx="$REMARK_IDX"
            current_date=$(date "+%Y-%m-%d %H:%M:%S")
            
            resolved_ip=$(timeout 2s getent hosts "$host_part" | awk '{print $1}' | head -n 1)
            
            if [[ -n "$resolved_ip" && "$resolved_ip" != "$host_part" ]]; then
                display_dest="$host_part ($resolved_ip)"
            else
                display_dest="$host_part"
            fi
            
            if [[ -z "$resolved_ip" ]] && ! [[ "$host_part" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
                status="NOK"
                issue="DNS Resolution Failed"
            else
                output=$(timeout ${TIMEOUT}s nc -zv "$host_part" "$port" 2>&1)
                exit_code=$?
                
                if [ $exit_code -eq 0 ]; then
                    status="OK"
                    issue="Success"
                elif [ $exit_code -eq 124 ]; then
                    status="NOK"
                    issue="Connection Timeout"
                else
                    status="NOK"
                    issue="Refused/Unreachable"
                fi
            fi

            if [[ "$status" == "NOK" ]]; then
                # Store Index | Remark | Host | Port to retain groupings and order
                echo "$current_idx|$current_remark|$host_part|$port" >> "$NOK_TEMP"
            fi

            # STORAGE FORMAT: Remark | Source | Destination | Remark (Display) | Port | Status | Date | Issue
            # Note: We put Remark first so the 'sort' command groups by it.
            # UPDATED: Changed %-40s to %-50s for the destination column
            printf "%s | %-15s | %-50s | %-25s | %-8s | %-6s | %-19s | \"%-25s\"\n" \
                "$current_remark" "$SOURCE_IP" "$display_dest" "$current_remark" "$port" "$status" "$current_date" "$issue" >> "$TEMP_RESULTS"
        ) & 
    done
done < "$INPUT_FILE"

wait

# 4. Generate NOK List File
echo "# Failed Connections from $INPUT_FILE" > "$OUTPUT_NOK_FILE"
echo "" >> "$OUTPUT_NOK_FILE"

if [[ -s "$NOK_TEMP" ]]; then
    awk -F'|' '{
        idx=$1; rem=$2; host=$3; port=$4;
        
        # Track the remark name mapped to its original index
        if (!(idx in rem_map)) {
            rem_map[idx] = rem
        }
        
        # Track the host:port aggregations per index
        key = idx"|"host
        if (key in ports) {
            ports[key] = ports[key] "," port
        } else {
            ports[key] = port
            if (!(idx in host_count)) host_count[idx] = 0
            host_list[idx, ++host_count[idx]] = host
        }
    } END {
        # Find the maximum index to ensure we iterate in the exact original order
        max_idx = 0
        for (i in rem_map) {
            if (i+0 > max_idx) max_idx = i+0
        }
        
        # Print grouped by the original remark order
        for (i=1; i<=max_idx; i++) {
            if (i in rem_map) {
                print "# " rem_map[i]
                for (j=1; j<=host_count[i]; j++) {
                    h = host_list[i, j]
                    print h ":" ports[i"|"h]
                }
                print ""
            }
        }
    }' "$NOK_TEMP" >> "$OUTPUT_NOK_FILE"
fi

# Remove trailing blank line if it exists
sed -i '$ d' "$OUTPUT_NOK_FILE"

# 5. Final Output Generation
echo -e "\nAll tests complete. Grouped by Remark:\n" >&2

# UPDATED: Changed %-40s to %-50s in the table header
printf "%-15s | %-50s | %-25s | %-8s | %-6s | %-19s | %-25s\n" \
    "SOURCE IP" "DESTINATION (RESOLVED IP)" "GROUP/REMARK" "PORT" "STATUS" "DATE" "\"REMARK/ISSUE\""
    
# UPDATED: Extended the separator line length from 175 to 185 to match the new column width
printf "%0.s-" {1..185}
echo

# Print Sorted Results (Sorts by the hidden first column: Remark)
# Then we use cut to hide that first sorting column from the user output.
sort "$TEMP_RESULTS" | cut -d'|' -f2-

# 6. Summary
TOTAL_TESTS=$(wc -l < "$TEMP_RESULTS")
NOK_COUNT=$(grep -E -c "\|\s*NOK\s*\|" "$TEMP_RESULTS" || true)
OK_COUNT=$((TOTAL_TESTS - NOK_COUNT))

# UPDATED: Extended summary separators
echo "-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------"
printf "SUMMARY: %d out of %d connections are NOK (%d OK)\n" "$NOK_COUNT" "$TOTAL_TESTS" "$OK_COUNT"
echo "-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------"

# Cleanup
rm "$TEMP_RESULTS" "$NOK_TEMP"