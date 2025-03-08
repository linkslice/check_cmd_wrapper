#!/usr/bin/env python3
"""
Patched version of check_nagios_wrapper.py to remove the "time" label restriction
Original comments preserved
"""

import sys
import os
import re
import subprocess
import time
import argparse
from enum import Enum

# Define Nagios status codes
class NagiosStatus(Enum):
    OK = 0
    WARNING = 1
    CRITICAL = 2
    UNKNOWN = 3

# Version info
VERSION = '1.9.1'  # Bumped version to indicate the patch
PROGNAME = os.path.basename(sys.argv[0])

class NagiosPlugin:
    """Python equivalent of the Perl Nagios::Plugin module"""
    
    def __init__(self, usage="", version="", blurb="", timeout=30):
        self.version = version
        self.shortname = PROGNAME.upper()
        self.perfdata = []
        self.messages = {
            NagiosStatus.OK: [],
            NagiosStatus.WARNING: [],
            NagiosStatus.CRITICAL: [],
            NagiosStatus.UNKNOWN: []
        }
        self.warning_threshold = None
        self.critical_threshold = None
        
    def set_shortname(self, name):
        """Set the shortname used in output"""
        self.shortname = name.upper()
        
    def add_perfdata(self, label="", value="", uom="", warning="", critical=""):
        """Add performance data"""
        perf_string = f"{label}={value}"
        if uom:
            perf_string += uom
        if warning:
            perf_string += f";{warning}"
            if critical:
                perf_string += f";{critical}"
        self.perfdata.append(perf_string)
        
    def add_message(self, status, message):
        """Add a message with a specific status level"""
        if isinstance(status, int):
            status = list(NagiosStatus)[status]
        self.messages[status].append(message)
        
    def set_thresholds(self, warning=None, critical=None):
        """Set warning and critical thresholds"""
        if warning is not None:
            self.warning_threshold = str(warning)
        if critical is not None:
            self.critical_threshold = str(critical)
            
    def check_threshold(self, value):
        """Check if a value exceeds thresholds"""
        # Only perform checks if thresholds are explicitly set
        if self.critical_threshold and self._is_threshold_exceeded(value, self.critical_threshold):
            return NagiosStatus.CRITICAL
        elif self.warning_threshold and self._is_threshold_exceeded(value, self.warning_threshold):
            return NagiosStatus.WARNING
        return NagiosStatus.OK
    
    def _is_threshold_exceeded(self, value, threshold):
        """Check if value exceeds threshold (supports Nagios threshold format)"""
        try:
            value = float(value)
        except (ValueError, TypeError):
            # If value can't be converted to float, can't compare
            return False
        
        # Handle range format like Nagios (@range, ~:range, etc.)
        if threshold.startswith('@'):
            # Inside range is bad
            min_val, max_val = self._parse_range(threshold[1:])
            return min_val <= value <= max_val
        elif ':' in threshold:
            # Outside range is bad
            min_val, max_val = self._parse_range(threshold)
            return value < min_val or value > max_val
        else:
            # Simple threshold
            try:
                return value > float(threshold)
            except (ValueError, TypeError):
                # If threshold can't be converted to float, can't compare
                return False
    
    def _parse_range(self, range_str):
        """Parse a range string like '10:20' into min and max values"""
        if ':' in range_str:
            parts = range_str.split(':')
            min_val = float(parts[0]) if parts[0] else float('-inf')
            max_val = float(parts[1]) if parts[1] else float('inf')
        else:
            min_val = 0
            max_val = float(range_str)
        return min_val, max_val
            
    def check_messages(self, join_all=" "):
        """Check all messages and return the highest severity"""
        # Find highest severity
        status = NagiosStatus.OK
        for s in [NagiosStatus.CRITICAL, NagiosStatus.WARNING, NagiosStatus.UNKNOWN, NagiosStatus.OK]:
            if self.messages[s]:
                status = s
                break
        
        # Combine messages for output
        messages = []
        for s in [NagiosStatus.CRITICAL, NagiosStatus.WARNING, NagiosStatus.UNKNOWN, NagiosStatus.OK]:
            if self.messages[s]:
                messages.extend(self.messages[s])
        
        return status, join_all.join(messages) if messages else ""
    
    def nagios_exit(self, status, message=""):
        """Exit with Nagios status and message"""
        if isinstance(status, NagiosStatus):
            exit_code = status.value
            status_text = status.name
        else:
            exit_code = status
            status_text = list(NagiosStatus)[exit_code].name
            
        # Format performance data
        perfdata_str = " ".join(self.perfdata)
        if perfdata_str:
            output = f"{self.shortname} {status_text} - {message} | {perfdata_str}"
        else:
            output = f"{self.shortname} {status_text} - {message}"
            
        print(output)
        sys.exit(exit_code)
        
    def nagios_die(self, message):
        """Exit with UNKNOWN status and message"""
        self.nagios_exit(NagiosStatus.UNKNOWN, message)


def click_stopwatch():
    """Get current time in seconds with microsecond precision"""
    return time.time()


def parse_arguments():
    """Parse command line arguments"""
    parser = argparse.ArgumentParser(
        description='Wrapper for converting commands to Nagios plugins',
        add_help=False  # We'll add our own help
    )
    
    # Basic options
    parser.add_argument('--help', action='store_true', help='Display help message')
    parser.add_argument('--man', action='store_true', help='Display manual')
    parser.add_argument('--verbose', action='store_true', help='Enable verbose output')
    parser.add_argument('--version', action='store_true', help='Display version')
    
    # Command options
    parser.add_argument('--command', type=str, help='Command to execute')
    parser.add_argument('--command-prefix', type=str, default='', help='Prefix for command')
    parser.add_argument('--command-args', type=str, default='', help='Arguments for command')
    parser.add_argument('--command-name', type=str, default='', help='Override command name in output')
    parser.add_argument('--ignore-exit-code', action='store_true', help='Ignore non-zero exit codes')
    
    # Timing options
    parser.add_argument('--timeout', type=int, default=30, help='Timeout in seconds')
    parser.add_argument('--time-warn', type=float, default=0, help='Warning threshold for execution time')
    parser.add_argument('--time-crit', type=float, default=0, help='Critical threshold for execution time')
    
    # We'll handle label parsing separately to support multiple labels
    args, remaining = parser.parse_known_args()
    
    # Display help or version if requested
    if args.help:
        display_help()
        sys.exit(0)
    if args.man:
        display_manual()
        sys.exit(0)
    if args.version:
        print(f"[INFO] {PROGNAME} version: {VERSION}")
        sys.exit(1)
        
    # Parse labels
    labels = parse_labels(remaining)
    
    return args, labels


def parse_labels(args):
    """Parse label arguments into structured data"""
    labels = {
        'name': [],
        'regex': [],
        'crit': [],
        'warn': [],
        'mode': [],
        'message': [],
        'severity': []
    }
    
    current_label_index = -1
    
    i = 0
    while i < len(args):
        if args[i] == '--label':
            if i + 1 >= len(args):
                print("Error: --label requires a key=value argument")
                sys.exit(2)
                
            # Parse key=value
            if '=' not in args[i+1]:
                print(f"Error: Invalid label format: {args[i+1]}")
                sys.exit(2)
                
            key, value = args[i+1].split('=', 1)
            
            if key == 'name':
                # New label
                labels['name'].append(value)
                labels['regex'].append(0)
                labels['crit'].append(0)
                labels['warn'].append(0)
                labels['mode'].append('parse')
                labels['message'].append(0)
                labels['severity'].append(NagiosStatus.CRITICAL.value)
                current_label_index = len(labels['name']) - 1
            elif current_label_index >= 0:
                # Update existing label
                labels[key][current_label_index] = value
            else:
                print("Error: Each set of label parameters must start with --label name=NAME")
                sys.exit(2)
                
            i += 2
        else:
            i += 1
            
    return labels


def display_help():
    """Display brief help message"""
    help_text = f"""
    {PROGNAME} - Wrap a normal command to be a nagios plugin.

    SYNOPSIS
    {PROGNAME} [--help] [--man] [--verbose] --command=COMMAND [--command-prefix=PREFIX] 
               [--command-args=ARGS] [--command-name=NAME] [--ignore-exit-code] 
               [--timeout=TIMEOUT] [--time-warn=TIMEWARN] [--time-crit=TIMECRIT] 
               --label name=LABELNAME --label regex=LABELREGEX --label mode=match|parse|count 
               --label severity=0|1|2 --label message=LABELMSG --label warn=LABELWARN 
               --label crit=LABELCRIT ...

    Use --man for full documentation.
    """
    print(help_text)


def display_manual():
    """Display full manual"""
    manual_text = f"""
    NAME
        {PROGNAME} - Wrap a normal command to be a nagios plugin.

    SYNOPSIS
        {PROGNAME} [--help] [--man] [--verbose] --command=COMMAND [--command-prefix=PREFIX] 
                   [--command-args=ARGS] [--command-name=NAME] [--ignore-exit-code] 
                   [--timeout=TIMEOUT] [--time-warn=TIMEWARN] [--time-crit=TIMECRIT] 
                   --label name=LABELNAME --label regex=LABELREGEX --label mode=match|parse|count 
                   --label severity=0|1|2 --label message=LABELMSG --label warn=LABELWARN 
                   --label crit=LABELCRIT ...

    DESCRIPTION
        This script is intended to be used as a wrapper for running a script or command, 
        parsing the data values it receives, and outputting properly-formatted 
        Nagios-style health messages.

    OPTIONS
        --help
            Print a brief help message and exits.

        --man
            Prints the manual page and exits.

        --verbose
            Enable verbose output for troubleshooting.

        --command=COMMAND
            The command to run (do not put arguments here, specify them with --command-args).

        --command-prefix=PREFIX
            The prefix to prepend to the command (if any).

        --command-args=ARGS
            The arguments to pass to COMMAND.

        --command-name=NAME
            Override the automatic shortname detection.

        --ignore-exit-code
            Suppresses the message that is displayed when the command exits with a non-zero exit code.

        --timeout=TIMEOUT (Default is 30.)
            The amount of time to wait (in seconds) for the script to execute.

        --time-warn=TIMEWARN & --time-crit=TIMECRIT
            Script execution time thresholds.

    LABELS
        An arbitrary number of labels can be specified to parse out or match various data points.
        Each label MUST consist of at least a name and a regex.

        --label name=NAME
            Name of the label used in performance data output.

        --label mode=MODE
            Mode can be "match" (or "m"), "nomatch" (or "n"), "parse" (or "p"), or "count" (or "c").

        --label regex=REGEX
            The perl-compatible regular expression.

        --label severity=SEVERITY
            Severity level: 0 (OK), 1 (WARNING), 2 (CRITICAL).

        --label message=MESSAGE
            Message to print if the label does not match.

        --label warn=WARN & --label crit=CRIT
            Warning and critical thresholds for label values.
            
    NOTE
        This version has been modified to allow using "time" in label names.
    """
    print(manual_text)


def validate_labels(p, labels):
    """Validate label options"""
    for i in range(len(labels['name'])):
        # Check mode
        mode = labels['mode'][i]
        if not re.match(r'^(match|nomatch|parse|count|m|n|p|c)$', mode):
            p.nagios_die(f" invalid mode specified on label {labels['name'][i]} ({mode})")
        
        # Check regex presence
        if labels['regex'][i] == "0":
            p.nagios_die(f" no regex specified on label {labels['name'][i]}")
            
        # Check for capture groups in parse mode
        if (mode in ('parse', 'p')) and not re.search(r'\(|\)', labels['regex'][i]):
            p.nagios_die(f" invalid regex specified on label {labels['name'][i]} ({labels['regex'][i]}). No groups specified in regex.")
            
        # Check severity
        if not re.match(r'^[0123]$', str(labels['severity'][i])):
            p.nagios_die(f" invalid severity specified on label {labels['name'][i]} ({labels['severity'][i]})")
            
        # Removed the time label name restriction
        # Now only checking for exact match with the execution time label
        if labels['name'][i] == "exec_time":  # Changed from 'time' to 'exec_time'
            p.nagios_die(f" invalid (reserved) label name used: {labels['name'][i]}")


def main():
    """Main function"""
    # Parse arguments
    args, labels = parse_arguments()
    
    # Create plugin instance
    p = NagiosPlugin(version=VERSION)
    
    # Required variables
    if not args.command:
        p.nagios_die(" a command was not specified. (Seek --help)")
        
    # Validate labels
    validate_labels(p, labels)
    
    # Make sure prefix ends with /
    command_prefix = args.command_prefix
    if command_prefix and not command_prefix.endswith('/'):
        command_prefix += '/'
        
    # Build full command
    the_command = f"{command_prefix}{args.command} {args.command_args}"
    
    # Set shortname
    if args.command_name:
        p.set_shortname(args.command_name)
    else:
        shortname = os.path.basename(f"{command_prefix}{args.command}").upper()
        if ' ' in shortname or '.' in shortname:
            match = re.match(r'(.*?)[\s\.]', shortname)
            if match:
                p.set_shortname(match.group(1))
            else:
                p.set_shortname(shortname)
        else:
            p.set_shortname(shortname)
    
    # Start the test
    time_start = click_stopwatch()
    
    if args.verbose:
        print(f"[INFO] Running command: {the_command}")
    
    try:
        # Set timeout
        process = subprocess.Popen(
            the_command,
            shell=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            universal_newlines=True
        )
        
        result = ""
        # Read output with timeout handling
        try:
            stdout, _ = process.communicate(timeout=args.timeout)
            result = stdout
            exitcode = process.returncode
        except subprocess.TimeoutExpired:
            process.kill()
            p.nagios_die("timeout")
    
    except Exception as e:
        p.nagios_die(f"Error executing command: {str(e)}")
    
    # Time's up
    time_end = click_stopwatch()
    total_time = round(time_end - time_start, 3)
    
    if args.verbose:
        print(f"[INFO] Command output: {result} exit code: {exitcode}")
        
    # Check exit code
    if not args.ignore_exit_code and exitcode != 0:
        p.add_message(NagiosStatus.WARNING, f" command {the_command} exited with non-zero status ({exitcode}).")
        
    # Iterate through labels
    for i in range(len(labels['name'])):
        labelname = labels['name'][i]
        labelregex = labels['regex'][i]
        labelcrit = labels['crit'][i]
        labelwarn = labels['warn'][i]
        labelmode = labels['mode'][i]
        labelmessage = labels['message'][i]
        labelseverity = int(labels['severity'][i])
        
        if args.verbose:
            print(f"[INFO] Processing label: {labelname}")
            
        # Run regex
        matches = re.findall(labelregex, result, re.MULTILINE)
        
        if matches:
            # Matched!
            labelvalue = matches[0]
            if isinstance(labelvalue, tuple) and len(labelvalue) > 0:
                # Handle groups in regex
                labelvalue = labelvalue[0]
                
            if args.verbose and len(matches) > 1:
                for match in matches:
                    if isinstance(match, tuple) and len(match) > 0:
                        print(f"[INFO] Result iteration: {match[0]}")
                    else:
                        print(f"[INFO] Result iteration: {match}")
            
            # Process according to mode
            if labelmode in ('parse', 'p'):
                # Parse mode
                if args.verbose:
                    print(f"[INFO] Data point ({labelname}) found. value={labelvalue}")
                
                # Add performance data
                p.add_perfdata(label=labelname, value=labelvalue)
                
                # Check thresholds
                if labelwarn != "0":
                    p.set_thresholds(warning=labelwarn)
                if labelcrit != "0":
                    p.set_thresholds(critical=labelcrit)
                
                if (labelwarn != "0" or labelcrit != "0"):
                    threshold_status = p.check_threshold(labelvalue)
                    if threshold_status == NagiosStatus.WARNING:
                        p.add_message(NagiosStatus.WARNING, f" {labelname} ({labelvalue}) exceeded warning threshold ({labelwarn})")
                    elif threshold_status == NagiosStatus.CRITICAL:
                        p.add_message(NagiosStatus.CRITICAL, f" {labelname} ({labelvalue}) exceeded critical threshold ({labelcrit})")
            
            elif labelmode in ('match', 'm'):
                # Match mode
                if args.verbose:
                    print(f"[INFO] Data point ({labelname}) matched successfully")
            
            elif labelmode in ('nomatch', 'n'):
                # Nomatch mode - this is a problem because it DID match but shouldn't
                if args.verbose:
                    print(f"[WARN] Data point ({labelname}) matched")
                
                if labelmessage != "0":
                    p.add_message(labelseverity, labelmessage)
                else:
                    p.add_message(labelseverity, f" label {labelname} found.")
            
            elif labelmode in ('count', 'c'):
                # Count mode
                matchcount = len(matches)
                if args.verbose:
                    print(f"[INFO] Data point ({labelname}) matched {matchcount} times.")
                
                # Add performance data
                p.add_perfdata(label=labelname, value=matchcount)
                
                # Check thresholds
                if labelwarn != "0":
                    p.set_thresholds(warning=labelwarn)
                if labelcrit != "0":
                    p.set_thresholds(critical=labelcrit)
                
                if (labelwarn != "0" or labelcrit != "0"):
                    threshold_status = p.check_threshold(matchcount)
                    if threshold_status == NagiosStatus.WARNING:
                        p.add_message(NagiosStatus.WARNING, f" {labelname} ({matchcount}) exceeded warning threshold ({labelwarn})")
                    elif threshold_status == NagiosStatus.CRITICAL:
                        p.add_message(NagiosStatus.CRITICAL, f" {labelname} ({matchcount}) exceeded critical threshold ({labelcrit})")
                        
        else:
            # No match found
            if labelmode in ('nomatch', 'n'):
                # Nomatch mode - no match is good
                if args.verbose:
                    print(f"[INFO] Data point ({labelname}) not found.")
            else:
                # Other modes - no match is bad
                if args.verbose:
                    print(f"[WARN] Data point ({labelname}) cannot be parsed.")
                
                if labelmessage != "0":
                    p.add_message(labelseverity, labelmessage)
                else:
                    p.add_message(labelseverity, f" label {labelname} not found.")
    
    # Add timing data
    p.add_perfdata(label="exec_time", value=f"{total_time:.3f}", uom="s")  # Changed from 'time' to 'exec_time'
    
    # Check time thresholds
    if args.time_warn != 0:
        p.set_thresholds(warning=args.time_warn)
    if args.time_crit != 0:
        p.set_thresholds(critical=args.time_crit)
        
    if args.time_crit > 0 or args.time_warn > 0:
        threshold_status = p.check_threshold(total_time)
        if threshold_status == NagiosStatus.WARNING:
            p.add_message(NagiosStatus.WARNING, f" total command time ({total_time}) exceeded warning threshold ({args.time_warn})")
        elif threshold_status == NagiosStatus.CRITICAL:
            p.add_message(NagiosStatus.CRITICAL, f" total command time ({total_time}) exceeded critical threshold ({args.time_crit})")
    
    # Exit with status and messages
    status, message = p.check_messages(join_all=' ')
    p.nagios_exit(status, message)


if __name__ == "__main__":
    main()
