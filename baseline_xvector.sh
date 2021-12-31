#!/bin/bash

#####
# Author:   Tran The Anh + Jang Jicheng
# Date:     Dec 2021
# Project:  ISSAC
# Topic:    Language ID
# Licensed: Nanyang Technological University
#####

# Build a kaldi x-vector baseline 
. cmd.sh
. path.sh

train_set="lre17_train_30s"
recog_sets="lre17_eval_3s lre17_eval_10s lre17_eval_30s lre17_dev_3s lre17_dev_10s lre17_dev_30s"

feat_name="bn" # bottleneck feature

# data location and project location
source_data=data
project_dir=exp
exp_dir=$project_dir/exp-${train_set}-${feat_name}

epochs=30

nj=5
steps=100
train_stage=-11
use_gpu=wait

remove_egs=false

sleep_time=3
model_limit=8

num_pdfs=
min_chunk=60
max_chunk=100

max_chunk_size=10000
min_chunk_size=25

dropout_schedule='0,0@0.20,0.1@0.50,0'
srand=123
train_stage=-10	

echo 
echo "$0 $@"
echo

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

target_data=$exp_dir/data
[ -d $exp_dir ] || mkdir -p $exp_dir
[ -d $target_data ] || mkdir -p $target_data

## Kaldi x-vector model training
# Training (preprocess -> get_egs -> training -> extract_xvectors)
outputname=kaldi_xvector
nnet_dir=$exp_dir/${outputname}
[ -d $nnet_dir ] || mkdir -p $nnet_dir

echo -e "SleepTime=$sleep_time\nLimit=$model_limit" > $nnet_dir/control.conf

egs_dir=$exp_dir/${outputname}/egs
train=$source_data/${train_set}
no_sil=$target_data/${train_set}_no_sil

# Now we prepare the features to generate examples for xvector training.
if [ ! -z $step01 ]; then
    echo -e "____________Step 1: Prepare feats for egs start @ $(date)____________"
    [ -d "${no_sil}" ] && rm -rf ${no_sil}
    [ -d "${exp_dir}/train_no_sil" ] && rm -rf ${exp_dir}/train_no_sil

    subtools/kaldi/sid/nnet3/xvector/prepare_feats_for_egs.sh --nj $nj --cmd "$cmd" \
        ${train}/${feat_name} ${no_sil} $exp_dir/${train_set}_no_sil    
    echo "${no_sil}"
    echo -e "____________Step 1: Prepare feats for egs ended @ $(date)____________"
fi

if [ ! -z $step02 ]; then
    echo -e "____________Step 2: Remove utts start @ $(date)____________"
    subtools/removeUtt.sh ${no_sil} $max_chunk
    echo -e "____________Step 2: Remove utts ended @ $(date)____________"
fi

if [ ! -z $step03 ]; then
    echo -e "____________Step 3: Get egs start @ $(date)____________"
    mkdir -p $nnet_dir
    num_pdfs=$(awk '{print $2}' $train/utt2spk | sort | uniq -c | wc -l)

    subtools/kaldi/sid/nnet3/xvector/get_egs.sh --cmd "$cmd" \
    --nj 8 \
    --stage 0 \
    --frames-per-iter 1000000000 \
    --frames-per-iter-diagnostic 100000 \
    --min-frames-per-chunk $min_chunk \
    --max-frames-per-chunk $max_chunk \
    --num-diagnostic-archives 3 \
    --num-repeats 1000 \
    ${no_sil} $egs_dir
    echo -e "____________Step 3: Get egs ended @ $(date)____________"
fi

if [ ! -z $step04 ]; then
    echo -e "____________Step 4: Network config start @ $(date)____________"
    num_targets=$(wc -w $egs_dir/pdf2num | awk '{print $1}')
    feat_dim=$(cat $egs_dir/info/feat_dim)

    max_chunk_size=10000
    min_chunk_size=25

    mkdir -p $nnet_dir/configs
	cat <<EOF > $nnet_dir/configs/network.xconfig
	# please note that it is important to have input layer with the name=input
	# The frame-level layers
	input dim=${feat_dim} name=input
 	spec-augment-layer name=spec-augment freq-max-proportion=0.3 time-zeroed-proportion=0.1 time-mask-max-frames=20 include-in-init=true
	relu-batchnorm-layer name=tdnn1 input=Append(-2,-1,0,1,2) dim=512
	relu-batchnorm-layer name=tdnn2 dim=512
	relu-batchnorm-layer name=tdnn3 input=Append(-2,0,2) dim=512
	relu-batchnorm-layer name=tdnn4 dim=512
	relu-batchnorm-layer name=tdnn5 input=Append(-3,0,3) dim=512
	relu-batchnorm-layer name=tdnn6 dim=512
	relu-batchnorm-layer name=tdnn7 input=Append(-4,0,4) dim=512
	relu-batchnorm-layer name=tdnn8 dim=512
	relu-batchnorm-layer name=tdnn9 dim=512
	relu-batchnorm-layer name=tdnn10 dim=1500

	stats-layer name=stats config=mean+stddev(0:1:1:${max_chunk_size})

	# This is where we usually extract the embedding (aka xvector) from.
	relu-batchnorm-layer name=embedding1 dim=512 input=stats

	# This is where another layer the embedding could be extracted
	# from, but usually the previous one works better.
	relu-batchnorm-layer name=embedding2 dim=512
	output-layer name=output include-log-softmax=true dim=${num_targets}
EOF

	steps/nnet3/xconfig_to_configs.py \
        --xconfig-file $nnet_dir/configs/network.xconfig \
        --config-dir $nnet_dir/configs
	cp $nnet_dir/configs/final.config $nnet_dir/nnet.config

	# These three files will be used by sid/nnet3/xvector/extract_xvectors.sh
	echo "output-node name=output input=embedding1.affine" > $nnet_dir/extract.config
	echo "$max_chunk_size" > $nnet_dir/max_chunk_size
	echo "$min_chunk_size" > $nnet_dir/min_chunk_size
    echo -e "____________Step 4: Network config ended @ $(date)____________"
fi

if [ ! -z $step05 ]; then
    echo -e "____________Step 5: Train xvectors system start @ $(date)____________"
    subtools/kaldi/steps/nnet3/train_raw_dnn.py \
        --stage=$train_stage \
        --cmd="$cmd" \
        --trainer.optimization.proportional-shrink 10 \
        --trainer.optimization.momentum=0.5 \
        --trainer.optimization.num-jobs-initial=2 \
        --trainer.optimization.num-jobs-final=2 \
        --trainer.optimization.initial-effective-lrate=0.005 \
        --trainer.optimization.final-effective-lrate=0.0005 \
        --trainer.optimization.minibatch-size=128 \
        --trainer.srand=$srand \
        --trainer.max-param-change=2 \
        --trainer.num-epochs=$epochs \
        --trainer.dropout-schedule="$dropout_schedule" \
        --trainer.shuffle-buffer-size=1000 \
        --egs.frames-per-eg=1 \
        --egs.dir="$egs_dir" \
        --cleanup.remove-egs $remove_egs \
        --cleanup.preserve-model-interval=10 \
        --use-gpu=wait \
        --dir=$nnet_dir  || exit 1;
    echo -e "____________Step 5: Train xvectors system ended @ $(date)____________"
fi

if [ ! -z $step06 ]; then
    echo -e "____________Step 6: Extract xvectors of several datasets start @ $(date)____________"
    nj=4
    gpu=true
    cache=3000
    for x in ${recog_sets} ${train_set} ;do 
        subtools/kaldi/sid/nnet3/xvector/extract_xvectors_sre.sh  --cmd "$cmd" \
			--use-gpu $gpu --nj $nj --cache-capacity $cache $nnet_dir ${source_data}/$x/${feat_name} $nnet_dir/$x
        echo "layer embeddings of $x extracted done."
    done
    echo -e "____________Step 6: Extract xvectors of several datasets ended @ $(date)____________"
fi

train_set=$train_set
train=$train_set
enroll=$train_set
clad=100

# Get score
if [ ! -z $step09 ]; then
    echo -e "____________Step 7: Get score on recog sets start @ $(date)____________"
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
    echo -e "____________Step 7: Get score on recog sets ended @ $(date)____________"
fi

