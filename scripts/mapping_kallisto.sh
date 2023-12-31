#!/bin/bash -x

echo $@
params=("$@")

# saner programming env: these switches turn some bugs into errors
set -o errexit -o pipefail -o noclobber -o nounset

# -allow a command to fail with !’s side effect on errexit
# -use return value from ${PIPESTATUS[0]}, because ! hosed $?
! getopt --test > /dev/null 
if [[ ${PIPESTATUS[0]} -ne 4 ]]; then
    echo 'I’m sorry, `getopt --test` failed in this environment.'
    exit 1
fi

OPTIONS=
LONGOPTS=index:,pdata:,samples:,out:,nthread:,log:,bootstrap:,fraglen:,sd:,

# -regarding ! and PIPESTATUS see above
# -temporarily store output to be able to check for errors
# -activate quoting/enhanced mode (e.g. by writing out “--options”)
# -pass arguments only via   -- "$@"   to separate them correctly
! PARSED=$(getopt --options=$OPTIONS --longoptions=$LONGOPTS --name "$0" -- "$@")
if [[ ${PIPESTATUS[0]} -ne 0 ]]; then
    # e.g. return value is 1
    #  then getopt has complained about wrong arguments to stdout
    exit 2
fi
# read getopt’s output this way to handle the quoting right:
eval set -- "$PARSED"

bootstrap=100 fraglen=200 sd=80
# now enjoy the options in order and nicely split until we see --
while true; do
    case "$1" in
		--index)
        	index="$2"
            shift 2
            ;;
		--pdata)
            pdata="$2"
            shift 2
            ;;
        --samples)
            samples="$2"
            shift 2
            ;;
        --out)
            out="$2"
            shift 2
            ;;
        --nthread)
            nthread="$2"
            shift 2
            ;;
		--log)
			log="$2"
			shift 2
			;;
		--bootstrap)
			bootstrap="$2"
			shift 2
			;;
		--fraglen)
			fraglen="$2"
			shift 2
			;;
		--sd)
			sd="$2"
			shift 2
			;;
        --)
            shift
            break
            ;;
        *)
            shift
            ;;
    esac
done

baseout=$out/KALLISTO/quant
baseoutP=$out/KALLISTO/pseudo
kallisto='/home/software/kallisto/kallisto'
kindex="$index/kallisto/INDEX"

dir=$(basename $out)

mkdir -p $baseout
mkdir -p $baseoutP

echo "[INFO] [kallisto] ["`date "+%Y/%m/%d-%H:%M:%S"`"] Started processing $dir"$'\n'

watch pidstat -dru -hlH '>>' $log/kallisto_${dir}.$(date +%s).pidstat & wid2=$!
starter="$(date +%s)"

mkdir -p $log/kallisto_$dir

for sample in `sed '1d' $pdata | cut -f1`; do
	samplein=$samples/$sample
	sampleout=$baseout/$sample
	sampleoutP=$baseoutP/$sample

	[ "$(ls -A $sampleout)" ] && echo "[INFO] [kallisto] $sampleout already exists; skipping.."$'\n' && continue
	mkdir $sampleout
	watch pidstat -dru -hlH '>>' $log/kallisto_${dir}/$sample.$(date +%s).pidstat & wid=$!
	
	##paired
	[ -f "${samplein}_1.fastq.gz" ] &&\
		$kallisto quant -t $nthread --index $kindex --output-dir $sampleout --bias -b $bootstrap ${samplein}_1.fastq.gz ${samplein}_2.fastq.gz && \
		$kallisto pseudo -t $nthread --index $kindex --output-dir $sampleoutP ${samplein}_1.fastq.gz ${samplein}_2.fastq.gz
	##unpaired
	[ -f "$samplein.fastq.gz" ] &&\
		$kallisto quant -t $nthread --index $kindex -l $fraglen -s $sd --output-dir $sampleout --bias -b $bootstrap --single $samplein.fastq.gz && \
		$kallisto pseudo -t $nthread --index $kindex --output-dir $sampleoutP --single $samplein.fastq.gz

	kill -15 $wid
done
echo "$(($(date +%s)-$starter))" >> $log/kallisto_${dir}.$(date +%s).runtime
kill -15 $wid2

echo "[INFO] [kallisto] ["`date "+%Y/%m/%d-%H:%M:%S"`"] Finished processing $dir"$'\n'
