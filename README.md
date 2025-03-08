# check_cmd_wrapper
Script that allows you to run any command and massage it's output into nagios-style output


Example usages:
````
➜  /tmp ./check_cmd_wrapper.py \
  --command=curl \
  --command-args="-s -w \"size_download:%{size_download}\ntime_total:%{time_total}\nhttp_code:%{http_code}\n\" -o /dev/null https://www.google.com" \ 
  --command-name=WEBSITE_CHECK \
  --timeout=30 \
  --time-warn=2 \
  --time-crit=5 \
  --label name=page_size --label regex="size_download:(\d+)" --label mode=parse --label warn=1000000 --label crit=2000000 \
  --label name=response_time --label regex="time_total:([0-9.]+)" --label mode=parse --label warn=1 --label crit=3 \
  --label name=http_code --label regex="http_code:(\d+)" --label mode=parse --label warn=0 --label crit=0 \
  --label name=http_error --label regex="http_code:([45]\d\d)" --label mode=nomatch --label severity=2 --label message="HTTP error code detected"
WEBSITE_CHECK OK -  | page_size=18023 response_time=0.209746 http_code=200 exec_time=0.224s

➜  /tmp ./check_cmd_wrapper.py \
  --command=curl \
  --command-args="-s -w \"size_download:%{size_download}\ntime_total:%{time_total}\nhttp_code:%{http_code}\n\" -o /dev/null https://httpstat.us/400" \
  --command-name=WEBSITE_CHECK \
  --timeout=30 \
  --time-warn=2 \
  --time-crit=5 \
  --label name=page_size --label regex="size_download:(\d+)" --label mode=parse --label warn=1000000 --label crit=2000000 \
  --label name=response_time --label regex="time_total:([0-9.]+)" --label mode=parse --label warn=1 --label crit=3 \
  --label name=http_code --label regex="http_code:(\d+)" --label mode=parse --label warn=0 --label crit=0 \
  --label name=http_error --label regex="http_code:([45]\d\d)" --label mode=nomatch --label severity=2 --label message="HTTP error code detected"
WEBSITE_CHECK CRITICAL - HTTP error code detected | page_size=15 response_time=0.441797 http_code=400 exec_time=0.456s

➜  /tmp ./check_cmd_wrapper.py \
  --command=curl \
  --command-args="-s -w \"size_download:%{size_download}\ntime_total:%{time_total}\nhttp_code:%{http_code}\n\" -o /dev/null https://httpstat.us/401" \ 
  --command-name=WEBSITE_CHECK \
  --timeout=30 \
  --time-warn=2 \
  --time-crit=5 \
  --label name=page_size --label regex="size_download:(\d+)" --label mode=parse --label warn=1000000 --label crit=2000000 \
  --label name=response_time --label regex="time_total:([0-9.]+)" --label mode=parse --label warn=1 --label crit=3 \
  --label name=http_code --label regex="http_code:(\d+)" --label mode=parse --label warn=0 --label crit=0 \
  --label name=http_error --label regex="http_code:([45]\d\d)" --label mode=nomatch --label severity=2 --label message="HTTP error code detected"
WEBSITE_CHECK CRITICAL - HTTP error code detected | page_size=16 response_time=0.242121 http_code=401 exec_time=0.255s
````
