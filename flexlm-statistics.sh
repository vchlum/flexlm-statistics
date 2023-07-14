#!/bin/bash

# usage example: ./flexlm-statistics.sh flexlm_server1.log flexlm_server2.log  flexlm_lm-server3.log

#initial date of flexlm log
INIT_DATE="3/19/2020"
INIT_DATE="10/13/2015"

#timestamp - from when the data should be exported
MIN_TS=1640995200

# license of interest
LICENSE="\"MATLAB\""

# set of users included in exported data
# item can be regexp
USERS=(
"vchlum"
)

USERS_AFFILIATION=(
"vchlum@CESNET"
)

# hostanem regexp of nodes in exported data
HOSTNAMES=".*cz"

USERS=".*"
HOSTNAMES=".*"


# progress and tmp files definitions
TS_ALL="ts_all"
TS_ALL_SORTED="${TS_ALL}_sorted"
TS_RESETS_ADDED="${TS_ALL}_resets"
TS_ALL_SORTED_USERS="${TS_ALL}_users"
TS_ALL_SORTED_LICENSE="${TS_ALL_SORTED_USERS}_license"
FINAL="final.dat"
FINAL_PEAKS="final_day_peaks.dat"
FINAL_OUT_NUMBER="final_out.dat"
FINAL_HOURS="final_hours.dat"

# add timestamps to all lines containing time of day in the log files
# iterates over log files and adds timestamps
# checks if time of day passes midnight and adds day in such a case
TS_FILES=()
for FILE in "$@"
do
    TS_FILE="ts_$FILE"
    cat $FILE | grep -E "^[ ]*[0-9]+:[0-9]+:[0-9]+ .+" | awk -v init_date=$INIT_DATE '
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


# concate all log files into one
echo "" > $TS_ALL
for TS_FILE in "${TS_FILES[@]}"
do
    cat $TS_FILE >> $TS_ALL
done

# sort concated file based on timestamps
cat $TS_ALL | sort -s -n -k 1,1 > $TS_ALL_SORTED


# adds tags RESET_OUT - meaning all counters should be reset due to licenses out are reset
cat $TS_ALL_SORTED | awk 'BEGIN{master=""} {
	if ($0 ~ /.*REStarted MLM.*/) print $1 " RESET_OUT";
	if ($0 ~ /.*Since this is an unknown status, license server.*/) print $1 " RESET_OUT";

	print
}' > $TS_RESETS_ADDED


# creating regexp from users in form of (user1|user2|user3|...)
ALL_USERS=""
for USER in "${USERS[@]}" ; do
	ALL_USERS="${USER}|$ALL_USERS"
done
ALL_USERS=${ALL_USERS::-1}

USERS_REGEXP="^($ALL_USERS)@$HOSTNAMES"

# filters by users and also adds reset points
cat $TS_RESETS_ADDED | awk -v r=$USERS_REGEXP '{
	if ($6 ~ r) print
	if ($2 == "RESET_OUT") print
	if ($4 == "TIMESTAMP") print
}' > $TS_ALL_SORTED_USERS

# filters by licenses in/out and reset points
cat $TS_ALL_SORTED_USERS | awk  -v lic=$LICENSE '{
	if ($5 == lic && ($4 == "IN:" || $4 == "OUT:")) print $1 " " $4 " " $6 " " $5 " "$7
	if ($2 == "RESET_OUT") print
	if ($4 == "TIMESTAMP") print
}' > $TS_ALL_SORTED_LICENSE

# real magic is here
# tracks licenses per node and decreases out for 'in' record if no more license is on node
# for 'out' records if first license is issued increases out
# if 'in' includes 'shutdown', all licenses per this node are returned -> always decrease out and reset licenses on node
# you can select if 'licenses out' or 'unique users' are printed out
cat $TS_ALL_SORTED_LICENSE | awk -v mts=$MIN_TS 'BEGIN{out=0}
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
			lic[node]++
		else
			lic[node]=1
			
		if (lic[node] == 1)
			out++
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

# eventually, the file containing one line per license change is transformed into file
# where each line is one day containing peak of the day
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

			print day " " max
						
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
			
			max=$4
			day=$1
	}
} END {print $1 " " max}' > $FINAL_PEAKS

exit 0

# institutions: number of liceses out
AFFILIATION=""
for USER in "${USERS_AFFILIATION[@]}" ; do
	AFFILIATION="${USER};$AFFILIATION"
done
AFFILIATION=${AFFILIATION::-1}

cat $TS_ALL_SORTED_LICENSE | awk -v mts=$MIN_TS -v affiliation=$AFFILIATION 'BEGIN {
	split(affiliation, users, ";")
	for (u in users) {
		split(users[u], a, "@")
		af_dic[a[1]] = a[2]
	}
}
{
	if ($2 == "OUT:") {
		node=$3
		split(node, n, "@")
		institution=af_dic[n[1]]

		if ($1 >= mts) {
			if (institution in runs)
				runs[institution]++
			else
				runs[institution]=1
		}
	}

} END{
	for (inst in runs) {
		print inst " " runs[inst]
	}
}' | sort > $FINAL_OUT_NUMBER


# institutions: license-hours
cat $TS_ALL_SORTED_LICENSE | awk -v mts=$MIN_TS -v affiliation=$AFFILIATION 'BEGIN {
	split(affiliation, users, ";")
	for (u in users) {
		split(users[u], a, "@")
		institution=a[2]
		af_dic[a[1]] = institution

		license_time[institution] = 0

		license_ts[institution][1]=""
		split("", license_ts[institution])
	}
}
{
	node=$3
	split(node, n, "@")
	institution=af_dic[n[1]]

	if ($2 == "IN:") {
		l=length(license_ts[institution])
		seconds=$1 - license_ts[institution][l]
		delete license_ts[institution][l]

		if ($1 >= mts)
			license_time[institution]+=seconds

		if ($5 == "(SHUTDOWN)") {
			for (i = 2; i<=lic[node]; i++) {
				l=length(license_ts[institution])
				seconds=$1 - license_ts[institution][l]
				delete license_ts[institution][l]

				if ($1 >= mts)
					license_time[institution]+=seconds
			}
		}

		if ($5 == "(SHUTDOWN)") {
			lic[node]=0
		} else if (node in lic) {
			lic[node]--
		} else {
			lic[node]=0
		}
	}
	if ($2 == "OUT:") {
		if (length(license_ts[institution]) > 0) {
			l=length(license_ts[institution])
			license_ts[institution][l+1] = $1
		} else {
			license_ts[institution][1]=""
			split("", license_ts[institution])

			license_ts[institution][1] = $1
		}

		if (node in lic)
			lic[node]++
		else
			lic[node]=1
	}

	if ($2 == "RESET_OUT") {
		split("", lic)
	}

} END{
	for (inst in license_time) {
		lt=license_time[inst]/3600
		printf inst " %.0f\n", lt
	}
}' | sort > $FINAL_HOURS