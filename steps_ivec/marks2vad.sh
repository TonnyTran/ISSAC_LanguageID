#!/bin/bash

data_dir=$1
marks_dir=$2
vad_dir=$3

feat-to-len scp:$data_dir/feats.scp ark,t:$data_dir/utt2len

mkdir -p $vad_dir
name=$(basename $data_dir)

for f in $(awk '{ print $1}' $data_dir/wav.scp)
do
    mark_f=$marks_dir/$f.mark
    num_frames=$(awk '/'$f'/ { print $2}' $data_dir/utt2len)
    python - <<EOF
import sys
import numpy as np
with open('$mark_f') as f:
     fields = [line.rstrip().split(sep=' ') for line in f]
key = [i[0] for i in fields]
start = np.array([float(i[1])*100 for i in fields])
stop = np.array([float(i[2])*100 for i in fields]) + start
start = np.floor(start).astype(int)
stop = np.ceil(stop).astype(int)
vad = np.zeros(($num_frames,), dtype=int)
for i1,i2 in zip(start, stop):
     vad[i1:i2] = 1
sys.stdout.write('$f [ ')
for v in vad:
     sys.stdout.write('%d ' % v)
sys.stdout.write(']\n')
EOF

done | copy-vector ark,t:- ark,scp:$vad_dir/vad_$name.ark,$vad_dir/vad_$name.scp

cp $vad_dir/vad_$name.scp $data_dir/vad.scp




