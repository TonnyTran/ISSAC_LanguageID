#!/bin/bash

input_dir=$1
output_dir=$2

tmp_dir=$output_dir/tmp

mkdir -p $tmp_dir

trials=$input_dir/docs/lre17_dev_trials.tsv
table=$input_dir/docs/lre17_dev_segments.key
conv_table=./local/lre17_dev_eval_sessionids.tsv

for file in $(awk '/\.sph/ { printf "%s ",$1}' $table)
do
    wav=$(find $input_dir -name $file)
    echo "$file sph2pipe -f wav -p $wav |"

done | sort > $output_dir/wav_sph.scp


for file in $(awk '/\.flac/ { printf "%s ",$1}' $table)
do
    wav=$(find $input_dir -name $file)
    echo "$file sox $wav -r 8000 -t wav -b 16 -e signed-integer - |"

done | sort > $output_dir/wav_flac.scp

cat $output_dir/wav_sph.scp $output_dir/wav_flac.scp | sort > $output_dir/wav.scp

awk '$1!="segmentid" { print $1, $1}' $table | sort > $output_dir/utt2spk
cp $output_dir/utt2spk $output_dir/spk2utt

awk '$1!="segmentid" { print $1, $2}' $table | sort > $output_dir/utt2lang
./utils/utt2spk_to_spk2utt.pl $output_dir/utt2lang > $output_dir/lang2utt

cp $trials $output_dir/trials.tsv
cp $table $output_dir/segments.key

awk -v conv_table=$conv_table 'BEGIN{
while(getline < conv_table)
{
   if($2=="dev")
   {
      convs[$1]=$3
   }
}
}
$1 == "segmentid" { print $0,"sessionid" }
$1 != "segmentid" { print $0,convs[$1] }' $output_dir/segments.key > $output_dir/segments.ext.key

