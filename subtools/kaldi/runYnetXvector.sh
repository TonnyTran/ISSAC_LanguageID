#!/bin/bash

# Copyright xmuspeech (Author:Snowdar 2019-03-13)

set -e

stage=0
endstage=5
train_stage=-10
use_gpu=true
clean=true
remove_egs=true

sleep_time=3
model_limit=8

traindata=data/plp_20_5.0/baseTrain
outputname=base_xv_plp_20_5.0

num_input=2 # num of input branch and if you change it, you should add feat_dim[n] and change nnet config by yourself
feat_dim[1]=  # dim of the first input branch. If NULL, the 'num_dims' file is expected to exist in traindata, which could be generated by subtools/pasteFeats.sh
feat_dim[2]=

. subtools/path.sh
. subtools/kaldi/utils/parse_options.sh

nnet_dir=exp/$outputname
egs_dir=exp/$outputname/egs

mkdir -p $nnet_dir
echo -e "SleepTime=$sleep_time\nLimit=$model_limit" > $nnet_dir/control.conf

feat_dim=$xv_feat_dim

for n in $(seq $num_input);do
if [ "${feat_dim[$n]}" == "" ];then
[ ! -f "$traindata/num_dims" ] && echo "[exit] feat_dim_$n is NULL and $traindata/num_dims is not exist." && exit 1
feat_dim[$n]=$(awk -v n=$n '{print $n}' $traindata/num_dims)
fi
done

if [[ $stage -le 0 && 0 -le $endstage ]];then
rm -rf ${traindata}_nosil
rm -rf exp/features/${traindata}_nosil
subtools/kaldi/sid/nnet3/xvector/prepare_feats_for_egs.sh --nj 20 --cmd "run.pl" \
		$traindata ${traindata}_nosil exp/features/${traindata}_nosil
fi


min_chunk=60
max_chunk=80

num_archives=150

if [[ $stage -le 1 && 1 -le $endstage ]];then
subtools/removeUtt.sh ${traindata}_nosil $max_chunk
fi

if [[ $stage -le 2 && 2 -le $endstage ]];then
subtools/kaldi/sid/nnet3/xvector/get_egs.sh --cmd "run.pl" \
    --nj 20 \
    --stage 0 \
    --num-train-archives $num_archives \
    --frames-per-iter-diagnostic 100000 \
    --min-frames-per-chunk $min_chunk \
    --max-frames-per-chunk $max_chunk \
    --num-diagnostic-archives 3 \
    --num-repeats 6000 \
    "${traindata}_nosil" $egs_dir
fi

if [[ $stage -le 3 && 3 -le $endstage ]];then 
num_targets=$(wc -w $egs_dir/pdf2num | awk '{print $1}')
feat_dim=$(cat $egs_dir/info/feat_dim)
max_chunk_size=10000
min_chunk_size=25

mkdir -p $nnet_dir/configs

cat <<EOF > $nnet_dir/configs/network.xconfig
  # please note that it is important to have input layer with the name=input

  # The frame-level layers
  input dim=${feat_dim} name=input
  dim-range-component name=branch1 dim-offset=0 dim=${feat_dim[1]} input=input
  dim-range-component name=branch2 dim-offset=${feat_dim[1]} dim=${feat_dim[2]} input=input
	  
  # shared layers
  # input branch1
  relu-batchnorm-layer name=branch1_tdnn1 input=Append(branch1@-2,branch1@-1,branch1@0,branch1@1,branch1@2) dim=512
  relu-batchnorm-layer name=branch1_tdnn2 input=Append(-2,0,2) dim=512
  relu-batchnorm-layer name=branch1_tdnn3 input=Append(-3,0,3) dim=512

  # input branch2
  relu-batchnorm-layer name=branch2_tdnn1 input=Append(branch2@-2,branch2@-1,branch2@0,branch2@1,branch2@2) dim=512
  relu-batchnorm-layer name=branch2_tdnn2 input=Append(-2,0,2) dim=512
  relu-batchnorm-layer name=branch2_tdnn3 input=Append(-3,0,3) dim=512
  
  # append
  relu-batchnorm-layer name=tdnn4 dim=1024 input=Append(branch1_tdnn3,branch2_tdnn3)
  
  relu-batchnorm-layer name=tdnn5 dim=1500

  # The stats pooling layer. Layers after this are segment-level.
  # In the config below, the first and last argument (0, and ${max_chunk_size})
  # means that we pool over an input segment starting at frame 0
  # and ending at frame ${max_chunk_size} or earlier.  The other arguments (1:1)
  # mean that no subsampling is performed.
  stats-layer name=stats config=mean+stddev(0:1:1:${max_chunk_size})

  # This is where we usually extract the embedding (aka xvector) from.
  relu-batchnorm-layer name=tdnn6 dim=512 input=stats

  # This is where another layer the embedding could be extracted
  # from, but usually the previous one works better.
  relu-batchnorm-layer name=tdnn7 dim=512
  output-layer name=output include-log-softmax=true dim=${num_targets}
EOF

  subtools/kaldi/steps/nnet3/xconfig_to_configs.py \
      --xconfig-file $nnet_dir/configs/network.xconfig \
      --config-dir $nnet_dir/configs
  cp $nnet_dir/configs/final.config $nnet_dir/nnet.config

  # These three files will be used by sid/nnet3/xvector/extract_xvectors.sh
  echo "output-node name=output input=tdnn6.affine" > $nnet_dir/extract_tdnn6.config
  cp -f $nnet_dir/extract_tdnn6.config $nnet_dir/extract.config
  echo "output-node name=output input=tdnn7.affine" > $nnet_dir/extract_tdnn7.config
  echo "$max_chunk_size" > $nnet_dir/max_chunk_size
  echo "$min_chunk_size" > $nnet_dir/min_chunk_size
fi

dropout_schedule='0,0@0.20,0.1@0.50,0'
srand=123
if [[ $stage -le 4 && 4 -le $endstage ]]; then
  subtools/kaldi/steps/nnet3/train_raw_dnn.py --stage=$train_stage \
    --cmd="run.pl" \
    --trainer.optimization.proportional-shrink 10 \
    --trainer.optimization.momentum=0.5 \
    --trainer.optimization.num-jobs-initial=2 \
    --trainer.optimization.num-jobs-final=8 \
    --trainer.optimization.initial-effective-lrate=0.001 \
    --trainer.optimization.final-effective-lrate=0.0001 \
    --trainer.optimization.minibatch-size=128 \
    --trainer.srand=$srand \
    --trainer.max-param-change=2 \
    --trainer.num-epochs=3 \
    --trainer.dropout-schedule="$dropout_schedule" \
    --trainer.shuffle-buffer-size=1000 \
    --egs.frames-per-eg=1 \
    --egs.dir="$egs_dir" \
    --cleanup=true \
    --cleanup.remove-egs=$remove_egs \
    --cleanup.preserve-model-interval=500 \
    --use-gpu=$use_gpu \
    --dir=$nnet_dir  || exit 1;
fi

if [[ -f $nnet_dir/final.raw && "$clean" == "true" ]];then
rm -f $nnet_dir/egs/egs*
rm -rf ${traindata}_nosil
rm -rf exp/features/${traindata}_nosil
fi

if [[ $stage -le 5 && 5 -le $endstage ]]; then
prefix=plp_20_5.0
toEXdata="baseTrain test_1s"
layer="tdnn6"
nj=30
force=true
gpu=false
cache=3000

for x in $toEXdata ;do
for y in $layer ;do
num=0
[ -f $nnet_dir/$y/$x/xvector.scp ] && num=$(grep ERROR $nnet_dir/$y/$x/log/extract.*.log | wc -l)
[[ "$force" == "true" || ! -f $nnet_dir/$y/$x/xvector.scp || $num -gt 0 ]] && \
subtools/kaldi/sid/nnet3/xvector/extract_xvectors.sh --cache-capacity $cache --extract-config extract_${y}.config \
    --use-gpu $gpu --nj $nj $nnet_dir data/${prefix}/$x $nnet_dir/$y/$x
> $nnet_dir/$y/$x/$prefix
echo "$y layer embeddings of data/$prefix/$x extracted done."
done
done
fi

