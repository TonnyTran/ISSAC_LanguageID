#!/bin/bash

input_dir=$1
output_dir=$2

tmp_dir=$output_dir/tmp

mkdir -p $tmp_dir

table=$input_dir/docs/filename_language_key.tab

for file in $(awk '{ sub(/\.sph/,"",$1); printf "%s ",$1}' $table)
do
    wav=$(find $input_dir -name $file.sph)
    echo "$file sph2pipe -f wav -p $wav |"

done | sort > $output_dir/wav.scp


awk '{ sub(/\.sph/,"",$1); print $1, $1}' $table | sort > $output_dir/utt2spk
cp $output_dir/utt2spk $output_dir/spk2utt

awk '{ sub(/\.sph/,"",$1); print $1, $2}' $table | sort > $output_dir/utt2lang
./utils/utt2spk_to_spk2utt.pl $output_dir/utt2lang > $output_dir/lang2utt

