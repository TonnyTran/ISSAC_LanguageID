#################V2.1 ################
#The difference between this version and the previous V2 is at line 696. PostProcessVAD(currChanVAD, 20) instead of MedianFilter(currChanVAD, 25). Also we use results from DNN with sliced features
#print the 
import numpy
import math
import scipy.interpolate
import os
import sys
import random
import scipy.signal
import scipy.fftpack
import scipy.stats as ss
import glob
from copy import deepcopy

def readList(wavscpfile):
    listUtt = []
    f = open(wavscpfile, 'r')
    line = f.readline()
    while line:
        row = line.split()
        listUtt.append(row[0])
        line = f.readline()
    f.close()
    return listUtt

class Seg:
    def __init__(self):
        self.start = []
        self.stop = []
        self.label = []

def MedianFilter(x,filter_len):
    nf = len(x);
    hs = (filter_len-1)/2
    y=deepcopy(x);
    for i in range(hs, nf-hs):
        y[i] = numpy.median(x[i-hs:i+hs+1]);
    return y

def PostProcessVAD(vad, buffer_len, filter_len = 40):
    vad = vad[:];
    
    # First filter the vad flat using a median filter
    vad_smoothed = MedianFilter(vad, 3);
    # Then grow any valid speech frame by 20 frames, as we think
    # anything immediately before and after the voiced frames are
    # speech.
    
    #if nargin<3
    #    filter_len = 40;
    #end
    bool_arr = numpy.greater(numpy.convolve(numpy.ones(filter_len), vad_smoothed), 0.5)
    vad_extended = bool_arr.astype(numpy.double)
    vad_extended = vad_extended[filter_len/2:]#vad_extended(1:filter_len/2) = [];
    vad_extended = vad_extended[:len(vad_extended)-filter_len/2+1]#vad_extended(end-filter_len/2+2:end) = [];
    
    # We don't want to have too many segments. Sometimes, we can merge
    # several segments into one.
    filter_len = buffer_len-40;
    if filter_len>0:
        bool_arr2 = numpy.greater(numpy.convolve(numpy.ones(filter_len), vad_extended), 0.5)
        vad_merged = bool_arr2.astype(numpy.double)
        vad_merged = vad_merged[filter_len/2:]#vad_merged(1:filter_len/2) = [];
        vad_merged = vad_merged[:len(vad_merged)-filter_len/2+1]#vad_merged(end-filter_len/2+2:end) = [];
    else:
        vad_merged = vad_extended;
    
    return vad_merged

def label2seg(label):
    # If the state is changed
    diff = label[1:] - label[0:len(label)-1];
    idx_tuple = numpy.nonzero(diff);
    idx = idx_tuple[0]
    N_seg = len(idx);
    #print ("Number of segment = " + str(N_seg))
    seg = Seg() 
    if N_seg ==0:
        seg.start.append(0);
        seg.stop.append(len(label)-1);
        seg.label.append(label[0])
        return seg  
    for i in range(N_seg):
        if i==0 :
            seg.start.append(0);
        else:
            seg.start.append(idx[i-1]+1)
        seg.stop.append(idx[i])
        seg.label.append(label[idx[i]])
    seg.start.append(idx[-1]+1)
    seg.stop.append(len(label)-1);
    seg.label.append(label[-1])
    
    return seg


def writeSeg(seg, outfile, maxLength, buffExt, discardShortSegLength, tollerance, segmentBuffFile, segmentOrgFile):
    #discardShortSegLength=0.07
    #tollerance= 0.5
    N_seg = len(seg.label)
    segInfor = []
    #for i in range(numChans):
    #  writer = open("segment_" + str(i+1) +  posfix + ".txt", "w")
    #  segWriter.append(writer)
    for i in range(N_seg):
        if seg.label[i] > 0:
            segInfor.append(str(round(seg.start[i] * 0.01, 2)) + " " + str(round(seg.stop[i] * 0.01, 2)))  
        
    writer = open(outfile, "w")
    for j in range(len(segInfor)):
        writer.write(segInfor[j] + "\n")
    writer.close()
    currStart = 0
    currEnd = 0
    currSeg = 0
    wf = open(segmentOrgFile, "w")
    wf2 = open(segmentBuffFile, "w")
    for i in range(N_seg):
        if seg.label[i] > 0: 
            start = seg.start[i] * 0.01
            end = seg.stop[i] * 0.01
            #avg_energ = numpy.average(energy[seg.start[i]:seg.stop[i]])
            #if avg_energ <= filterRatio * mean:
            #    print("Discard segment (" + str(seg.start[i] * 0.01) + ", " + str(seg.stop[i]) + " since the average energy is " + str(avg_energ) + " which is less than " + str(filterRatio) + " mean energy (i.e. " + str(filterRatio * mean)) 
            #    continue
            
            #print("Consider: " + posfix + " and (" + str(currStart) + "," + str(currEnd) + ")")
            if currSeg == 0: #Already finish the process of merging close segments, now starting a new segment
                currSeg = 1
                currEnd = end;
                currStart = start;
            else: # In the process of merging close segments
                if start - currEnd <= tollerance: #The segment aSeg can be merged into the current segment
                    currEnd = end;
                else:#The previous segment is too far from the current segment => Write down the previous segment and start new segment
                    if(currEnd - currStart) < discardShortSegLength: #The current segment is too short
                        print("Discard short segment " + str(round(currStart,2)) + " " + str(round(currEnd,2)))
                        #logger(Const.CROSSTALK_LOGGER_NAME).info("Discard short segment " + str(currStart) + " " + str(currEnd))
                    else:
                        #logger(Const.CROSSTALK_LOGGER_NAME).info("Speech " + str(currStart) + " " + str(currEnd))
                        actStart = currStart - buffExt
                        actEnd = currEnd + buffExt
                        if actStart < 0:
                            actStart = 0
                        if actEnd > maxLength:
                            actEnd = maxLength
                        print("Speech " + str(round(currStart,2)) + " " + str(round(currEnd,2)))
                        if round(currEnd,2 ) - round(actStart,2 ) >= 0.05:
                            wf.write(str(round(currStart, 2)) + " " + str(round(currEnd,2 )) +  " unknowSpk\n" )
                            wf2.write("speech " + str(round(actStart, 2)) + " " + str(round(actEnd, 2)) +  "\n" )
                    currStart = start
                    currEnd = end
                    currSeg = 1
    
    actStart = currStart - buffExt
    actEnd = currEnd + buffExt
    if actStart < 0:
        actStart = 0
    if actEnd > maxLength:
        actEnd = maxLength
    print("Speech " + str(round(currStart,2)) + " " + str(round(currEnd,2)))
    if round(currEnd,2 ) - round(currStart,2 ) >= tollerance:
        wf.write(str(round(currStart, 2)) + " " + str(round(currEnd,2 )) +  " unknowSpk\n" )
        wf2.write(str(actStart) + " " + str(actEnd) +  "\n" )
    wf.close()
    wf2.close()

outid = int(sys.argv[1])
infolder = sys.argv[2]
out_fold = sys.argv[3]
discardShortSeg2 = float(sys.argv[4]) ### discard segment shorter than a threshold, e.g. 1.0
tollerance2 = float(sys.argv[5]) ### merge two consecutive segments that closer than a threshold, e.g. 0.4

print('---- discardShortSeg2 ' + str(discardShortSeg2) + ', tollerance2 = ' + str(tollerance2))

if outid <= 10:
    chnk = "0" + str(int(outid)-1)
else:
    chnk = str(int(outid)-1)

pfile = infolder + '/' + chnk

listfile = readList(pfile)
for dnn_output in listfile:
    print('Process file ' + dnn_output)
    filename = os.path.splitext(dnn_output)[0].split("/")[-1]
    currChanVAD = numpy.loadtxt(dnn_output)
    vad_seg = label2seg(currChanVAD)
    maxLength = len(currChanVAD)
    buffExt = 0.2
    writeSeg(vad_seg, "tmp_new3.txt", maxLength, buffExt, discardShortSeg2, tollerance2, "tmp_new4.txt", out_fold + '/' + filename + '.txt')