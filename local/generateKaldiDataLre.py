from __future__ import print_function

import numpy
import os
import sys

langArr = ["ara-acm","ara-apc","ara-ary","ara-arz","eng-gbr","eng-usg","por-brz","qsl-pol","qsl-rus","spa-car","spa-eur","spa-lac","zho-cmn","zho-nan"]

def generateMappingAudio2Infor(wavscpfile):
    rec2inf = {}
    f = open(wavscpfile, 'r')
    line = f.readline()
    while line:
        row = line.split()
        rec2inf[row[0]] = ' '.join(row[1:])
        line = f.readline()
    f.close()
    return rec2inf

def generateData(segments, rec2lang, rec2spk, rec2path, outdir):
    f = open(segments, 'r')
    fwUtt2lang = open(outdir + '/utt2lang', 'w')
    fwUtt2spk = open(outdir + '/utt2spk', 'w')
    fwText = open(outdir + '/text', 'w')
    fwUtt2label = open(outdir + '/utt2label', 'w')
    fwWavScp = open(outdir + '/wav.scp', 'w')
    fwSegments = open(outdir + '/segments', 'w')

    wavDict = {}
    line = f.readline()
    while line:
        row = line.split()
        orgUttName = row[1]
        newUttName = row[0]
        startTime = row[2]
        endTime = row[3]
        lang = rec2lang[orgUttName]
        # print(lang)
        langId = langArr.index(lang)
        path = rec2path[orgUttName]
        temp = lang + '-' + orgUttName
        if temp not in wavDict.keys():
            temp = temp.replace('.', '-').replace('_', '-')
            wavDict[temp] = path

        orgUttName = orgUttName.replace('.', '-').replace('_', '-')
        newUttName = newUttName.replace('.', '-').replace('_', '-') 
        fwUtt2lang.write(lang + '-' + newUttName + ' ' + lang + '\n')
        fwUtt2spk.write(lang + '-' + newUttName + ' ' + lang + '-' + orgUttName + '\n')
        fwText.write(lang + '-' + newUttName + ' ' + 'transcription' + '\n')
        fwUtt2label.write(lang + '-' + newUttName + ' ' + str(langId) + '\n')
        fwSegments.write(lang + '-' + newUttName + ' ' + lang + '-' + orgUttName + ' ' + startTime + ' ' + endTime + '\n')

        line = f.readline()

    for key in wavDict.keys():
        fwWavScp.write(key + ' ' + wavDict[key] + '\n')

    f.close()
    fwUtt2lang.close()
    fwUtt2spk.close()
    fwText.close()
    fwUtt2label.close()
    fwWavScp.close()
    fwSegments.close()

segments = sys.argv[1]
wav_scp = sys.argv[2]
utt2spk = sys.argv[3]
utt2lang = sys.argv[4]
outdir = sys.argv[5]

rec2lang = generateMappingAudio2Infor(utt2lang)
rec2spk = generateMappingAudio2Infor(utt2spk)
rec2path = generateMappingAudio2Infor(wav_scp)

generateData(segments, rec2lang, rec2spk, rec2path, outdir)
