#!/bin/bash
#set -x

# Default wait timeout in seconds
WTIME=60
SQLDB=dependencies.db
export PATH=$PATH:.

# Required utills
SQL=$(which sqlite3)

chk_status(){
app_name=$1
w_time=$2
#echo "checking status for [$app_name] application"

case "$(app-status $app_name;echo $?)" in
    0) echo -e "Application [$app_name] is \e[36mrunning\e[39m.";;
    1) echo -e "Application [$app_name] is \e[33mstarting\e[39m..";;
    2) echo -e "Application [$app_name] is \e[91mdown\e[39m..";;
    *) echo "Application [$app_name] state is unknown.."
esac

if [[ -n $w_time ]];then
local end=$((SECONDS+$WTIME))
while [[ $SECONDS -lt $end ]];do
        state=$(app-status $app_name;echo $?)
        if [[ $state == 0 ]];then
        echo "Application [$app_name] is running"
        break
        else
        echo "Waiting for application [$app_name] initialization.."
        fi
        sleep 1
        :
done
[ $state != 0 ] && echo "Application [$app_name] failed to start within configured time limit [$WTIME].Exiting"||:
fi
return $state
}

chk_deps(){
[[ $1 == "all" ]] && app_name="null"||app_name="'$1'"
result=$($SQL $SQLDB <<EOF | sed 's/,/ /g' | awk -F'|' '{print $1}'
with recursive deps_order(appName, dep_apps, depth) as (
    select appName
     , dep_apps
     , 1
    from deps
    where appName = coalesce($app_name, appName)
    union all
    select d.appName
     , d.dep_apps
     , r.depth + 1
    from deps d, deps_order r
    where trim(replace(substr(r.dep_apps, instr(r.dep_apps, d.appName) - 1, instr(r.dep_apps, d.appName) + length(d.appName) + length(d.appName) + 1), ',', ' ')) = d.appName
    and r.depth <= (select count(1) from deps)
)
select appName, dep_apps, max(depth) from deps_order group by appName, dep_apps order by depth desc;
EOF
)
echo "$result"
}

run_app(){
app_name=$1
if [[ $(app-status $app_name;echo $?) != 0 ]];then
echo "starting [$app_name] application"
app-start $app_name && chk_status "$app_name" "$WTIME"
else
echo "Application [$app_name] has been started already."
fi
return $?
}

die(){
    echo "$1"
    exit 100
}


prepare_testenv(){
# Switch to script directory before doing anything
SDIR="$( cd "$( dirname "$0" )" && pwd )"
cd $SDIR || die "Unable change working directory to [$SDIR]"

echo "Creating sample database with application and dependencies."
[ -f dependencies.db ] && rm -f dependencies.db ||:

sqlite3 dependencies.db <<EOF
CREATE TABLE deps (appName varchar(20), dep_apps varchar(100));
INSERT INTO deps (appName) VALUES ('a1');
INSERT INTO deps (appName, dep_apps) VALUES ('a2', 'a1');
INSERT INTO deps (appName, dep_apps) VALUES ('a3', 'a1 a9 a10');
INSERT INTO deps (appName, dep_apps) VALUES ('a4', 'a1');
INSERT INTO deps (appName, dep_apps) VALUES ('a5', 'a1, a3');
INSERT INTO deps (appName, dep_apps) VALUES ('a6', 'a1, a2');
INSERT INTO deps (appName, dep_apps) VALUES ('a7', 'a1 a3');
INSERT INTO deps (appName, dep_apps) VALUES ('a8', 'a2,a3');
INSERT INTO deps (appName, dep_apps) VALUES ('a9', 'a1 a2');
INSERT INTO deps (appName) VALUES ('a10');
EOF

echo "creating stub files for utills and linking dummy apps"
cat > app-status <<\EOF
#!/bin/bash
app_name=$1
[ -f ${app_name}.state ] && exit "$(cat ${app_name}.state)" || exit 2
EOF

cat > app-start <<\EOF
#!/bin/bash
app_name=$1
echo "Starting app [${app_name}]"
./${app_name} &
exit $?
EOF

cat > a1 <<\EOF
#!/bin/bash
name=$(basename $0)
echo 1 > $name.state
sleep 15
echo 0 > $name.state
EOF

for i in 2 3 4 5 6 7 8 9 10;do
ln -s a1 a$i
done

chmod +x a*
}

action=$1
source_app=$2

case "$action" in
        start) 
                for app in $(chk_deps "$source_app");do
                run_app $app &
                p_id=$!
                wait $p_id && echo "Application [$app] started successfuly" || die "Failed to start application [$app] with code [$?]"
                done
                ;;
        status)
                for app in $(chk_deps "$source_app");do
                chk_status $app
                done
                ;;
        prepare-env)
                echo "Undocummented test-env preparation call"
                prepare_testenv
                ;;        
        *) echo "Usage: $(basename $0) start|status appName|all"
                ;;
esac
