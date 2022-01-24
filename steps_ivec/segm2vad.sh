#!/bin/bash

data_dir=$1
segm_dir=$2
vad_dir=$3

len_file=$data_dir/utt2len
seg_file=$segm_dir/segments

if [ ! -f $len_file ];then
    feat-to-len scp:$data_dir/feats.scp ark,t:$len_file
fi

mkdir -p $vad_dir
name=$(basename $data_dir)

   
# python - <<EOF  | copy-vector ark,t:- ark,scp:$vad_dir/vad_$name.ark,$vad_dir/vad_$name.scp
# import sys
# import numpy as np
# with open('$len_file') as f:
#      num_frames = { r[0]:int(r[1]) for r in [ line.rstrip().split(sep=' ') for line in f] }
# with open('$seg_file') as f:
#      fields = [line.rstrip().split(sep=' ') for line in f]

# keys = set([i[1] for i in fields])
# for key in set(keys):
#      start = np.array([float(i[2])*100 for i in fields if i[1]==key])
#      stop = np.array([float(i[3])*100 for i in fields if i[1]==key])
#      start = np.floor(start).astype(int)
#      stop = np.ceil(stop).astype(int)
#      vad = np.zeros((num_frames[key],), dtype=int)
#      for i1,i2 in zip(start, stop):
#           vad[i1:i2] = 1
#      sys.stdout.write('%s [ ' % key)
#      for v in vad:
#           sys.stdout.write('%d ' % v)
#      sys.stdout.write(']\n')
# EOF
 

sort -k 1 $vad_dir/vad_$name.scp > $data_dir/vad.scp




