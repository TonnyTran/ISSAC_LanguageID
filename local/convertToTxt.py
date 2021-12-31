from __future__ import print_function
import kaldi_io #_vesis84
import numpy
import os
import sys

file_ark = sys.argv[1]
outdir= sys.argv[2]
dict_dat = {}
for key,mat in  kaldi_io.read_mat_ark(file_ark):
    numpy.savetxt(outdir + "/" + key + "_prob", mat[:, 0], fmt="%.6f")
    currChanVAD = (mat[:, 0] >= 0.5).astype(int)
    numpy.savetxt(outdir + "/" + key + ".txt", currChanVAD, fmt="%d")

    
