#!/usr/bin/env bash
# collect_metrics.sh: append one row of system metrics to data/metrics.csv
export LC_ALL=C

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_FILE="$PROJECT_DIR/data/metrics.csv"

mkdir -p "$(dirname "$OUT_FILE")"

# Write the header only if the file is new or empty
if [ ! -s "$OUT_FILE" ]; then
  echo "timestamp,cpu_percent,iowait_percent,ram_percent,swap_percent,disk_percent,load1,load5,load15,process_count,top_cpu_proc,top_cpu_pct,top_mem_proc,top_mem_pct" > "$OUT_FILE"
fi

# CPU and iowait: two samples of /proc/stat one second apart
read -r _ u1 n1 s1 i1 w1 q1 sq1 st1 _ < /proc/stat
sleep 1
read -r _ u2 n2 s2 i2 w2 q2 sq2 st2 _ < /proc/stat
idle1=$((i1 + w1)); idle2=$((i2 + w2))
total1=$((u1 + n1 + s1 + i1 + w1 + q1 + sq1 + st1))
total2=$((u2 + n2 + s2 + i2 + w2 + q2 + sq2 + st2))
dt=$((total2 - total1)); di=$((idle2 - idle1)); dw=$((w2 - w1))
cpu=$(awk -v dt="$dt" -v di="$di" 'BEGIN { if (dt > 0) printf "%.1f", (dt - di) * 100 / dt; else print 0 }')
iowait=$(awk -v dt="$dt" -v dw="$dw" 'BEGIN { if (dt > 0) printf "%.1f", dw * 100 / dt; else print 0 }')

# RAM: used = total minus available
ram=$(awk '/MemTotal/ {t=$2} /MemAvailable/ {a=$2} END {printf "%.1f", (t - a) * 100 / t}' /proc/meminfo)

# Swap: percent used, 0 if no swap exists
swap=$(awk '/SwapTotal/ {t=$2} /SwapFree/ {f=$2} END { if (t > 0) printf "%.1f", (t - f) * 100 / t; else print "0.0" }' /proc/meminfo)

# Disk usage of the root filesystem
disk=$(df / | awk 'NR==2 {gsub("%", "", $5); print $5}')

# Load averages and process count
read -r l1 l5 l15 _ < /proc/loadavg
procs=$(ps -e --no-headers | wc -l)

# Top process sorted by a column (pcpu or pmem), prints: name,cpu,mem
top_by() {
  ps -eo comm=,pcpu=,pmem= --sort=-"$1" | awk '
    $1 != "ps" && $1 != "awk" {
      n = NF - 2; name = $1
      for (i = 2; i <= n; i++) name = name "_" $i
      gsub(",", "_", name)
      print name "," $(NF-1) "," $NF
      exit
    }'
}
top_cpu=$(top_by pcpu | awk -F, '{print $1","$2}')
top_mem=$(top_by pmem | awk -F, '{print $1","$3}')

echo "$(date '+%Y-%m-%d %H:%M:%S'),$cpu,$iowait,$ram,$swap,$disk,$l1,$l5,$l15,$procs,$top_cpu,$top_mem" >> "$OUT_FILE"