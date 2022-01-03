#!/bin/bash

#####
# Author:   Tran The Anh + Jang Jicheng
# Date:     Dec 2021
# Project:  ISSAC
# Topic:    Language ID
# Licensed: Nanyang Technological University
#####

# Testing our best model of kaldi x-vector baseline 
. cmd.sh
. path.sh

# Trainset and testset prepared from prepare_data.sh
train_set="lre17_train_30s"
recog_sets="lre17_eval_3s lre17_eval_10s lre17_eval_30s lre17_dev_3s lre17_dev_10s lre17_dev_30s"

feat_name="bn" # bottleneck feature

# data location and project location
source_data=data
nnet_dir=pretrained-model # our best model location

nj=10
steps=100
srand=123

echo 
echo "$0 $@"
echo

. parse_options.sh || exit 1
steps=$(echo $steps | perl -e '$steps=<STDIN>;  $has_format = 0;
  if($steps =~ m:(\d+)\-$:g){$start = $1; $end = $start + 10; $has_format ++;}
        elsif($steps =~ m:(\d+)\-(\d+):g) { $start = $1; $end = $2; if($start == $end){}
        elsif($start < $end){ $end = $2 +1;}else{die;} $has_format ++; }
      if($has_format > 0){$steps=$start;  for($i=$start+1; $i < $end; $i++){$steps .=":$i"; }}
      print $steps;' 2>/dev/null)  || exit 1

if [ ! -z "$steps" ]; then
  for x in $(echo $steps|sed 's/[,:]/ /g'); do
  index=$(printf "%02d" $x);
  declare step$index=1
  done
fi

if [ ! -z $step01 ]; then
    echo -e "____________Step 1: Extract xvectors of several datasets start @ $(date)____________"
    nj=4
    gpu=true
    cache=3000
    for x in ${recog_sets} ${train_set} ;do 
        subtools/kaldi/sid/nnet3/xvector/extract_xvectors_sre.sh  --cmd "$cmd" \
			--use-gpu $gpu --nj $nj --cache-capacity $cache $nnet_dir ${source_data}/$x/${feat_name} $nnet_dir/$x
        echo "layer embeddings of $x extracted done."
    done
    echo -e "____________Step 1: Extract xvectors of several datasets ended @ $(date)____________"
fi

train=$train_set
enroll=$train_set
clad=100

# Get score
if [ ! -z $step02 ]; then
    echo -e "____________Step 2: getScore use plda and lr start @ $(date)____________"
    echo $num
    for test in $recog_sets; do
        for meth in lr plda ;do
            local/scoreSet.sh --nj $nj --steps 1-11 --eval false --source_data $source_data \
                --trainset ${train} --vectordir $nnet_dir --enrollset ${enroll} --testset ${test} \
                --lda true --clda $clad --submean true --score $meth --metric "eer"
            local/scoreSet.sh --nj $nj --steps 1-11 --eval false --source_data $source_data --trainset ${train} \
                --vectordir $nnet_dir --enrollset ${enroll} --testset ${test} --lda true --clda $clad --submean true --score $meth --metric "Cavg" || exit;
            echo "#LOG:: getScore use $meth Done!"
        done
    done
    echo "*****Resuls are stored in $nnet_dir *****"
    echo -e "____________Step 2: getScore use plda and lr ended @ $(date)____________"
fi

