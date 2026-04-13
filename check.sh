#!/bin/bash

# ==============================================================================
# Connectivity Test Strategy Script (Ultra-Fast Parallel Edition)
# ==============================================================================

# 1. Dependency Check
for cmd in nc getent awk cut printf timeout sort wc grep; do
    if ! command -v $cmd &> /dev/null; then
        echo "Error: Required command '$cmd' is not installed."
        exit 1
    fi
done

# 2. Configuration & Arguments
INPUT_FILE=$1
TIMEOUT=3
SOURCE_IP=$(hostname -I | awk '{print $1}')
TEMP_RESULTS=$(mktemp)

if [[ -z "$INPUT_FILE" || ! -f "$INPUT_FILE" ]]; then
    echo "Usage: $0 <filename>"
    exit 1
fi

echo "Firing parallel connectivity tests... (Max wait time: ~${TIMEOUT}s)" >&2

# 3. Execution Loop (Multi-Threaded)
while IFS= read -r line || [ -n "$line" ]; do
    [[ -z "$line" || "$line" =~ ^# ]] && continue
    
    host_part=$(echo "$line" | cut -d':' -f1 | xargs)
    port_part=$(echo "$line" | cut -d':' -f2)
    IFS=',' read -ra ADDR <<< "$port_part"
    
    for port in "${ADDR[@]}"; do
        port=$(echo "$port" | xargs)
        
        # ---------------------------------------------------------
        # START BACKGROUND JOB: Everything inside ( ) & runs in parallel
        # ---------------------------------------------------------
        (
            current_date=$(date "+%Y-%m-%d %H:%M:%S")
            printf "  -> Spawning test for %s on port %s...\n" "$host_part" "$port" >&2
            
            # Resolve DNS inside the thread so slow DNS doesn't block other tests
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
                    issue="Connection Timeout (Firewall Drop)"
                else
                    status="NOK"
                    if [[ "$output" == *"refused"* ]]; then
                        issue="Connection Refused (Service Down)"
                    else
                        issue="Network Unreachable"
                    fi
                fi
            fi

            # Atomically write to the temp file
            printf "%s | %-15s | %-60s | %-8s | %-6s | %-19s | %-25s\n" "$status" "$SOURCE_IP" "$display_dest" "$port" "$status" "$current_date" "$issue" >> "$TEMP_RESULTS"
        ) & 
        # ---------------------------------------------------------
        # END BACKGROUND JOB
        # ---------------------------------------------------------
    done
done < "$INPUT_FILE"

# Wait for all background jobs to finish before proceeding
wait

# 4. Final Output Generation
echo -e "\nAll tests complete. Generating report...\n" >&2

printf "%-15s | %-60s | %-8s | %-6s | %-19s | %-25s\n" "SOURCE IP" "DESTINATION (RESOLVED IP)" "PORT" "STATUS" "DATE" "REMARK/ISSUE"
printf "%0.s-" {1..150}
echo

# Print Sorted Results
sort "$TEMP_RESULTS" | cut -d'|' -f2-

# 5. Dynamic Summary Calculation
TOTAL_TESTS=$(wc -l < "$TEMP_RESULTS")
# Ensure grep doesn't fail the script if 0 NOKs are found
NOK_COUNT=$(grep -c "^NOK" "$TEMP_RESULTS" || true)
OK_COUNT=$((TOTAL_TESTS - NOK_COUNT))

echo "------------------------------------------------------------------------------------------------------------------------------------------------------"
printf "SUMMARY: %d out of %d connections are NOK (%d OK)\n" "$NOK_COUNT" "$TOTAL_TESTS" "$OK_COUNT"
echo "------------------------------------------------------------------------------------------------------------------------------------------------------"

# Cleanup
rm "$TEMP_RESULTS"