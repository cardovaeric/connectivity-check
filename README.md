# Connectivity Check Script

A Bash script to check network connectivity to various hosts and ports, useful for troubleshooting network issues, firewall configurations, and service availability.

## Features

- **DNS Resolution**: Automatically resolves hostnames to IP addresses
- **Multi-Port Support**: Test multiple ports per host (comma-separated)
- **Timeout Configuration**: Configurable connection timeout (default: 2 seconds)
- **Detailed Reporting**: Provides status, timestamps, and diagnostic information
- **Source IP Detection**: Shows the local source IP used for connections

## Usage

```bash
./check.sh <input_file>
```

### Parameters

- `input_file`: Path to a text file containing host:port combinations (one per line)

### Input File Format

Each line in the input file should follow this format:
```
hostname_or_ip:port1,port2,port3
```

Examples:
```
example.com:80,443
192.168.1.1:22
api.example.com:8080,8443
```

Lines starting with `#` are treated as comments and ignored.
Empty lines are skipped.

### Sample Input File

See `ip_list.txt` for a sample input file containing various endpoints including:
- Solace Cloud messaging endpoints
- Radius servers
- MFT servers
- API gateways
- Kafka brokers

## Output Format

The script generates a formatted table with the following columns:

- **SOURCE IP**: Local IP address used for connections
- **DESTINATION**: Hostname/IP with resolved IP in parentheses (if applicable)
- **PORT**: Port number being tested
- **STATUS**: OK (connection successful) or NOK (connection failed)
- **DATE**: Timestamp of the test
- **REMARK/ISSUE**: Diagnostic information or error description

## Status Codes and Issues

- **OK**: Connection successful
- **NOK** with issues:
  - DNS Resolution Failed: Hostname could not be resolved
  - Connection Timeout: Connection attempt timed out (possible firewall)
  - Connection Refused: Connection rejected by remote host (service may be down)
  - Network Unreachable: Network routing issue

## Requirements

- Bash shell
- `nc` (netcat) command
- `getent` command (for DNS resolution)
- `hostname` command

## Example Output

```
SOURCE IP       | DESTINATION (RESOLVED IP)                    | PORT    | STATUS | DATE                | REMARK/ISSUE
--------------------------------------------------------------------------------------------------------------
192.168.1.100   | example.com (93.184.216.34)                  | 80      | OK     | 2024-01-15 10:30:45 | Success
192.168.1.100   | api.example.com (10.0.0.1)                   | 8080    | NOK    | 2024-01-15 10:30:46 | Connection Refused
```

## Troubleshooting

- Ensure the script has execute permissions: `chmod +x check.sh`
- Check that `nc` (netcat) is installed on your system
- Verify network connectivity and firewall rules
- For DNS issues, ensure proper DNS configuration
- Timeout value can be adjusted in the script for slower networks