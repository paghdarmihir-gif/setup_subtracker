#!/usr/bin/env bash
# L29 Subscription Tracker - setup script
# Student: PAGHADAR MIHIR VIKESHKUMAR | Roll: G26 | Division: G
set -Eeuo pipefail

P="${HOME}/linux_project/subtracker"

if [[ -e "$P" ]]; then
    echo "ERROR: $P already exists."
    echo "To protect your data, this setup will not overwrite it."
    echo "Rename or back up the existing folder, then run this script again."
    exit 1
fi

mkdir -p "$P"/{lib,data,reports,backups,logs}
cd "$P"

cat > data/subs.csv <<'CSV'
name,cost,cycle,renew_date
Spotify,119,monthly,2026-11-03
Prime Video,1499,yearly,2027-02-14
Netflix,649,monthly,2026-11-05
YouTube Premium,129,monthly,2026-11-06
Google One,130,monthly,2026-11-12
Adobe Creative Cloud,1999,monthly,2026-11-15
Gym,1200,monthly,2026-11-01
Microsoft 365,4899,yearly,2027-01-10
Canva Pro,499,monthly,2026-11-20
Dropbox,1199,yearly,2027-03-01
Amazon Music,99,monthly,2026-11-09
iCloud+,75,monthly,2026-11-11
PlayStation Plus,2999,yearly,2027-04-02
News Subscription,199,monthly,2026-11-18
Domain Hosting,2400,yearly,2027-02-25
CSV

cat > lib/functions.sh <<'FUNCS'
#!/usr/bin/env bash

# Resolve all paths from the project directory, not from the caller's directory.
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DATA="$PROJECT_DIR/data/subs.csv"
LOG="$PROJECT_DIR/logs/activity.log"
REPORTS="$PROJECT_DIR/reports"
BACKUPS="$PROJECT_DIR/backups"

log() {
    printf '%s | %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$LOG"
}

check_data() {
    if [[ ! -f "$DATA" ]]; then
        echo "Data file not found: $DATA" >&2
        return 1
    fi
}

show_help() {
    cat <<'HELP'
Usage:
  ./main.sh          Open the interactive menu
  ./main.sh --help   Show this help
  ./main.sh --backup Create a compressed backup of data/
  ./main.sh --cron   Generate a renewal alert report
HELP
}

view_data() {
    check_data || return 1
    if command -v column >/dev/null 2>&1; then
        column -s, -t "$DATA"
    else
        cat -n "$DATA"
    fi
    log "viewed subscription data"
}

do_backup() {
    check_data || return 1
    mkdir -p "$BACKUPS"
    local f
    f="$BACKUPS/data_$(date +%Y%m%d_%H%M%S).tar.gz"
    tar -czf "$f" -C "$PROJECT_DIR" data
    echo "Backup saved: $f ($(du -h "$f" | cut -f1))"
    log "backup created: $f"
}

view_log() {
    if [[ -s "$LOG" ]]; then
        tail -n 15 "$LOG"
    else
        echo "No activity logged yet."
    fi
}

valid_date() {
    [[ "$1" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] &&
        date -d "$1" '+%Y-%m-%d' >/dev/null 2>&1 &&
        [[ "$(date -d "$1" '+%Y-%m-%d')" == "$1" ]]
}

feature_1() {
    check_data || return 1
    echo "== Add / cancel a subscription =="
    echo "1) Add subscription"
    echo "2) Cancel subscription"
    read -r -p "Choose 1 or 2: " action
    case "$action" in
        1)
            local name cost cycle renew
            read -r -p "Subscription name: " name
            if [[ -z "${name//[[:space:]]/}" || "$name" == *","* ]]; then
                echo "Name cannot be empty or contain a comma."
                return 1
            fi
            read -r -p "Cost (number, INR): " cost
            if [[ ! "$cost" =~ ^[0-9]+([.][0-9]{1,2})?$ ]]; then
                echo "Enter a valid non-negative amount, e.g. 199 or 199.50."
                return 1
            fi
            read -r -p "Billing cycle (monthly/yearly): " cycle
            cycle="${cycle,,}"
            if [[ "$cycle" != "monthly" && "$cycle" != "yearly" ]]; then
                echo "Cycle must be monthly or yearly."
                return 1
            fi
            read -r -p "Renewal date (YYYY-MM-DD): " renew
            if ! valid_date "$renew"; then
                echo "Enter a real date in YYYY-MM-DD format."
                return 1
            fi
            if grep -Fqi -- "$name," "$DATA"; then
                echo "A subscription with this name may already exist."
                read -r -p "Add it anyway? (y/N): " confirm
                [[ "$confirm" =~ ^[Yy]$ ]] || return 0
            fi
            printf '%s,%s,%s,%s\n' "$name" "$cost" "$cycle" "$renew" >> "$DATA"
            echo "Subscription added."
            log "added subscription: $name"
            ;;
        2)
            local name tmp
            read -r -p "Exact subscription name to cancel: " name
            if [[ -z "$name" ]]; then echo "Name cannot be empty."; return 1; fi
            tmp="$(mktemp)"
            awk -F',' -v name="$name" 'BEGIN{IGNORECASE=1} NR==1 || $1!=name' "$DATA" > "$tmp"
            if cmp -s "$DATA" "$tmp"; then
                rm -f "$tmp"
                echo "Subscription not found: $name"
                return 1
            fi
            cat "$tmp" > "$DATA"
            rm -f "$tmp"
            echo "Subscription cancelled."
            log "cancelled subscription: $name"
            ;;
        *) echo "Invalid choice."; return 1 ;;
    esac
}

feature_2() {
    check_data || return 1
    echo "== Monthly and yearly cost =="
    awk -F',' '
      NR==1 {next}
      {
        cost=$2+0
        if ($3=="monthly") { monthly+=cost; yearly+=cost*12 }
        else if ($3=="yearly") { monthly+=cost/12; yearly+=cost }
        count++
      }
      END {
        printf "Subscriptions counted: %d\n", count
        printf "Estimated monthly total: Rs. %.2f\n", monthly
        printf "Estimated yearly total:  Rs. %.2f\n", yearly
      }' "$DATA"
    log "calculated monthly and yearly costs"
}

feature_3() {
    check_data || return 1
    echo "== Renewals in the next 7 days (including today) =="
    local today end found=0
    today="$(date +%F)"
    end="$(date -d '+7 days' +%F)"
    printf '%-25s %-12s %-12s\n' "NAME" "COST (Rs.)" "RENEW DATE"
    awk -F',' -v today="$today" -v end="$end" '
      NR>1 && $4>=today && $4<=end {
        printf "%-25s %-12s %-12s\n", $1, $2, $4
        found++
      }
      END {if (!found) print "No renewals due in the next 7 days."}
    ' "$DATA"
    log "checked renewals for next 7 days"
}

feature_4() {
    check_data || return 1
    echo "== Five most expensive subscriptions (listed price) =="
    { head -n 1 "$DATA"; tail -n +2 "$DATA" | sort -t, -k2,2nr | head -n 5; } |
      awk -F',' 'NR==1 {printf "%-25s %-12s %-10s %-12s\n",$1,"COST (Rs.)",$3,$4; next}
                 {printf "%-25s %-12s %-10s %-12s\n",$1,$2,$3,$4}'
    log "viewed most expensive subscriptions"
}

feature_5() {
    echo "== Renewal reminder setup =="
    echo "The daily 9:00 AM schedule is configured with crontab."
    echo "To test the reminder now, choose option 5 then run: ./main.sh --cron"
    echo "Alert report: $REPORTS/renewals_alert.txt"
    log "viewed renewal reminder instructions"
}

cron_task() {
    check_data || return 1
    mkdir -p "$REPORTS"
    local today end
    today="$(date +%F)"
    end="$(date -d '+7 days' +%F)"
    {
        echo "Subscription renewal alert"
        echo "Generated: $(date '+%Y-%m-%d %H:%M:%S')"
        echo "Period: $today through $end"
        echo
        awk -F',' -v today="$today" -v end="$end" '
          NR==1 {next}
          $4>=today && $4<=end {
            printf "%s | Rs. %s | %s | renews %s\n", $1, $2, $3, $4
            found++
          }
          END {if (!found) print "No renewals due in the next 7 days."}
        ' "$DATA"
    } > "$REPORTS/renewals_alert.txt"
    echo "Renewal alert report written to $REPORTS/renewals_alert.txt"
    cat "$REPORTS/renewals_alert.txt"
    log "generated renewal alert report"
}

FUNCS

cat > main.sh <<'MAIN'
#!/usr/bin/env bash
set -o nounset
cd "$(dirname "$0")" || exit 1
source lib/functions.sh
touch "$LOG"

case "${1:-}" in
    --help) show_help; exit 0 ;;
    --backup) do_backup; exit $? ;;
    --cron) cron_task; exit $? ;;
    "") ;;
    *) echo "Unknown argument: $1"; show_help; exit 2 ;;
esac

while true; do
    echo
    echo '========== SUBSCRIPTION TRACKER =========='
    echo '1) Add / cancel a subscription'
    echo '2) Monthly and yearly cost'
    echo '3) Renewals in the next 7 days'
    echo '4) Most expensive subscriptions'
    echo '5) Renewal reminder information'
    echo '6) View data'
    echo '7) Backup data (tar.gz)'
    echo '8) View activity log'
    echo '0) Exit'
    read -r -p "Choose an option: " ch || break
    case "$ch" in
        1) feature_1 ;;
        2) feature_2 ;;
        3) feature_3 ;;
        4) feature_4 ;;
        5) feature_5 ;;
        6) view_data ;;
        7) do_backup ;;
        8) view_log ;;
        0) echo "Bye!"; break ;;
        *) echo "Invalid choice, try again." ;;
    esac
done
MAIN

cat > README.md <<'README'
# L29 – Subscription Tracker

Student: PAGHADAR MIHIR VIKESHKUMAR | Roll: G26 | Division: G
Enrollment: 24004501210234

## Problem
Track subscription costs and renewal dates.

## CSV columns
- name: subscription name
- cost: amount in INR
- cycle: monthly or yearly
- renew_date: renewal date in YYYY-MM-DD format

## Features
1. Add or cancel a subscription
2. Estimate monthly and yearly costs
3. List renewals due within seven days
4. Show the five highest listed costs
5. Generate a renewal alert report
6. View CSV data, create a tar.gz backup, and view activity logs

## Run
cd ~/linux_project/subtracker
./main.sh
./main.sh --help
./main.sh --backup
./main.sh --cron

## Schedule renewal alerts at 9:00 AM daily
Add this line with `crontab -e`:
0 9 * * * /bin/bash "$HOME/linux_project/subtracker/main.sh" --cron >> "$HOME/linux_project/subtracker/logs/cron.log" 2>&1

## What I learned
I learned to write a menu-driven Bash script using functions, loops, and case statements.
I used awk, grep, sort, date, tar, and file tests to process CSV data.
I added input validation, activity logging, compressed backups, and a cron schedule.
README

touch logs/activity.log
chmod +x main.sh lib/functions.sh
echo
echo "Starter kit ready! Folder: $P"
find "$P" -maxdepth 2 -type f -print | sort
echo
echo "Next: cd ~/linux_project/subtracker && ./main.sh"
