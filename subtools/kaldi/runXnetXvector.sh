#!/bin/bash

# Copyright     Tsinghua  (Author:YiLiu earlier than 2018-10-01)
#               xmuspeech (Author:Snowdar 2018-10-01 2018-12-13)


# This script is to train a multitask xvector network which contains two task, speaker/language recognition 
# and phonetic distinction but also has multi input branches of features just like a 'X' network in architecture, 
# which has a little difference with 'runMultiTaskXvector.sh'. It just supports two input branches now, but it's 
# very easy to add extra input branch by adding some variables and editing the nnet config.

set -e

stage=0
endstage=6

train_stage=-10

use_gpu=true
clean=true
remove_egs=true
cmn=true # do sliding cmn when getting egs

sleep_time=3
model_limit=8

phonetic_vad=true # if true,it works in both feats and ali during getting egs and it is equal to remove 'sil' phone
phonetic_min_len=20

xv_min_chunk=60
xv_max_chunk=80 # equal to xv_min_len:utt-length should be always >= xv_max_chunk

num_archives=150

# the training data with two feature types should pasted before runing this script and you could use 
# subtools/pasteFeats.sh to deal with this thing.
xvTrainData=data/mfcc_20_paste_plp_20_pitch_5.0/baseTrain
phoneticTrainData=data/mfcc_20_paste_plp_20_pitch_5.0/thchs30_train  # the feat-type and dim of two traindatas should be consistent
phoneticAliDir=exp/thchs30_train_dnn_ali # get ali from a am model by yourself
num_input=2 # num of input branch and if you change it, you should add feat_dim[n] and change nnet config by yourself
feat_dim[1]=  # dim of the first input branch. If NULL, the 'num_dims' file is expected to exist in xvTrainData, which could be generated by subtools/pasteFeats.sh
feat_dim[2]=

outputname=base_multiTask_xv_mfcc_20_paste_plp_20_pitch_5.0_cmn # just a output name and the real output-path is exp/$outputname

. subtools/path.sh
. subtools/kaldi/utils/parse_options.sh

########## auto variables ################
nnet_dir=exp/$outputname
phonetic_egs_dir=exp/$outputname/phonetic_egs
xv_egs_dir=exp/$outputname/xvector_egs

mkdir -p $nnet_dir
echo -e "SleepTime=$sleep_time\nLimit=$model_limit" > $nnet_dir/control.conf

xv_feat_dim=$(feat-to-dim scp:$xvTrainData/feats.scp -) || exit 1
phonetic_feat_dim=$(feat-to-dim scp:$phoneticTrainData/feats.scp -) || exit 1
[ $xv_feat_dim != $phonetic_feat_dim ] && echo "[exit] Dim of $xvTrainData is not equal to $phoneticTrainData" && exit 1

feat_dim=$xv_feat_dim

for n in $(seq $num_input);do
if [ "${feat_dim[$n]}" == "" ];then
[ ! -f "$xvTrainData/num_dims" ] && echo "[exit] feat_dim_$n is NULL and $xvTrainData/num_dims is not exist." && exit 1
feat_dim[$n]=$(awk -v n=$n '{print $n}' $xvTrainData/num_dims)
fi
done

#### stage --> go #####
if [[ $stage -le 0 && 0 -le $endstage ]];then
	echo "[stage 0] Prepare xvTrainData dir with no nonspeech frames for xvector egs"
	rm -rf ${xvTrainData}_nosil
	rm -rf exp/features/${xvTrainData}_nosil
	subtools/kaldi/sid/nnet3/xvector/prepare_feats_for_egs.sh --nj 20 --cmd "run.pl" \
			$xvTrainData ${xvTrainData}_nosil exp/features/${xvTrainData}_nosil
fi

if [[ $stage -le 1 && 1 -le $endstage ]];then
	echo "[stage 1] Remove utts whose length is less than the lower limit value"
	subtools/removeUtt.sh ${phoneticTrainData} $phonetic_min_len
	subtools/removeUtt.sh ${xvTrainData}_nosil $xv_max_chunk
fi


phonetic_output="phonetic_output"

if [[ $stage -le 2 && 2 -le $endstage ]];then 
	echo "[stage 2] Prepare multitask network config" 
	phonetic_num_targets=$(tree-info $phoneticAliDir/tree | grep num-pdfs | awk '{print $2}') || exit 1
	xv_num_targets=$(awk '{print $1}' $xvTrainData/spk2utt | sort | wc -l | awk '{print $1}') || exit 1
	max_chunk_size=10000
	min_chunk_size=25
	
	mkdir -p $nnet_dir/configs/phonetic

	cat <<EOF > $nnet_dir/configs/network.xconfig
	  
	  input dim=${feat_dim} name=input
      dim-range-component name=branch1 dim-offset=0 dim=${feat_dim[1]} input=input
      dim-range-component name=branch2 dim-offset=${feat_dim[1]} dim=${feat_dim[2]} input=input
	  
	  # shared layers
	  # input branch1
	  relu-batchnorm-layer name=branch1_tdnn1 input=Append(branch1@-2,branch1@-1,branch1@0,branch1@1,branch1@2) dim=256
	  relu-batchnorm-layer name=branch1_tdnn2 input=Append(-2,0,2) dim=256
	  relu-batchnorm-layer name=branch1_tdnn3 input=Append(-3,0,3) dim=256
	 
	  # input branch2
	  relu-batchnorm-layer name=branch2_tdnn1 input=Append(branch2@-2,branch2@-1,branch2@0,branch2@1,branch2@2) dim=256
	  relu-batchnorm-layer name=branch2_tdnn2 input=Append(-2,0,2) dim=256
	  relu-batchnorm-layer name=branch2_tdnn3 input=Append(-3,0,3) dim=256
	  
	  # append
	   relu-batchnorm-layer name=tdnn4 dim=512 input=Append(branch1_tdnn3,branch2_tdnn3)
	  
	  # phonetic branch
	  relu-batchnorm-layer name=phonetic_tdnn5 dim=512 input=tdnn4
	  relu-batchnorm-layer name=phonetic_tdnn6 dim=512 
	  relu-batchnorm-layer name=phonetic_tdnn7 dim=512 
	  output-layer name=$phonetic_output dim=$phonetic_num_targets max-change=1.5 
	  
	  # xvector branch
	  relu-batchnorm-layer name=tdnn5 dim=1500 input=tdnn4
	  
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
	  output-layer name=output include-log-softmax=true dim=${xv_num_targets}
EOF
	
	# parse nnet config with phonetic as main branch,but we just need the "vars" file here
	sed 's/name=output/name=xvector_output/g' $nnet_dir/configs/network.xconfig | \
	sed ''s/name=$phonetic_output/name=output/g'' > $nnet_dir/configs/phonetic/network.xconfig
	subtools/kaldi/steps/nnet3/xconfig_to_configs.py \
		--xconfig-file $nnet_dir/configs/phonetic/network.xconfig \
		--config-dir $nnet_dir/configs/phonetic
		
	# parse nnet config with xvector as main branch	and use it to init raw model
	subtools/kaldi/steps/nnet3/xconfig_to_configs.py \
		--xconfig-file $nnet_dir/configs/network.xconfig \
		--config-dir $nnet_dir/configs
	
	cp $nnet_dir/configs/vars $nnet_dir/configs/vars_xvec
	cp $nnet_dir/configs/phonetic/vars $nnet_dir/configs/vars_am
	
	# some configs for extracting xvector
	echo "output-node name=output input=tdnn6.affine" > $nnet_dir/extract_tdnn6.config
	cp -f $nnet_dir/extract_tdnn6.config $nnet_dir/extract.config
	echo "output-node name=output input=tdnn7.affine" > $nnet_dir/extract_tdnn7.config
	echo "$max_chunk_size" > $nnet_dir/max_chunk_size
	echo "$min_chunk_size" > $nnet_dir/min_chunk_size
fi	

# note:
# for train_cvector_dnn.py script (by YiLiu), the num of egs of xvector and phonetic should be equal and 
# *egs.*.scp is required to exist in both xvector and phonetic egs dir.Next, the "archive_chunk_lengths"
# file should be exist in $xv_egs_dir rather than $xv_egs_dir/temp where this file is generated initially. 
#
# the reason why don't combine the two type egs before training is that the author provide a c++ paragram 
# "nnet3-copy-cvector-egs" which can combine multitask egs temporarily when training,but it is not must
# because "nnet3-copy-egs" (kaldi provide) can also achive this purpose by option --outputs,which could be
# tedious than "nnet3-copy-cvector-egs".Ok,the training c++ paragrams like nnet3-train,nnet3-compute-prob
# are how to recognize multi-egs to update params of different branch of a shared network is very interesting,
# which is refered to the format of egs,a string like "<NnetIo> output <I1V>",which means this egs will be 
# used for a output-node (see parsed config ) whose name is "output" and ignore other branch.Yeh，the output-node 
# named "output" is a main branch and others,such as "phonetic_output", will be as a secondary branch,which 
# refering to "nnet3-compute",but by "nnet3-[am-]copy",you can still change the master-slave relationship always 
# when you just have a final.raw/final.mdl.

## xvector egs ##
##############################################
if [[ $stage -le 3 && 3 -le $endstage ]];then
	echo "[stage 3] get xvector egs"
	subtools/kaldi/sid/nnet3/xvector/get_egs.sh --cmd "run.pl" \
		--nj 20 \
		--stage 0 \
		--num-train-archives $num_archives \
		--frames-per-iter-diagnostic 100000 \
		--min-frames-per-chunk $xv_min_chunk \
		--max-frames-per-chunk $xv_max_chunk \
		--num-diagnostic-archives 3 \
		--num-repeats 6000 \
		"${xvTrainData}_nosil" $xv_egs_dir
	
	# training script needs this file
	cp -f $xv_egs_dir/temp/archive_chunk_lengths $xv_egs_dir
fi

## phonetic egs ##
##############################################	
if [[ $stage -le 4 && 4 -le $endstage ]];then
	echo "[stage 4] get phonetic egs"
	left_context=$(grep 'model_left_context' $nnet_dir/configs/phonetic/vars | cut -d '=' -f 2) || exit 1
	right_context=$(grep 'model_right_context' $nnet_dir/configs/phonetic/vars | cut -d '=' -f 2) || exit 1
	num_archives=$(cat $xv_egs_dir/info/num_archives) || exit 1
	frame_subsampling_factor=1
	[ -f $phoneticAliDir/frame_subsampling_factor ] && frame_subsampling_factor=$(awk '{print $1}' $phoneticAliDir/frame_subsampling_factor)

	subtools/kaldi/sid/nnet3/get_egs.sh --cmd "run.pl" \
		--nj 10 \
		--stage 0 \
		--frame-subsampling-factor $frame_subsampling_factor \
		--cmn $cmn \
		--vad $phonetic_vad \
		--generate-egs-scp true \
		--num-archives $num_archives \
		--frames-per-eg 1 \
		--left-context $left_context \
		--right-context $right_context \
		${phoneticTrainData} $phoneticAliDir $phonetic_egs_dir
fi


if [[ $stage -le 5 && 5 -le $endstage ]]; then
	echo "[stage 5] train multitask nnet3 raw model"
	dropout_schedule='0,0@0.20,0.1@0.50,0'
	srand=123
	
	subtools/kaldi/steps_multitask/nnet3/train_cvector_dnn.py --stage=$train_stage \
	  --cmd="run.pl" \
	  --trainer.optimization.proportional-shrink 10 \
	  --trainer.optimization.momentum=0.5 \
	  --trainer.optimization.num-jobs-initial=2 \
	  --trainer.optimization.num-jobs-final=8 \
	  --trainer.optimization.initial-effective-lrate=0.001 \
	  --trainer.optimization.final-effective-lrate=0.0001 \
	  --trainer.optimization.minibatch-size="256;64" \
	  --trainer.srand=$srand \
	  --trainer.max-param-change=2 \
	  --trainer.num-epochs=3 \
	  --trainer.dropout-schedule="$dropout_schedule" \
	  --trainer.shuffle-buffer-size=1000 \
	  --cleanup.remove-egs=$remove_egs \
	  --cleanup.preserve-model-interval=500 \
	  --use-gpu=true \
	  --am-output-name=$phonetic_output \
	  --am-weight=1.0 \
	  --am-egs-dir=$phonetic_egs_dir \
	  --xvec-output-name="output" \
	  --xvec-weight=1.0 \
	  --xvec-egs-dir=$xv_egs_dir \
	  --dir=$nnet_dir  || exit 1;
fi

if [[ -f $nnet_dir/final.raw && "$clean" == "true" ]];then
        rm -f $xv_egs_dir/egs*
        rm -f $phonetic_egs_dir/egs*
        rm -rf ${xvTrainData}_nosil
        rm -rf exp/features/${xvTrainData}_nosil
fi

if [[ $stage -le 6 && 6 -le $endstage ]]; then
	echo "[stage 8] extract multitask-xvectors of several datasets"
	prefix=plp_20_5.0
	toEXdata="baseTrain test_1s test_1s_concat_sp"
	layer="tdnn6"
	nj=20
	gpu=false
	cache=1000
	
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
