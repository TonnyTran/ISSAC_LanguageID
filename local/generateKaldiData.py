from __future__ import print_function

import numpy
import os
import sys

def generateMappingAudio2Infor(wavscpfile):
    rec2inf = {}
    f = open(wavscpfile, 'r')
    line = f.readline()
    while line:
        row = line.split()
        rec2inf[row[0]] = row[1]
        line = f.readline()
    f.close()
    return rec2inf



def generateData(segments, rec2ageSre08, rec2ageSre10, rec2spk08, rec2spk10, outfold):
    f = open(segments, 'r')
    fwUtt2age = open(outfold + '/utt2age', 'w')
    fwUtt2spk = open(outfold + '/utt2spk', 'w')
    fwText = open(outfold + '/text', 'w')
    line = f.readline()
    while line:
        row = line.split()
        if row[1] in rec2ageSre08:
            age = rec2ageSre08[row[1]]
        elif row[1] in rec2ageSre10:
            age = rec2ageSre10[row[1]]
        else:
            print('Cannot find age for recording ' + row[1])
            sys.exit(1)
        fwUtt2age.write(row[0] + ' ' + age + '\n')

        if row[1] in rec2spk08:
            spk = rec2spk08[row[1]]
        elif row[1] in rec2spk10:
            spk = rec2spk10[row[1]]
        else:
            print('Cannot find spk for recording ' + row[1])
            sys.exit(1)
        fwUtt2spk.write(row[0] + ' ' + spk + '\n')
        fwText.write(row[0] + ' text' + '\n')
        
        line = f.readline()
    f.close()
    fwUtt2age.close()
    fwUtt2spk.close()
    fwText.close()

segments = sys.argv[1]
sre08 = sys.argv[2]
sre10 = sys.argv[3]

folder = '/'.join(segments.split("/")[:-1])
print('Folder = ' + folder)

rec2ageSre08 = generateMappingAudio2Infor(sre08 + '/utt2age')
rec2ageSre10 = generateMappingAudio2Infor(sre10 + '/utt2age')
rec2spk08 = generateMappingAudio2Infor(sre08 + '/utt2spk')
rec2spk10 = generateMappingAudio2Infor(sre10 + '/utt2spk')

generateData(segments, rec2ageSre08, rec2ageSre10, rec2spk08, rec2spk10, folder)