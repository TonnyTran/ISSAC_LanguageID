#!/bin/bash

input_dir=$1
output_dir=$2

tmp_dir=$output_dir/tmp

mkdir -p $tmp_dir

# trials=$input_dir/docs/lre17_eval_trials.tsv
# table=$input_dir/docs/lre17_eval_segments.key
trials=/data/users/ellenrao/NIST_LRE_Corpus/NIST_LRE_2017/key/lre17_eval_trials.tsv
table=/data/users/ellenrao/NIST_LRE_Corpus/NIST_LRE_2017/key/lre17_eval_segments.key
conv_table=./local/lre17_dev_eval_sessionids.tsv

for file in $(awk '/\.sph/ { sub(/.*\//,"",$1); printf "%s ",$1}' $table); do
    wav=$(find $input_dir -name $file)
    echo "$file sph2pipe -f wav -p $wav |"

done | sort >$output_dir/wav_sph.scp

for file in $(awk '/\.flac/ { sub(/.*\//,"",$1); printf "%s ",$1}' $table); do
    wav=$(find $input_dir -name $file)
    echo "$file sox $wav -r 8000 -t wav -b 16 -e signed-integer - |"

done | sort >$output_dir/wav_flac.scp

cat $output_dir/wav_sph.scp $output_dir/wav_flac.scp | sort >$output_dir/wav.scp

awk '$1!="segmentid" { sub(/.*\//,"",$1); print $1, $1}' $table | sort >$output_dir/utt2spk
cp $output_dir/utt2spk $output_dir/spk2utt

awk '$1!="segmentid" { sub(/.*\//,"",$1); print $1, $2}' $table | sort >$output_dir/utt2lang
./utils/utt2spk_to_spk2utt.pl $output_dir/utt2lang >$output_dir/lang2utt

cp $trials $output_dir/trials.tsv
cp $table $output_dir/segments.key

awk -v conv_table=$conv_table 'BEGIN{
while(getline < conv_table)
{
   if($2=="eval")
   {
      convs[$1]=$3
   }
}
}
$1 == "segmentid" { print $0,"sessionid" }
$1 != "segmentid" { print $0,convs[$1] }' $output_dir/segments.key >$output_dir/segments.ext.key

# wav-to-duration scp:$output_dir/wav.scp ark,t:$output_dir/utt2dur

# awk '{ sub(/.*\//,"",$1); print $0 }' $input_dir/docs/lre17_eval_trials.tsv > $output_dir/lre17_eval_trials.tsv
# awk 'BEGIN{ print "segmentid language_code data_source speech_duration" }
# $1 ~ ".sph$" { c="mls14"; d=30 }
# $2 < 20 { d=10}
# $2 < 6 { d=3 }
# $1 ~ ".flac$" { c="vast"; d="1000" }
# { print $1,"unk",c,d }
# ' $output_dir/utt2dur > $output_dir/lre17_eval_segments.key

# # awk '$1!="segmentid" { sub(/\.[^\.]*$/,"",$1); print $1, $2}' $table | sort > $output_dir/utt2lang
# # ./utils/utt2spk_to_spk2utt.pl $output_dir/utt2lang > $output_dir/lang2utt
