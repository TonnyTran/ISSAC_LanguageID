#!/bin/bash
#####
# Author:   Tran The Anh + Jang Jicheng
# Date:     Dec 2021
# Project:  ISSAC
# Topic:    Language ID
# Licensed: Nanyang Technological University
#####

echo
echo "$0 $@"
echo

. cmd.sh
. path.sh
set -e
cmd="slurm.pl --quiet --exclude=node0[3-4,8]"

## Raw data location
lre17_train=/data/users/ellenrao/NIST_LRE_Corpus/NIST_LRE_2017/LDC2017E22_2017_NIST_Language_Recognition_Evaluation_Training_Data
lre17_dev=/data/users/ellenrao/NIST_LRE_Corpus/NIST_LRE_2017/LDC2017E23_2017_NIST_Language_Recognition_Evaluation_Development_Data
lre17_eval=/data/users/ellenrao/NIST_LRE_Corpus/NIST_LRE_2017/LRE2017_Eval/lre17

# ASR model localtion for extracter bottleneck feature
dnn_model=pretrained-model/final_bn.mdl

nj=100
steps=100

function UsageExample {
  cat <<EOF
 $0 --steps 1 --cmd "$cmd" --nj $nj \
 /mipirepo/data/seame/formatted  projects/seame  
EOF
}

. parse_options.sh || exit 1

steps=$(echo $steps | perl -e '$steps=<STDIN>;  $has_format = 0;
  if($steps =~ m:(\d+)\-$:g){$start = $1; $end = $start + 10; $has_format ++;}
        elsif($steps =~ m:(\d+)\-(\d+):g) { $start = $1; $end = $2; if($start == $end){}elsif($start < $end){ $end = $2 +1;}else{die;} $has_format ++; }  
      if($has_format > 0){$steps=$start;  for($i=$start+1; $i < $end; $i++){$steps .=":$i"; }} print $steps;' 2>/dev/null) || exit 1

if [ ! -z "$steps" ]; then
  for x in $(echo $steps | sed 's/[,:]/ /g'); do
    index=$(printf "%02d" $x)
    declare step$index=1
  done
fi

dataset=train
source_data=data/original
train_set=train
dev_set=dev
test_set=test

tgbnf=tmp/$dataset/dnn_output
finalOutput=vad_segments/${dataset}

filename=$(basename -- "$testFile")
extension="${filename##*.}"
filename="${filename%.*}"

mkdir -p $tgbnf
mkdir -p tmp/$dataset/log

# prepare data in Kaldi format
if [ ! -z $step01 ]; then
  echo -e "____________Step 1: Prepare Kaldi format data start @ $(date)____________"
  bash ./local/make_lre17_train.sh $lre17_train $source_data/$train_set
  utils/fix_data_dir.sh $source_data/$train_set
  bash ./local/make_lre17_dev.sh $lre17_dev $source_data/$dev_set
  bash ./local/make_lre17_eval.sh $lre17_eval $source_data/$test_set

  # Divide test sets and verification sets of different lengths
  mkdir -p data/lre17_dev_3s
  cat data/original/dev/segments.key | awk '{if($4""=="3") print $1}' >data/lre17_dev_3s/utt.list
  utils/subset_data_dir.sh --utt-list data/lre17_dev_3s/utt.list data/original/dev/ data/lre17_dev_3s/
  mkdir -p data/lre17_dev_10s
  cat data/original/dev/segments.key | awk '{if($4""=="10") print $1}' >data/lre17_dev_10s/utt.list
  utils/subset_data_dir.sh --utt-list data/lre17_dev_10s/utt.list data/original/dev/ data/lre17_dev_10s/
  mkdir -p data/lre17_dev_30s
  cat data/original/dev/segments.key | awk '{if($4""=="30") print $1}' >data/lre17_dev_30s/utt.list
  utils/subset_data_dir.sh --utt-list data/lre17_dev_30s/utt.list data/original/dev/ data/lre17_dev_30s/

  mkdir -p data/lre17_eval_3s
  cat data/original/test/segments.key | awk '{if($4""=="3") print $1}' >data/lre17_eval_3s/utt.list
  utils/subset_data_dir.sh --utt-list data/lre17_eval_3s/utt.list data/original/test/ data/lre17_eval_3s/
  mkdir -p data/lre17_eval_10s
  cat data/original/test/segments.key | awk '{if($4""=="10") print $1}' >data/lre17_eval_10s/utt.list
  utils/subset_data_dir.sh --utt-list data/lre17_eval_10s/utt.list data/original/test/ data/lre17_eval_10s/
  mkdir -p data/lre17_eval_30s
  cat data/original/test/segments.key | awk '{if($4""=="30") print $1}' >data/lre17_eval_30s/utt.list
  utils/subset_data_dir.sh --utt-list data/lre17_eval_30s/utt.list data/original/test/ data/lre17_eval_30s/

  for x in data/lre17_dev_3s data/lre17_dev_10s data/lre17_dev_30s data/lre17_eval_3s data/lre17_eval_10s data/lre17_eval_30s;do
    cat $x/utt2lang | cut -d ' '  -f2 | paste -d '-' - $x/wav.scp > $x/new_wav.scp
    cat $x/utt2lang | awk '{print $2"-"$1 " " $2}' > $x/utt2spk
    rm $x/{spk2utt,utt2lang}
    mv $x/new_wav.scp $x/wav.scp
    utils/fix_data_dir.sh $x
  done
  echo -e "____________Step 1: Prepare Kaldi format data ended @ $(date)____________"
fi

segment_set=$source_data/$dataset
### Step 2: Compute mfcc
if [ ! -z $step02 ]; then
  echo -e "____________Step 2: Make MFCCs (to do VAD) start @ $(date)____________"
  steps/make_mfcc.sh --cmd "$cmd" --nj $nj --mfcc-config conf/mfcc_8k.conf $segment_set || exit 1
  sid/compute_vad_decision.sh --nj $nj --cmd "$cmd" \
    --vad-config conf/vad-5.0.conf $segment_set $segment_set/log $segment_set/feat || exit 1
  steps/compute_cmvn_stats.sh $segment_set || exit 1
  echo -e "____________Step 2: Make MFCCs (to do VAD) ended @ $(date)____________"
fi

### Step 3: Extract BNF feature
if [ ! -z $step03 ]; then
  echo -e "____________Step 3: Extract BNF feature (to do VAD) start  @ $(date)____________"
  [ ! -d $tgbnf/log ] || mkdir -p $tgbnf/log
  [ -d $segment_set/bn ] || mkdir -p $segment_set/bn
  [ -f $segment_set/segments ] && cp -r $segment_set/{wav.scp,utt2spk,spk2utt,utt2dur,feats.scp,cmvn.scp,segments,vad.scp} $segment_set/bn
  [ ! -f $segment_set/segments ] && cp -r $segment_set/{wav.scp,utt2spk,spk2utt,utt2dur,feats.scp,cmvn.scp,vad.scp} $segment_set/bn
  cp -r $segment_set/{wav.scp,utt2spk,spk2utt,utt2dur,feats.scp,cmvn.scp} $segment_set/bn
  steps_ivec/make_mfcc_bn.sh --mfcc-config conf/mfcc_hires.conf --nj $nj --cmd "$cmd" \
    $segment_set/bn $dnn_model $tgbnf/log $tgbnf || exit 1
  utils/fix_data_dir.sh $segment_set/bn
  echo -e "____________Step 3: Extract BNF feature (to do VAD) ended  @ $(date)____________"
fi

#### Step 4: Convert frame-based VAD to segment-based VAD
discardShortSeg=1.5       ### We discard segments shorter than 1.5s
mergeTwoSegCloserThan=1.5 ### Two segment closer than 1.5s will be merged into one segment
if [ ! -z $step04 ]; then
  echo -e "____________Step 4: Convert frame-based VAD to segment-based VAD start @ $(date)____________"
  files=$tgbnf/*.ark
  for f in $files; do
    python local/convertToTxt.py $f $tgbnf
  done
  files=$tgbnf/*.txt

  ls $tgbnf/*.txt >tmp/$dataset/list_all_files.txt
  split -l 300 -d tmp/$dataset/list_all_files.txt tmp/$dataset/
  count=$(($(ls tmp/$dataset/ | wc -l) - 3))

  mkdir -p ${finalOutput}_${discardShortSeg}_${mergeTwoSegCloserThan}
  ### Following commands will convert DNN VAD (frame-by-frame prediction) to segments.
  ${cuda_cmd} JOB=1:$count tmp/$dataset/log/processVad.JOB.log \
    python local/process_DNN_output_v2.py JOB tmp/$dataset ${finalOutput}_${discardShortSeg}_${mergeTwoSegCloserThan} $discardShortSeg $mergeTwoSegCloserThan
  echo -e "____________Step 4: Convert frame-based VAD to segment-based VAD ended @ $(date)____________"
fi

#### Step 5: Cut each speech segment (generated by step 4) into many fix-length chunks of fixLength with overlapping. Then, we prepare Kaldi-formatted data
if [ ! -z $step05 ]; then
  echo -e "____________Step 5: Segmentation into fix-length chunks start @ $(date)____________"
  fixLength=30
  hopLength=27.5
  echo "fixLength: ${fixLength}, hopLength=${hopLength}"
  finalFolder=segmentation/$dataset/${finalOutput}_${discardShortSeg}_${mergeTwoSegCloserThan}_${fixLength}_overlap_${hopLength}s
  mkdir -p $finalFolder

  ### Cut each speech segment into many fix-length chunks. Two consecutive chunks are overlapped 2.5s. The result is a segment file in $finalFolder
  python local/segmentation_to_short.py $segment_set/utt2spk ${finalOutput}_${discardShortSeg}_${mergeTwoSegCloserThan} $finalFolder/segments_old ${fixLength} ${hopLength}

  ### Now prepare other files to make $finalFolder to be a Kaldi-formatted data. For wav.scp, we just copy from folder in step 2.
  python local/generateKaldiDataLre.py $finalFolder/segments_old $segment_set/wav.scp $segment_set/utt2spk $segment_set/utt2lang $finalFolder

  utils/fix_data_dir.sh $finalFolder
  utils/validate_data_dir.sh --no-feats $finalFolder

  mkdir -p data/lre17_train_${fixLength}s
  cp segmentation/$dataset/${finalOutput}_${discardShortSeg}_${mergeTwoSegCloserThan}_${fixLength}_overlap_${hopLength}s/{utt2lang,segments,wav.scp} data/lre17_train_${fixLength}s
  cp data/lre17_train_${fixLength}s/utt2lang data/lre17_train_${fixLength}s/utt2spk
  utils/fix_data_dir.sh data/lre17_train_${fixLength}s
  echo -e "____________Step 5: Segmentation into fix-length chunks ended @ $(date)____________"
fi

# define train set and test sets using for training and testing
train_sets="lre17_train_30s"
recog_sets="lre17_eval_3s lre17_eval_10s lre17_eval_30s lre17_dev_3s lre17_dev_10s lre17_dev_30s"
data_dir=data

# step 6: Feature Preparation for training and testing
if [ ! -z $step06 ]; then
  echo "____________Step 6: Extract Bottleneck Feature for training and testing start: @ $(date)____________"
 for x in ${train_sets} ${recog_sets}; do
  # for x in ${recog_sets}; do
    data=$data_dir/$x/bn
    log=$data/log
    feat=$data/data-bn
    utils/data/copy_data_dir.sh $data_dir/$x $data || exit 1
    steps_ivec/make_mfcc_bn.sh --mfcc-config conf/mfcc_hires.conf --nj $nj --cmd "$cmd" \
      $data $dnn_model $log $feat || exit 1
    echo "## LOG(Extract Bottleneck Feature Done: $x @ $(date))"

    steps/compute_cmvn_stats.sh $data $log $feat || exit 1
    sid/compute_vad_decision.sh --nj $nj --cmd "$cmd" \
      --vad-config conf/vad-5.0.conf $data $log $feat || exit 1
    echo "## LOG(Compute CMVN and VAD Done: $x @ $(date))"
  done
  echo "____________Step 6: Extract Bottleneck Feature for training and testing ended: @ $(date)____________"
fi
