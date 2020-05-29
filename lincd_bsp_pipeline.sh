#/bin/bash -
#jenkins_base="http://pek-lpgtest17.wrs.com:8080/view/BSP_Regression/job/"
#jenkins_job_suffix="/label=good_host/consoleText"
jenkins_job_suffix="/consoleText"
progress_path="/folk/jhu2/scripts/scripts_repo/bsp_ci/logs/"
shared_image_base="/net/pek-lpgtest7302/buildarea1/SharedImage/"
jenkins_builder_base="http://pek-lpggp5.wrs.com:5001/jenkins_builder/jobs?q="

#builder_path="/lpg-build/cdc/jenkins-builder-v2/"
builder_path="/folk/jhu2/repo/jenkins-builder/"
builder_cmd="./jenkins-image-builder -c ./configs/jenkins_local.ini"
#builder_cmd="./jenkins-image-builder -c /folk/jhu2/repo/jenkins-builder/configs/jenkins_local.ini"
build_yaml_path=${builder_path}"jobs/build/"

runtimer_path="/lpg-build/cdc/jenkins-builder-v2/"
#runtimer_path="/net/pek-lpgtest20/buildarea1/lyang0/repo/jenkins-builder-new/"
runtimer_path=$builder_path
runtimer_cmd="./jenkins-job-scheduler2 -c ./configs/jenkins_local.ini"
#runtimer_cmd="./jenkins-job-scheduler2 -c /folk/jhu2/repo/jenkins-builder/configs/jenkins_local.ini"
#runtime_yaml_path=${builder_path}"jobs/runtime/"
runtime_yaml_path="/folk/jhu2/repo/jenkins-builder/jobs/runtime/"

debug="cat"
timeout=1800
wait_time=15
interval=500
last_count=0
runtime_printed_num=0

group_name=""
run_as_group="no"
runtime_step="no"
report_step="no"
shared_image_check="no"
no_show_summary_html="no"
no_show_build_log="no"
time_stamp_file="rootfs.tar.bz2"
runtime_start_once="yes"
runtime_end_once="yes"

parallel_yaml_path="/folk/jhu2/repo/jenkins-builder/jobs/parallel_yamls/"
parallel_yaml_path="/folk/jhu2/repo/jenkins-builder/jobs/runtime/"


usage()
{
exit 0
}

cat_to_yaml()
{
    group=$1

cat << EOF > ${parallel_yaml_path}${group}.yaml
global_config:
    bsp: intel-x86-64
    target_name: NUC7i5DNK1E
    kernel_arch: x86-64
    tester_name: jhu2
    email_recipient_list: jianwei.hu@windriver.com
    extra_config: '--templates feature/docker'
    customized_case_list:
       - $group

job:
    - kernel_type: standard
      domain: LTP
      fs_type: glibc-std
EOF
}

plan_generate()
{
    #echo "${groups// /,}"
    cd ${runtimer_path} &> /dev/null
    ${runtimer_cmd} -r ${product} -j ${runtime_yaml_path} -b ${combo} -m ${board}
    cd - &> /dev/null
    exit 0
}

#download the all log with curl/wget command
get_html()
{
    link=$1
    log=$2
    #get_html_cmd="wget "
    #ops="-O"
    get_html_cmd="curl -u admin:admin "
    ops="-o"
    ${get_html_cmd} ${link} ${ops} ${log} &> /dev/null
}

#check the image has vaild date and week
out_of_date_check()
{
    #The latest testing image should be in 5 days
    threshold=86400
    #threshold=432000
    #used date
    ud=${1##*/}
    #current date
    cd_human=`TZ='Asia/Chongqing' date "+%Y-%m-%d %H:%M:%S"`

    ud_human="${ud:0:4}-${ud:4:2}-${ud:6:2} ${ud:9:2}:${ud:11:2}:${ud:13:2}"
    weekdayofimage=`TZ='Asia/Chongqing' date -d "$ud_human" +%A`
    dayofweek=`TZ='Asia/Chongqing' date -d "$cd_human" +%A`

    ud_s=`TZ='Asia/Chongqing' date -d "$ud_human" +%s`
    cd_s=`TZ='Asia/Chongqing' date -d "$cd_human" +%s`
    ud_s_threshold=$((ud_s + $threshold))

    echo "The used image date: $ud_human"
    echo "The current date   : $cd_human"
    echo "threshold: $((threshold/24/60/60))d ($((threshold/60/60))h)"

    if [ $ud_s_threshold -lt $cd_s ]; then
        echo "used date: $ud_human  + $((threshold/24/60/60))d($((threshold/60/60))h) < current date:$cd_human"
        echo "ERROR: The used image is out of date, please build new image to testing"
        exit 1
    fi

    cur_weekofyear=`TZ='Asia/Chongqing' date +%V`
    image_weekofyear=`TZ='Asia/Chongqing' date -d "$ud_human" +%V`

    if [ $cur_weekofyear -ne $image_weekofyear ];then
        echo "INFO: Current week: $cur_weekofyear"
        echo "INFO: Image week: $image_weekofyear"
        echo "ERROR: This image is not in current week, please build new image to testing"
        exit 1
    fi
}

#md5sum check TBD
essential_check()
{
    exist_flag=1
    essential_files=(imgInfo.txt \
                   kernel \
                   rootfs.tar.bz2 \
                   )
    #num=${#essential_files[@]}

    for one_file in "${essential_files[@]}"
    do
        md5sum ${shared_image}/$one_file 
        [ ! -s ${shared_image}/$one_file ] && ((exist_flag&=0))
        if [ $exist_flag -ne 1 ];then
            echo "`TZ='Asia/Chongqing' date "+%Y-%m-%d %H:%M:%S"` The essential file $one_file are not present"
            break
        else
            echo "`TZ='Asia/Chongqing' date "+%Y-%m-%d %H:%M:%S"` The $one_file file is present"
        fi
    done
    echo "-----------------------------------------------------------"
    if [ $exist_flag -eq 1 ];then
        echo "`TZ='Asia/Chongqing' date "+%Y-%m-%d %H:%M:%S"` PASS: all essential files are present"
    else
        echo "`TZ='Asia/Chongqing' date "+%Y-%m-%d %H:%M:%S"` FAIL: the essential file is incorrect"
        exit 3
    fi
    echo "-----------------------------------------------------------"
}

#check the shared image is valid
shared_image_check()
{
    shared_image=$1
    if [ -n "$shared_image" ];then
        echo "shared_image: $shared_image"
        out_of_date_check $shared_image
        essential_check
    else
        echo "ERROR: Not found shared image!"
        exit 1
    fi
}

#submit one runtime job to jenkins template
runtime_sumbit()
{
    product=$1
    combo=$2
    boards=$3
    group_name=$4
    [ -n "$group_name" ] &&run_group="-g $group_name"
    echo "${runtimer_path}:"
    cd ${runtimer_path} &> /dev/null
    for board in `echo $boards`
    do
        echo "board name: $board"
        echo +++++++++++++++++++++++++++++++++++++++++++++++
        echo "${runtimer_cmd} -r ${product} -j ${runtime_yaml_path} -b ${combo}"
        ${runtimer_cmd} -r ${product} -j ${runtime_yaml_path} -b ${combo}

        echo "${runtimer_cmd} -r ${product} -j ${runtime_yaml_path} -b ${combo} -m ${board}"
        ${runtimer_cmd} -r ${product} -j ${runtime_yaml_path} -b ${combo} -m ${board}

        echo "${runtimer_cmd} -r ${product} -j ${runtime_yaml_path} -b ${combo} -m ${board} -e ${run_group}"
        if [ X"$debug" != X"debug" ];then
             sst=$((RANDOM %120))
             #echo "sleep $sst" && sleep $sst
             sleep $sst
             output=`${runtimer_cmd} -r ${product} -j ${runtime_yaml_path} -b ${combo} -m ${board} -e ${run_group}`
        else
            output="submit a new build http://pek-lpgtest17.wrs.com:8080/job/LINCD_BSP_STD/1522"
        fi
    done
    cd - &> /dev/null
    echo $output
    jenkins_job_id="${output##*/}"
    jenkins_job="`echo ${output}|awk -F" " '{print $5}'`"
    if [ "$jenkins_job_id" -gt 0 ] 2>/dev/null ;then
        :
    else
        echo "ERROR: Can not get build id"
        exit 6
    fi
}

#submit one build job to jenkins template
build_submit()
{
    product=$1
    combo=$2
    echo "${builder_path}:"
    cd ${builder_path} &> /dev/null
    echo "${builder_cmd} -r ${product} -j ${build_yaml_path} -b ${combo}"
    if [ X"$debug" != X"debug" ];then
        output=`${builder_cmd} -r ${product} -j ${build_yaml_path} -b ${combo}`
        #output=`/folk/jhu2/scripts/scripts_repo/bsp_ci/submit.py LINCD_BUILD_NEXT_PIPELINE`
    else
        output="submit a new build http://pek-lpgtest17.wrs.com:8080/job/LINCD_BUILD_STD/1393"
    fi
    cd - &> /dev/null
    echo $output
    jenkins_job_id="${output##*/}"
    jenkins_job="`echo ${output}|awk -F" " '{print $5}'`"
    if [ "$jenkins_job_id" -gt 0 ] 2>/dev/null ;then
        :
    else
        echo "ERROR: Can not get build id"
        exit 6
    fi
}

#check the build output, print the progress, the interal is 500
show_build_process()
{
    build_log_html=$1
    rm -rf $build_process_log
    get_html ${build_log_html} $build_process_log
    [ -s "$build_process_log" ] && message=`cat $build_process_log|grep "NOTE: Running task"| tail -1|awk -F"(" '{print $1}'|awk -F": " '{print $NF}'`
    current=`echo $message|awk '{print $3}'`
    [ -z "$current" ] && return
    if [ $current -gt $last_count ] ;then
        echo "`TZ='Asia/Chongqing' date "+%Y-%m-%d %H:%M:%S"` $message"
        last_count=$((current + $interval ))
    fi
}

show_runtime_process()
{
    runtime_html=$1
    rm -rf $runtime_process_log && get_html ${runtime_html} $runtime_process_log
    [ ! -s "$runtime_process_log" ] && return
    total_num=`cat $runtime_process_log | grep "class=\"testNameCell\""|wc -l`
    if [ $total_num -eq $runtime_printed_num ];then
        if [ X"$runtime_end_once" == X"yes" ];then
            echo "`TZ='Asia/Chongqing' date "+%Y-%m-%d %H:%M:%S"` INFO: All cases are executed and done!"
            runtime_end_once="no"
        fi
        return
    fi
    if [ X"$runtime_start_once" == X"yes" ];then
        echo "`TZ='Asia/Chongqing' date "+%Y-%m-%d %H:%M:%S"` INFO: Total case number: $total_num"
        runtime_start_once="no"
    fi
    ijk=0
    for case_name in `cat $runtime_process_log | grep "class=\"testNameCell\""|awk -F">|<" '{print $5}'`
    do
        ijk=$((ijk + 1))
        for case_result in `cat $runtime_process_log |grep "class=\"testNameCell\">$case_name<" -A4|tail -1|awk -F"\"" '{print $2}'`
        do
            [ -z "$case_result" -o X"$case_result" == X"No_Targets" -o X"$case_result" == X"Exec_Started" -o X"$case_result" == X"Got_Targets" -o X"$case_result" == X"Not_Started" ] && continue
            [ $ijk -le $runtime_printed_num ] && continue 
            runtime_printed_num=$((runtime_printed_num + 1))
            echo "`TZ='Asia/Chongqing' date "+%Y-%m-%d %H:%M:%S"` ${runtime_printed_num}. $case_name ==> $case_result"
        done
    done
}

#check build log, print build log path
show_build_log()
{
    summary_html=$1
    get_html ${summary_html} $summary_html_log
    timeout_times=$((timeout/wait_time))

    uuu=1
    while true
    do
       sleep $wait_time
       uuu=$((uuu + 1))
       [ -s $summary_html_log ] && break
       get_html ${summary_html} $summary_html_log
       if [ ${uuu} -gt ${timeout_times} ] ;then
           echo "$summary_html_log is NULL, timeout!!!"
           rm -rf $summary_html_log
       fi
    done
    
    cur_build_log_base=${summary_html%Summary/*}
    cur_build_log_suffix_raw=`cat $summary_html_log | grep consolelogs |grep "\.log"|head -1|awk -F"href=|\"" '{print $5}'`
    cur_build_log_suffix=${cur_build_log_suffix_raw#../*}
 
    build_log=${cur_build_log_base}${cur_build_log_suffix}
    if [ X"$no_show_build_log" == X"no" -a -n "$cur_build_log_suffix_raw" ];then
        no_show_build_log="yes"
        echo "`TZ='Asia/Chongqing' date "+%Y-%m-%d %H:%M:%S"` Build log: ${build_log}"
        echo ""
        echo ===========
    fi
    show_build_process ${build_log}
}

#check the job status in loop,print Log/Job cosole/Local summary html 
job_status_check()
{
    if [ -z "$jenkins_job_id" ];then
        echo "WARNING: jenkins_job_id is NULL"
        exit 6
    fi
    rm -rf $logfile
    sleep $wait_time
    job_path=${jenkins_job}${jenkins_job_id}${jenkins_job_suffix}
    job_path=${jenkins_job}${jenkins_job_suffix}
    get_html ${job_path} $logfile
    timeout_times=$((timeout/wait_time))

    jjj=1
    while true
    do
       sleep $wait_time
       jjj=$((jjj + 1))
       [ -s $logfile ] && break
       get_html ${job_path} $logfile
       if [ ${jjj} -gt ${timeout_times} ] ;then
           echo "$logfile is NULL, timeout!!!"
           rm -rf $logfile
           exit 1
       fi
    done

    MY_NODE_NAME=`cat $logfile | grep '^MY_NODE_NAME'|head -1 |awk -F"=" '{print $2}'`
    cur_job_status=`cat $logfile | grep '^Finished:'`
    cur_summary_html_raw=`cat $logfile | grep '^local_log_link:'|awk -F" " '{print $2}'`

    if [ -n "$MY_NODE_NAME" ];then
        [ X"`echo $MY_NODE_NAME| grep "wrs.com"`" == X"" ] && MY_NODE_NAME="${MY_NODE_NAME}.wrs.com"
        cur_summary_html=`echo $cur_summary_html_raw|awk -v my_node_name=$MY_NODE_NAME -F"/" 'BEGIN{OFS="/"}{$3=my_node_name;print}'`
    else
        cur_summary_html=$cur_summary_html_raw
    fi

    #show summary.html once
    if [ X"$no_show_summary_html" == X"no" -a -n "$cur_summary_html" ];then
        no_show_summary_html="yes"
        echo ""
        echo ===========
        echo "`TZ='Asia/Chongqing' date "+%Y-%m-%d %H:%M:%S"` Log file: $logfile"
        echo "`TZ='Asia/Chongqing' date "+%Y-%m-%d %H:%M:%S"` Job console: $job_path"
        echo "`TZ='Asia/Chongqing' date "+%Y-%m-%d %H:%M:%S"` Local summary html: $cur_summary_html"
    fi

    [ X"$runtime_step" == X"no" -a -n "$cur_summary_html" ] && show_build_log $cur_summary_html
    [ X"$runtime_step" == X"yes" -a -n "$cur_summary_html" ] && show_runtime_process $cur_summary_html

    if [ -n "$cur_job_status" ] ;then
        if [ X"`echo $cur_job_status | grep SUCCESS`" != X"" ] ;then
            echo "`TZ='Asia/Chongqing' date "+%Y-%m-%d %H:%M:%S"` INFO: The ${job_path} is SUCCESS"
            return 0
        else
            echo "`TZ='Asia/Chongqing' date "+%Y-%m-%d %H:%M:%S"` ERROR: The ${job_path} is FAILED"
            print_time
            exit 1
        fi
    else
        #echo "The ${job_path} is WIP"
        return 1
    fi
}

#print the total time at the end
print_time()
{
   end_human=`TZ='Asia/Chongqing' date "+%Y-%m-%d %H:%M:%S"`
   echo "Done at: $end_human"

   start_s=`date -d "$start_human" +%s`
   end_s=`date -d "$end_human" +%s`
   used_time=$((end_s - start_s ))
   print_hour=`echo "scale=2;$used_time/60/60"|bc 2>/dev/null`
   print_mins=`echo "scale=0;$used_time/60"|bc 2>/dev/null`
   [ -n "$print_hour" ] && echo "The total time: $((used_time/24/60/60))d [${print_hour}h] [${print_mins}m] [${used_time}s]" ||\
                           echo "The total time: $((used_time/60))m [${used_time}s]"
                          
}

generate_report_link()
{
    case ${input_product} in
        circ) p=CIRC ;;
        next) p=NEXT ;;
        standard) p=STD ;;
    esac
   
    links="`echo ${combo}|sed "s/@/%20/g"`"
    dashboard="${jenkins_builder_base}${p}"%20"${links}"
    #echo "http://pek-lpggp5.wrs.com:5001/jenkins_builder/jobs?q=${params.combo.replace("@", "%20")}"
    echo "`TZ='Asia/Chongqing' date "+%Y-%m-%d %H:%M:%S"` INFO: ${dashboard}"
    exit 0
}

#main
start_human=`TZ='Asia/Chongqing' date "+%Y-%m-%d %H:%M:%S"`

while getopts "sGg:t:m:r:b:dcjR:" opt; do
        case ${opt} in
                s)
                        run_as_group="yes"
                        ;;
                G)
                        runtime_yaml_path=${parallel_yaml_path}
                        ;;
                g)
                        group_name=$OPTARG
                        runtime_yaml_path=${parallel_yaml_path}
                        ;;
                c)
                        echo "INFO: Check the shared image..."
                        shared_image_check="yes"
                        ;;
                t|m)
                        runtime_step="yes"
                        boards=$OPTARG
                        ;;
                b)
                        combo=$OPTARG
                        ;;
                R)
                        RR="$OPTARG"
                        f1=`echo "$RR" | awk -F "_" '{print $1}'`
                        f2=`echo "$RR" | awk -F "_" '{print $2}'`
                        f3=`echo "$RR" | awk -F "_" '{print $3}'`
                        echo ${f1/$f2/$f3} 
                        exit 0
                        ;;
                r)
                        input_product=$OPTARG
                        ;;
                d)
                        debug="debug"
                        #input_product="standard"
                        #combo="intel-x86-64@BSP@standard@glibc-std"
                        echo "INFO: Will dry run this script"
                        ;;
                j)
                        report_step="yes"
                        ;;
                \?) usage
                        ;;
        esac
done

if [ X"$input_product" != X"standard" -a X"$input_product" != X"next" -a X"$input_product" != X"circ" ];then
   echo "ERROR: Please give correct product name:[standard|next|circ]"
   exit 1
fi
product=$input_product

if [ -z "$combo" ] ;then
    echo "ERROR: The combo is required!"
    exit 1
fi

if [ X"$run_as_group" == X"yes" ];then
    board=$boards
    plan_generate
fi

echo "Start at: $start_human"
echo ""
echo "INFO: The given product: $input_product"
echo "INFO: The given job combo: $combo"
echo "INFO: The given job boards: $boards"
echo "INFO: The given group runtime path: $runtime_yaml_path"
[ X"$report_step" == X"yes" ] && generate_report_link
[ X"$runtime_step" == X"no" ] && boards=""

jenkins_base=${JENKINS_URL}job/
case "$product" in
    "standard")
        jenkins_job="${jenkins_base}LINCD_BUILD_STD_PIPILINE/"
        [ -n "$boards" ] && jenkins_job="${jenkins_base}LINCD_BSP_STD/"
        ;;
    "next")
        jenkins_job="${jenkins_base}LINCD_BUILD_NEXT_PIPELINE/"
        [ -n "$boards" ] && jenkins_job="${jenkins_base}LINCD_BSP_NEXT/"
        ;;
    "circ")
        jenkins_job="${jenkins_base}LINCD_BUILD_CIRC_PIPELINE/"
        [ -n "$boards" ] && jenkins_job="${jenkins_base}LINCD_BSP_NEXT/"
        ;;
esac


if [ X"$shared_image_check" == X"yes" ];then
    shared_image=`cat ${progress_path}build_pipe.log.${product}_${combo}|grep "^INFO: The new backend path:" |awk -F": " '{print $3}'`
    shared_image_http=`cat ${progress_path}build_pipe.log.${product}_${combo}|grep "^NOW_LATEST_IMAGE_PATH:" |cut -d ":" -f 2-`
    if [ X"$shared_image" == X"null" ] ;then
        echo "`TZ='Asia/Chongqing' date "+%Y-%m-%d %H:%M:%S"` ERROR: shared image is null"
        exit 1
    else 
        echo ""
        echo "==============="
        echo "`TZ='Asia/Chongqing' date "+%Y-%m-%d %H:%M:%S"` ${progress_path}build_pipe.log.${product}_${combo}"
        echo "Net path: $shared_image"
        echo "HTTP link: $shared_image_http"
        echo ""
        echo "==============="
        shared_image_check $shared_image
        exit 0
    fi
fi

if [ -n "$boards" ];then
    echo "`TZ='Asia/Chongqing' date "+%Y-%m-%d %H:%M:%S"` INFO: TEST RUNTIME phase..."
    runtime_sumbit $product $combo $boards $group_name
    logfile=${progress_path}"build_pipe.log.${product}_${combo:-null}_${boards//[,@ ]/_}${group_name:+_$group_name}"
    runtime_process_log=${progress_path}"build_pipe.log.${product}_${combo:-null}_${boards//[,@ ]/_}${group_name:+_$group_name}_runtime_process"
else
    echo "`TZ='Asia/Chongqing' date "+%Y-%m-%d %H:%M:%S"` INFO: BUILD phase..."
    build_submit $product $combo
    logfile=${progress_path}"build_pipe.log.${product}_${combo:-null}"
    summary_html_log=${progress_path}"build_pipe.log.${product}_${combo:-null}_summary_html"
    build_process_log=${progress_path}"build_pipe.log.${product}_${combo:-null}_build_process"
fi

while true
do
    job_status_check
    need_wait=$?
    if [ ${need_wait} -eq 0 ];then
        print_time
        break
    fi
done

echo "`TZ='Asia/Chongqing' date "+%Y-%m-%d %H:%M:%S"` Done"
