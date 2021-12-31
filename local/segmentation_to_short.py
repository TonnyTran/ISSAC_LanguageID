from __future__ import print_function

import numpy
import os
import sys

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

def convertStr(num):
    valInt = int(num * 100)
    if valInt < 10:
        return "0000" + str(valInt)
    elif valInt < 100:
        return "000" + str(valInt)
    elif valInt < 1000:
        return "00" + str(valInt) 
    elif valInt < 10000:
        return "0" + str(valInt) 
    else:
        return str(valInt)


def generateFixLengthSegsFromASeg(start, end, fixLength, hopLength):
    listSegs = []
    currStart = start
    # hopLength = fixLength/10.0
    currEnd = currStart + fixLength
    while currEnd <= end:
        listSegs.append([round(currStart, 2), round(currEnd, 2)])
        currStart += hopLength
        currEnd += hopLength
    currEnd = end
    listSegs.append([round(currStart, 2), round(currEnd, 2)])
    return listSegs

def generateSegmentFromVAD(fullname, fw, fixLength, hopLength):
    f = open(fullname, 'r')
    filename = os.path.splitext(fullname)[0].split("/")[-1]
    print('File name only = ' + str(filename))
    line = f.readline()
    while line:
        row = line.split()
        listSegs = generateFixLengthSegsFromASeg(float(row[0]), float(row[1]), fixLength, hopLength)
        for seg in listSegs:
            st, et = seg[0], seg[1]
            fw.write(filename + "_" + convertStr(st) + "_" + convertStr(et) + " " + filename + " " + str(st) + " " + str(et) + "\n")
        line = f.readline()
    f.close()

def processSegmentation(utt2spk, vadFolder, segmentsOut, fixLength, hopLength):
    f = open(utt2spk, 'r')
    line = f.readline()
    fw = open(segmentsOut, 'w')

    number = 0
    while line:
        row = line.split()
        vadfile = vadFolder + "/" + row[0] + ".txt"
        if (os.path.exists(vadfile)):
           print('============ Process the vad file ' + vadfile + ' ==================')
           generateSegmentFromVAD(vadfile, fw, fixLength, hopLength)
        else:
           number += 1
           print('============ Can not find the vad file ' + vadfile + ' ==================')
        line = f.readline()

    print('============ Total ' + str(number) + ' vad file can not find ==================')
    f.close() 
    fw.close()

utt2spk = sys.argv[1]
vadFolder = sys.argv[2]
segmentsOut = sys.argv[3]
fixLength = float(sys.argv[4])
hopLength = float(sys.argv[5])

processSegmentation(utt2spk, vadFolder, segmentsOut, fixLength, hopLength)



    
