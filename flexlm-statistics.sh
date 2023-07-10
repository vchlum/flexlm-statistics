#!/bin/bash

# usage example: ./flexlm-statistics.sh flexlm_server1.log flexlm_server2.log  flexlm_lm-server3.log

INIT_DATE="3/19/2020"
MIN_TS=1640995200
LICENSE="\"MATLAB\""
USERS=(
"vchlum"
)

HOSTNAMES=".+cz"

#USERS=".*"
#HOSTNAMES=".*"

TS_ALL="ts_all"
TS_ALL_SORTED="${TS_ALL}_sorted"
TS_RESETS_ADDED="${TS_ALL}_resets"
TS_ALL_SORTED_USERS="${TS_ALL}_users"
TS_ALL_SORTED_LICENSE="${TS_ALL_SORTED_USERS}_license"
FINAL="final.dat"

TS_FILES=()
for FILE in "$@"
do
    TS_FILE="ts_$FILE"
    cat $FILE | grep -E "^[0-9]+:[0-9]+:[0-9]+ .+" | awk -v init_date=$INIT_DATE '
        BEGIN{ts=0; last_ts=0; split(init_date, d, "/")}
        {
			split($1, t, ":")

            if ($3 == "TIMESTAMP")
            {
                split($4, d, "/")
            } else {
				ts=mktime(d[3]" "d[1]" "d[2]" "t[1]" "t[2]" "t[3])
				if (ts < last_ts) {
					old_day=d[2]
					while (old_day == d[2]) {
						ts+=3600
						tmp=strftime("%m/%d/%Y %H:%M:%S", ts)
						split(tmp, tmp_split, " ")
						split(tmp_split[1], d, "/")
					}
				}
			}
            ts=mktime(d[3]" "d[1]" "d[2]" "t[1]" "t[2]" "t[3])
            last_ts=ts
            print ts" "$0
        }
    ' > $TS_FILE
    TS_FILES+=("$TS_FILE")
done

echo "" > $TS_ALL
for TS_FILE in "${TS_FILES[@]}"
do
    cat $TS_FILE >> $TS_ALL
done

cat $TS_ALL | sort -s -n -k 1,1 > $TS_ALL_SORTED

cat $TS_ALL_SORTED | awk 'BEGIN{master=""} {
	if ($0 ~ /.*REStarted MLM.*/) print $1 " RESET_OUT";

	print
}' > $TS_RESETS_ADDED

ALL_USERS=""
for USER in "${USERS[@]}" ; do
	ALL_USERS="${USER}|$ALL_USERS"
done
ALL_USERS=${ALL_USERS::-1}

USERS_REGEXP="^($ALL_USERS)@$HOSTNAMES"

cat $TS_RESETS_ADDED | awk -v r=$USERS_REGEXP '{if ($6 ~ r) print; if ($2 == "RESET_OUT") print}' > $TS_ALL_SORTED_USERS

cat $TS_ALL_SORTED_USERS | awk  -v lic=$LICENSE '{if ($5 == lic && ($4 == "IN:" || $4 == "OUT:")) print $1 " " $4 " " $6 " " $5 " "$7; if ($2 == "RESET_OUT") print}' > $TS_ALL_SORTED_LICENSE

cat $TS_ALL_SORTED_LICENSE | awk -v mts=$MIN_TS 'BEGIN{out=0; last_check_ts=0}
{
	node=$3
	if ($2 == "IN:") {
		if ($5 == "(SHUTDOWN)") {
			lic[node]=0
			out--
		} else if (node in lic) {
			lic[node]--
			if (lic[node] == 0) {
				out--
			}
		} else {
			lic[node]=0
			out--
		}
	}
	if ($2 == "OUT:") {
		if (node in lic)
			{lic[node]++}
		else
			{lic[node]=1}
			
		if (lic[node] == 1) {
			out++
		}

		last[node]=$1
	}

	if ($2 == "RESET_OUT") {
		split("", lic)
		out = 0
	}

	# licenses out
	if ($1 >= mts && 1 == 1) {
		datetime=strftime("%m/%d/%Y %H:%M:%S", $1)
		print datetime " " $1 " " out
	}

	# unique users using licenses
	if ($1 >= mts && 1 == 0) {
		datetime=strftime("%m/%d/%Y %H:%M:%S", $1)

		split("", uniq_users)
		for (node in lic) {
			if (lic[node] > 0) {
				split(node, user, "@")
				u = user[1]
				uniq_users[u] = 1
			}
		}

		uniq_count=0
		for (u in uniq_users) {
			if (uniq_users[u] > 0) {
				uniq_count++
				uniq_users[u] = 0
			}
		}

		print datetime " " $1 " " uniq_count
	}
}
' > $FINAL

cat $FINAL | awk -v mts=$MIN_TS 'BEGIN {
	tmp=strftime("%m/%d/%Y %H:%M:%S", mts)
	split(tmp, tmp_split, " ")
	day=tmp_split[1]
	max=0
}
{
	if (day == $1 && max < $4) {
		max=$4
	}

	if (day != $1) {
						
			split($1, curr_d, "/")
			
			split(day, last_d, "/")
			
			ts=mktime(last_d[3]" "last_d[1]" "last_d[2]" "12" "0" "0)

			ts+=86400
			tmp=strftime("%m/%d/%Y %H:%M:%S", ts)
			split(tmp, tmp_split, " ")
			split(tmp_split[1], last_d, "/")

			while ((curr_d[1] != last_d[1]) || (curr_d[2] != last_d[2]) || (curr_d[3] != last_d[3])) {
				print last_d[1]"/"last_d[2]"/"last_d[3]" "max
				
				ts+=86400
				tmp=strftime("%m/%d/%Y %H:%M:%S", ts)
				split(tmp, tmp_split, " ")
				split(tmp_split[1], last_d, "/")
			}
			
			print day " " max
			
			max=$4
			day=$1
	}
} END {print $1 " " max}' > "per_day_${FINAL}"
