#!/bin/bash

data_dir=$1
data_dir_bn=$2
vad_dir=$3

mkdir -p $vad_dir

#feat-to-len scp:$data_dir_bn/feats.scp ark,t:$data_dir_bn/utt2len

mkdir -p $vad_dir

name=$(basename $data_dir)

copy-vector scp:$data_dir/vad.scp ark,t:- | \
    awk -v f2l=$data_dir_bn/utt2len 'BEGIN{
while(getline < f2l)
{
   l[$1]=$2
}
}
{ 
num_frames_in=NF-3;
num_frames_out=l[$1]
if (num_frames_in>num_frames_out)
{
   $(num_frames_out+3)="]";
   for(i=num_frames_out+4;i<=num_frames_in+3;i++){ $i=""}
}
else if (num_frames_in<num_frames_out)
{
  for(i=num_frames_in+3;i<num_frames_out+3;i++){ $i="0"};
  $(num_frames_out+3)="]";
};
print $0
}' | copy-vector ark,t:- ark,scp:$vad_dir/vad_${name}.ark,$data_dir_bn/vad.scp



