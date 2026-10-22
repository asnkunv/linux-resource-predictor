#!/usr/bin/env bash
# generate_load.sh: run ONE load event at a time, with idle baseline periods between them.
# Runs forever as the systemd service lrp-loadgen.

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOAD_LOG="$PROJECT_DIR/logs/load_events.log"
DISK_DIR="$PROJECT_DIR/tmp_test"
mkdir -p "$PROJECT_DIR/logs" "$DISK_DIR"
CORES=$(nproc)

# Idle baseline between events, in seconds (lower = more events in the data)
IDLE_MIN=300
IDLE_MAX=720
# Skip an event if less than this percent of RAM is available
MIN_AVAIL_PCT=40

log() { echo "$(date '+%Y-%m-%d %H:%M:%S') $*" >> "$LOAD_LOG"; }

# rand_between MIN MAX: random integer from MIN to MAX
rand_between() { echo $(( $1 + RANDOM % ($2 - $1 + 1) )); }

# mem_ok: true if enough RAM is available to start an event safely
mem_ok() {
  awk -v min="$MIN_AVAIL_PCT" '/MemTotal/ {t=$2} /MemAvailable/ {a=$2} END {exit !(a * 100 / t >= min)}' /proc/meminfo
}

# ramp_steps START_MIN START_MAX INC_MIN INC_MAX CAP STEPS_MIN STEPS_MAX
# Prints a random list of increasing values, each bigger than the previous
ramp_steps() {
  local val steps i prev=0
  val=$(rand_between "$1" "$2")
  steps=$(rand_between "$6" "$7")
  for ((i = 0; i < steps; i++)); do
    [ "$val" -gt "$5" ] && val=$5
    [ "$val" -le "$prev" ] && break
    echo "$val"
    prev=$val
    val=$((val + $(rand_between "$3" "$4")))
  done
}

# CPU load that ramps up in random steps, then drops
cpu_ramp() {
  local pct
  log "START cpu_ramp"
  # shellcheck disable=SC2046
  for pct in $(ramp_steps 15 40 10 30 100 2 4); do
    log "  cpu step ${pct}%"
    stress-ng --cpu "$CORES" --cpu-load "$pct" --timeout "$(rand_between 40 70)s" -q
  done
  log "END cpu_ramp"
}

# RAM load that grows in random steps (percent of available memory)
mem_ramp() {
  local pct
  log "START mem_ramp"
  # shellcheck disable=SC2046
  for pct in $(ramp_steps 15 30 8 20 70 2 4); do
    log "  mem step ${pct}%"
    stress-ng --vm 1 --vm-bytes "${pct}%" --timeout "$(rand_between 40 70)s" -q
  done
  log "END mem_ramp"
}

# CPU and RAM together (rare on purpose)
mixed() {
  local cpu mem
  cpu=$(rand_between 60 95)
  mem=$(rand_between 20 40)
  log "START mixed cpu=${cpu}% mem=${mem}%"
  stress-ng --cpu "$CORES" --cpu-load "$cpu" --vm 1 --vm-bytes "${mem}%" \
    --timeout "$(rand_between 90 210)s" -q
  log "END mixed"
}

# Short full-speed CPU burst with no warning
burst() {
  log "START burst"
  stress-ng --cpu "$CORES" --timeout "$(rand_between 20 60)s" -q
  log "END burst"
}

# Disk writes in a project temp folder, cleaned up afterwards
disk_io() {
  local mb
  mb=$(rand_between 256 768)
  log "START disk_io ${mb}MB"
  stress-ng --hdd 1 --hdd-bytes "${mb}M" --temp-path "$DISK_DIR" \
    --timeout "$(rand_between 60 120)s" -q
  rm -rf "${DISK_DIR:?}"/*
  log "END disk_io"
}

# Traffic to the test web app (CPU load coming from a real service)
web_traffic() {
  local conc dur
  if ! curl -s -o /dev/null --max-time 2 http://127.0.0.1:8080/health; then
    log "SKIP web_traffic (web app not running)"
    return
  fi
  conc=$(rand_between 1 4)
  dur=$(rand_between 120 240)
  log "START web_traffic c=${conc} ${dur}s"
  ab -q -t "$dur" -n 10000000 -c "$conc" http://127.0.0.1:8080/work > /dev/null 2>&1
  log "END web_traffic"
}

# Fake backup: gzip of /usr, output thrown away (CPU plus disk reads)
backup() {
  log "START backup"
  timeout "$(rand_between 120 240)" tar czf - /usr 2>/dev/null > /dev/null
  log "END backup"
}

# Slow memory leak (the Python script grows memory, then exits and frees it)
leak() {
  log "START leak"
  python3 "$PROJECT_DIR/workloads/leaky_app.py"
  log "END leak"
}

# Weighted list: an event listed twice happens twice as often
EVENTS=(cpu_ramp cpu_ramp mem_ramp mem_ramp web_traffic web_traffic leak leak backup burst disk_io mixed)

log "generate_load started"
while true; do
  sleep "$(rand_between "$IDLE_MIN" "$IDLE_MAX")"
  if mem_ok; then
    "${EVENTS[RANDOM % ${#EVENTS[@]}]}"
  else
    log "SKIP event (low available memory)"
  fi
done